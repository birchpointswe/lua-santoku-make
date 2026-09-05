
local fs = require("santoku.fs")
local sys = require("santoku.system")
local arr = require("santoku.array")
local str = require("santoku.string")
local vendor = require("santoku.make.vendor")

local lua_tarball_url =
  "https://www.lua.org/ftp/lua-5.1.5.tar.gz"
local lua_tarball_sha256 =
  "2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333"

local function setup_lua(target_fn, dir)
  local lua_dir = fs.join(dir, "lua-5.1.5")
  local lua_ok = lua_dir .. ".ok"

  target_fn({ lua_ok }, {}, function ()
    fs.mkdirp(dir)
    return fs.pushd(dir, function ()
      vendor.fetch({ url = lua_tarball_url, sha256 = lua_tarball_sha256 }, "lua-5.1.5.tar.gz")
      if fs.exists("lua-5.1.5") then
        sys.execute({ "rm", "-rf", "lua-5.1.5" })
      end
      sys.execute({ "tar", "xf", "lua-5.1.5.tar.gz" })
      fs.pushd("lua-5.1.5", function ()
        fs.pushd("src", function ()
          sys.execute({ "emmake", "sh", "-c", arr.concat({
            "make", "--no-print-directory", "all",
            "CC=\"$CC\"",
            "AR=\"$AR rcu\"",
            "RANLIB=\"$RANLIB\"",
            "MYCFLAGS=\"-w -flto -Oz\"",
            "MYLDFLAGS=\"-flto -Oz -sSINGLE_FILE -lnodefs.js -lnoderawfs.js\""
          }, " ") })
        end)
        sys.execute({ "make", "--no-print-directory", "local" })
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

local web_flags = {
  "-sWASM_BIGINT",
  "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
  "-sEXPORTED_FUNCTIONS=_main,_malloc,_free",
  "-sEXPORTED_RUNTIME_METHODS=stringToUTF8,lengthBytesUTF8,UTF8ToString,stringToNewUTF8,HEAPU8",
  "-sENVIRONMENT=web,worker",
  "-sABORT_ON_WASM_EXCEPTIONS=0",
}

local function setting_name(flag)
  if type(flag) ~= "string" then
    return nil
  end
  return str.match(flag, "^%-s([%w_]+)")
end

local function get_web_flags(extras)
  local overridden = {}
  local i = 1
  while i <= #extras do
    if extras[i] == "-s" then
      local next_flag = extras[i + 1]
      local n = type(next_flag) == "string" and str.match(next_flag, "^([%w_]+)") or nil
      if n then overridden[n] = true end
      i = i + 2
    else
      local n = setting_name(extras[i])
      if n then overridden[n] = true end
      i = i + 1
    end
  end
  local flags = {}
  for j = 1, #web_flags do
    if not overridden[setting_name(web_flags[j])] then
      arr.push(flags, web_flags[j])
    end
  end
  return flags
end

local function get_bundle_flags(lua_dir, context, extra_cflags, extra_ldflags)
  local extras = arr.flatten({ extra_cflags or {}, extra_ldflags or {} })
  local node_cli = context == "test" or context == "install"
  return arr.flatten({
    context == "test"
      and { "-sASSERTIONS" }
      or { "-Oz", "-sASSERTIONS=0", "--closure", "0", "-sMALLOC=emmalloc",
           "-sTEXTDECODER=2", "-sEVAL_CTORS" },
    not node_cli and { "-sNO_EXIT_RUNTIME" } or {},
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. fs.join(lua_dir, "include"),
    "-L" .. fs.join(lua_dir, "lib"),
    node_cli and { "-sSINGLE_FILE", "-lnodefs.js", "-lnoderawfs.js" } or {},
    "-llua", "-lm",
    context == "web" and get_web_flags(extras) or {},
    extras,
  })
end

local function create_node_wrapper(dest, js_file)
  local wrapper = str.format([[#!/bin/sh
exec node "$(dirname "$0")/%s" "$@"
]], fs.basename(js_file))
  fs.writefile(dest, wrapper)
  sys.execute({ "chmod", "+x", dest })
end

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

local function build_embed(entry_lua, outdir, opts)
  opts = opts or {}
  local lua_dir = opts.lua_dir
  local lua_modules_dir = opts.lua_modules_dir
  local extra_flags = opts.flags or {}

  local outprefix = opts.outprefix or fs.stripextensions(fs.basename(entry_lua))
  local outcfp = fs.join(outdir, outprefix .. ".embed.c")
  local outmainfp = fs.join(outdir, outprefix)

  local lua_path = "/lua_modules/share/lua/5.1/?.lua;/lua_modules/share/lua/5.1/?/init.lua;/lua_modules/lib/lua/5.1/?.lua;/lua_modules/lib/lua/5.1/?/init.lua;;"
  local lua_cpath = "/lua_modules/lib/lua/5.1/?.so;;"

  local entry_vfs_path = "/" .. fs.basename(entry_lua)

  local c_code = str.format(embed_main_template, lua_path, lua_cpath, entry_vfs_path)

  fs.mkdirp(outdir)
  fs.writefile(outcfp, c_code)

  local args = arr.flatten({
    "emcc",
    outcfp,
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. fs.join(lua_dir, "include"),
    "-L" .. fs.join(lua_dir, "lib"),
    "-llua", "-lm",
    "--embed-file", lua_modules_dir .. "@/lua_modules",
    "--embed-file", entry_lua .. "@" .. entry_vfs_path,
    extra_flags,
    "-o", outmainfp,
  })

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
