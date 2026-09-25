local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local err = require("santoku.error")
local posix = require("santoku.make.posix")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/relink")

local descriptor = [[
return {
  type = "lib",
  env = {
    name = "relinkfixture",
    version = "0.0.1-1",
    ldflags = { "$(PWD)/deps/bar/libbar.a" },
    dependencies = { "lua == 5.1" },
  },
}
]]

local function dep_makefile (value)
  return str.interp(
    "results.mk: Makefile\n" ..
    "\t$(CC) -c -fPIC -DBAR_VALUE=%1 $(CFLAGS) -o bar.o bar.c\n" ..
    "\t$(AR) rcs libbar.a bar.o\n" ..
    "\ttouch results.mk\n", { value })
end

local function module_h (value)
  return str.interp("#define FIXTURE_OFFSET %1\n", { value })
end

local module_c = [[
#include "lua.h"
#include "lauxlib.h"
#include "relinkfixture.h"
int bar (void);
static int l_bar (lua_State *L)
{
  lua_pushinteger(L, bar() + FIXTURE_OFFSET);
  return 1;
}
int luaopen_relinkfixture (lua_State *L)
{
  lua_newtable(L);
  lua_pushcfunction(L, l_bar);
  lua_setfield(L, -2, "bar");
  return 1;
}
]]

local function write_project (dir)
  sys.execute({ "rm", "-rf", dir })
  local files = {
    ["make.lua"] = descriptor,
    ["deps/bar/Makefile"] = dep_makefile("1"),
    ["deps/bar/bar.c"] = "int bar (void) { return BAR_VALUE; }\n",
    ["lib/relinkfixture.c"] = module_c,
    ["lib/relinkfixture.h"] = module_h("10"),
  }
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function so_file (dir)
  return fs.join(dir, "build", "default", "test", "lib", "relinkfixture.so")
end

local function build (dir)
  return fs.pushd(dir, function ()
    project.init({}).exec({ "true" })
  end)
end

local function settle (dir)
  for _ = 1, 5 do
    local before = posix.time(so_file(dir))
    sys.sleep(1.1)
    build(dir)
    if posix.time(so_file(dir)) == before then
      return true
    end
  end
end

test("a rebuilt archive relinks the module that links it, and nothing else relinks", function ()

  local dir = fs.join(root, "archive")
  write_project(dir)
  build(dir)
  assert(settle(dir), "a rebuild with no input change must stop relinking the module")
  local first = fs.readfile(so_file(dir))

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "deps/bar/Makefile"), dep_makefile("2"))
  build(dir)
  assert(first ~= fs.readfile(so_file(dir)),
    "a changed archive must relink the module, so its bytes must change")

  sys.execute({ "rm", "-rf", dir })

end)

test("an edited header recompiles the module that includes it", function ()

  local dir = fs.join(root, "header")
  write_project(dir)
  build(dir)
  assert(settle(dir), "a rebuild with no input change must stop recompiling the module")
  local first = fs.readfile(so_file(dir))

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "lib/relinkfixture.h"), module_h("20"))
  build(dir)
  assert(first ~= fs.readfile(so_file(dir)),
    "a changed header must recompile the module, so its bytes must change")

  sys.execute({ "rm", "-rf", dir })

end)

test("a vendored results.mk rule without a Makefile prerequisite fails the build", function ()

  local dir = fs.join(root, "unguarded")
  write_project(dir)
  fs.writefile(fs.join(dir, "deps/bar/Makefile"),
    (str.gsub(dep_makefile("1"), "^results.mk: Makefile", "results.mk:")))
  local ok = err.pcall(build, dir)
  assert(eq(false, ok), "the build must refuse a results.mk rule that omits Makefile")
  assert(eq(false, fs.exists(so_file(dir))), "the module must not be built")

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
