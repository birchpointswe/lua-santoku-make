-- WASM build utilities for Lua projects

local fs = require("santoku.fs")
local sys = require("santoku.system")
local arr = require("santoku.array")

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
      fs.cd("lua-5.1.5")
      sys.execute({ "emmake", "sh", "-c", arr.concat({
        "make", "generic",
        "CC=\"$CC\"",
        "LD=\"$LD\"",
        "AR=\"$AR rcu\"",
        "RANLIB=\"$RANLIB\"",
        "CFLAGS=\"-flto -Oz\"",
        "MYLDFLAGS=\"-flto -Oz\""
      }, " ") })
      sys.execute({ "make", "local" })
      fs.cd("bin")
      sys.execute({ "mv", "lua", "lua.js" })
      sys.execute({ "mv", "luac", "luac.js" })
      fs.writefile("lua", "#!/bin/sh\nnode \"$(dirname $0)/lua.js\" \"$@\"\n")
      fs.writefile("luac", "#!/bin/sh\nnode \"$(dirname $0)/luac.js\" \"$@\"\n")
      sys.execute({ "chmod", "+x", "lua" })
      sys.execute({ "chmod", "+x", "luac" })
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
    "-sSINGLE_FILE",
    "-sALLOW_MEMORY_GROWTH",
    "-I" .. fs.join(lua_dir, "include"),
    "-L" .. fs.join(lua_dir, "lib"),
  }

  -- Test context needs node filesystem access
  if context == "test" then
    arr.extend(flags, { "-lnodefs.js", "-lnoderawfs.js" })
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

return {
  setup_lua = setup_lua,
  get_bundle_flags = get_bundle_flags,
  create_node_wrapper = create_node_wrapper,
}
