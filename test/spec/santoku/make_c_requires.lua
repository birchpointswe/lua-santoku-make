-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2023 Birch Point SWE
local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local sys = require("santoku.system")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/c-requires")

local files = {
  ["make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "crfixture",
    version = "0.0.1-1",
    license = "MIT",
    public = false,
    dependencies = { "lua == 5.1" },
  },
}
]],
  ["lib/fx/b.h"] = "#define FX_B_MODULE \"fx.b\"\n",
  ["lib/fx/b.c"] = [[
#include <lua.h>
#include <lauxlib.h>

int luaopen_fx_b (lua_State *L)
{
  lua_pushstring(L, "from b");
  return 1;
}
]],
  ["lib/fx/a.c"] = [[
#include <lua.h>
#include <lauxlib.h>
#include <fx/b.h>

int luaopen_fx_a (lua_State *L)
{
  lua_getglobal(L, "require");
  lua_pushstring(L, FX_B_MODULE);
  lua_call(L, 1, 1);
  return 1;
}
]],
  ["lib/fx/c.c"] = [[
#include <lua.h>
#include <lauxlib.h>
#include <fx/b.h>

int luaopen_fx_c (lua_State *L)
{
  lua_pushstring(L, "from c");
  return 1;
}
]],
  ["test/spec/fx.lua"] = "assert(require(\"fx.a\") == \"from b\")\nassert(require(\"fx.c\") == \"from c\")\n",
}

local function write_files (dir)
  sys.execute({ "rm", "-rf", dir })
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function requires (env, name)
  return fs.readfile(fs.join("build", env, "test", "lib", "fx", name .. ".requires"))
end

test("a C module's .requires lists the included siblings its object uses", function ()
  write_files(root)
  fs.pushd(root, function ()
    project.init().test({ skip_check = true })
    assert(eq("fx.b\n", requires("default", "a")), "fx/a includes fx/b.h, so it requires fx.b")
    assert(eq("", requires("default", "b")), "fx/b includes no sibling header")
    assert(eq("", requires("default", "c")), "fx/c includes fx/b.h but never uses fx.b, so it requires nothing")
  end)
end)

test("a wasm bundle follows a C module's .requires to its sibling", function ()
  fs.pushd(root, function ()
    project.init({ wasm = true }).test({ skip_check = true })
    assert(eq("fx.b\n", requires("default-wasm", "a")))
  end)
end)

sys.execute({ "rm", "-rf", root })
