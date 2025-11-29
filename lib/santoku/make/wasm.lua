-- WASM build utilities for Lua projects

local fs = require("santoku.fs")
local sys = require("santoku.system")
local arr = require("santoku.array")
local str = require("santoku.string")

-- Compile Lua 5.1.5 with emscripten for WASM builds
-- Returns lua_dir path and lua_ok marker file path
local function setup_lua(target_fn, dir)
  local lua_dir = fs.join(dir, "lua-5.1.5")
  local lua_ok = lua_dir .. ".ok"

  target_fn({ lua_ok }, {}, function ()
    fs.mkdirp(dir)
    return fs.pushd(dir, function ()
      if not fs.exists("lua-5.1.5.tar.gz") then
        sys.execute({ "wget", "https://www.lua.org/ftp/lua-5.1.5.tar.gz" })
      end
      if fs.exists("lua-5.1.5") then
        sys.execute({ "rm", "-rf", "lua-5.1.5" })
      end
      sys.execute({ "tar", "xf", "lua-5.1.5.tar.gz" })
      fs.pushd("lua-5.1.5", function ()
        fs.pushd("src", function ()
          sys.execute({ "emmake", "sh", "-c", arr.concat({
            "make", "all",
            "CC=\"$CC\"",
            "AR=\"$AR rcu\"",
            "RANLIB=\"$RANLIB\"",
            "MYCFLAGS=\"-flto -Oz\"",
            "MYLDFLAGS=\"-flto -Oz -sSINGLE_FILE -lnodefs.js -lnoderawfs.js\""
          }, " ") })
        end)
        sys.execute({ "make", "local" })
        fs.pushd("bin", function ()
          sys.execute({ "mv", "lua", "lua.js" })
          sys.execute({ "mv", "luac", "luac.js" })
          fs.writefile("lua", "#!/bin/sh\nnode \"$(dirname $0)/lua.js\" \"$@\"\n")
          fs.writefile("luac", "#!/bin/sh\nnode \"$(dirname $0)/luac.js\" \"$@\"\n")
          sys.execute({ "chmod", "+x", "lua" })
          sys.execute({ "chmod", "+x", "luac" })
        end)
      end)
      fs.touch(lua_ok)
    end)
  end)

  return lua_dir, lua_ok
end

-- Get standard emcc bundle flags for WASM builds
-- context: "test" adds node filesystem support, "build" is for production
local function get_bundle_flags(lua_dir, context, extra_cflags, extra_ldflags)
  extra_cflags = extra_cflags or {}
  extra_ldflags = extra_ldflags or {}

  local flags = {
    "-sASSERTIONS",
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. fs.join(lua_dir, "include"),
    "-L" .. fs.join(lua_dir, "lib"),
  }

  -- Test context needs node filesystem access and single file for simplicity
  if context == "test" then
    arr.extend(flags, { "-sSINGLE_FILE", "-lnodefs.js", "-lnoderawfs.js" })
  end

  arr.extend(flags, { "-llua", "-lm" })
  arr.extend(flags, extra_cflags)
  arr.extend(flags, extra_ldflags)

  return flags
end

-- Create a node wrapper script for a WASM executable
local function create_node_wrapper(dest, js_file)
  local wrapper = string.format([[#!/bin/sh
exec node "%s" "$@"
]], js_file)
  fs.writefile(dest, wrapper)
  sys.execute({ "chmod", "+x", dest })
end

-- C entry point template for embed mode (runs Lua files from embedded filesystem)
local embed_main_template = [[
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdlib.h"

int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    fprintf(stderr, "Failed to create Lua state\n");
    return 1;
  }

  luaL_openlibs(L);

  // Set up package.path and package.cpath for embedded filesystem
  lua_getglobal(L, "package");
  lua_pushstring(L, "%s");
  lua_setfield(L, -2, "path");
  lua_pushstring(L, "%s");
  lua_setfield(L, -2, "cpath");
  lua_pop(L, 1);

  // Set up arg table
  lua_createtable(L, argc, 0);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }
  lua_setglobal(L, "arg");

  // Run the entry point
  int rc = luaL_dofile(L, "%s");
  if (rc != 0) {
    fprintf(stderr, "%%s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }

  lua_close(L);
  return 0;
}
]]

-- Build with embedded filesystem (dev mode) for interpretable stack traces
-- Instead of bundling Lua into bytecode, embeds lua_modules directory
local function build_embed(entry_lua, outdir, opts)
  opts = opts or {}
  local lua_dir = opts.lua_dir
  local lua_modules_dir = opts.lua_modules_dir
  local extra_flags = opts.flags or {}

  local outprefix = opts.outprefix or fs.stripextensions(fs.basename(entry_lua))
  local outcfp = fs.join(outdir, outprefix .. ".embed.c")
  local outmainfp = fs.join(outdir, outprefix)

  -- Generate package paths for embedded filesystem
  local lua_path = "/lua_modules/share/lua/5.1/?.lua;/lua_modules/share/lua/5.1/?/init.lua;/lua_modules/lib/lua/5.1/?.lua;/lua_modules/lib/lua/5.1/?/init.lua;;"
  local lua_cpath = "/lua_modules/lib/lua/5.1/?.so;;"

  -- Determine entry point path in virtual filesystem
  local entry_vfs_path = "/" .. fs.basename(entry_lua)

  -- Generate C code
  local c_code = str.format(embed_main_template, lua_path, lua_cpath, entry_vfs_path)

  fs.mkdirp(outdir)
  fs.writefile(outcfp, c_code)

  -- Build with emcc, embedding the lua_modules directory and entry file
  local args = {
    "emcc",
    outcfp,
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. fs.join(lua_dir, "include"),
    "-L" .. fs.join(lua_dir, "lib"),
    "-llua", "-lm",
    "--embed-file", lua_modules_dir .. "@/lua_modules",
    "--embed-file", entry_lua .. "@" .. entry_vfs_path,
  }

  arr.extend(args, extra_flags)
  arr.push(args, "-o", outmainfp)

  print(arr.concat(args, " "))
  sys.execute(args)

  return outmainfp
end

return {
  setup_lua = setup_lua,
  get_bundle_flags = get_bundle_flags,
  create_node_wrapper = create_node_wrapper,
  build_embed = build_embed,
}
