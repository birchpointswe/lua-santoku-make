local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/generated")

local descriptor = [[
local fs = require("santoku.fs")
return {
  type = "web",
  env = {
    name = "genshape",
    version = "0.0.1-1",
    client = {
      generated = { "lib/gen/data.lua" },
    },
    server = {},
    nginx = { domain = "localhost", port = "8080", workers = 1 },
    configure = function (submake, envs)
      local client_env = envs.client
      if not client_env then return end
      local src = fs.join(client_env.root_dir, "res/gen-input.txt")
      local out = fs.join(client_env.work_dir, "lib/gen/data.lua")
      submake.target({ out }, { src }, function ()
        fs.mkdirp(fs.dirname(out))
        fs.writefile(out, fs.readfile(src))
      end)
    end,
  },
}
]]

local template = [[<% fs = require("santoku.fs") %><!doctype html><body><% return readfile(fs.join(work_dir, "lib/gen/data.lua")) %></body>
]]

local function write_shape (dir)
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  local files = {
    ["client/static/index.tk.html"] = template,
    ["res/gen-input.txt"] = "MARKER-v1",
    ["make.lua"] = descriptor,
  }
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function build_hash (dir)
  return fs.pushd(dir, function ()
    local p = project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    })
    p.submake.build({ fs.join(fs.absolute("build"), "default", "main", "dist", "hash.ok") }, 0)
  end)
end

test("client.generated orders the generator before templated renders on a cold build", function ()
  local dir = fs.join(root, "cold")
  write_shape(dir)
  build_hash(dir)
  local staged = fs.join(dir, "build", "default", "main", "dist", "public-staging", "index.html")
  assert(eq(true, fs.exists(staged)))
  assert(str.find(fs.readfile(staged), "MARKER-v1", 1, true))
  local out = fs.join(dir, "build", "default", "main", "client", "lib", "gen", "data.lua")
  assert(eq("MARKER-v1", fs.readfile(out)))
  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "res/gen-input.txt"), "MARKER-v2")
  build_hash(dir)
  assert(eq("MARKER-v2", fs.readfile(out)))
  assert(str.find(fs.readfile(staged), "MARKER-v2", 1, true))
  sys.execute({ "rm", "-rf", dir })
end)

sys.execute({ "rm", "-rf", root })
