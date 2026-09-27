local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local err = require("santoku.error")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/lua-env")

local function write_files (dir, files)
  sys.execute({ "rm", "-rf", dir })
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function all_absolute (paths)
  for p in str.gmatch(paths, "[^;]+") do
    if str.sub(p, 1, 1) ~= "/" then
      return false, p
    end
  end
  return true
end

local function requires_from_elsewhere (t, module)
  return fs.pushd("/", function ()
    return err.pcall(sys.execute, {
      t.lua, "-e", "assert(require('" .. module .. "') == 'ok')",
      env = { LUA_PATH = t.lua_path, LUA_CPATH = t.lua_cpath },
    })
  end)
end

test("a lib project's test tree resolves its modules from any directory", function ()

  local dir = fs.join(root, "lib")
  write_files(dir, {
    ["make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "luaenvfixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
  },
}
]],
    ["lib/luaenvfixture.lua"] = "return \"ok\"\n",
  })

  local t = fs.pushd(dir, function ()
    return project.init({}).lua_env("test")
  end)
  assert(eq(true, (all_absolute(t.lua_path))), "every lua_path entry must be absolute")
  assert(eq(true, (all_absolute(t.lua_cpath))), "every lua_cpath entry must be absolute")
  assert(eq(true, (requires_from_elsewhere(t, "luaenvfixture"))),
    "the test tree must resolve the project's module from another directory")

  local ok, msg = fs.pushd(dir, function ()
    return err.pcall(project.init({}).lua_env, "build")
  end)
  assert(eq(false, ok))
  assert(str.find(tostring(msg), "toku install", 1, true), "the build tree error must point at toku install")

  sys.execute({ "rm", "-rf", dir })

end)

test("a web project's test tree resolves its server modules from any directory", function ()

  local dir = fs.join(root, "web")
  write_files(dir, {
    ["make.lua"] = [[
return {
  type = "web",
  env = {
    name = "webenvfixture",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = { domain = "localhost", port = "8080" },
  },
}
]],
    ["server/lib/webenvfixture.lua"] = "return \"ok\"\n",
  })

  local t = fs.pushd(dir, function ()
    return project.init({ openresty_dir = "/nonexistent" }).lua_env("test")
  end)
  assert(eq(true, (all_absolute(t.lua_path))), "every lua_path entry must be absolute")
  assert(eq(true, (requires_from_elsewhere(t, "webenvfixture"))),
    "the test tree must resolve the server module from another directory")

  local ok = fs.pushd(dir, function ()
    return err.pcall(project.init({ openresty_dir = "/nonexistent" }).lua_env, "client")
  end)
  assert(eq(false, ok), "an unknown tree must be refused")

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
