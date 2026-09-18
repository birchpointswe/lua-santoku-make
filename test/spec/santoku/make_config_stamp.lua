local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local posix = require("santoku.make.posix")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/config-stamp")

local descriptor = [[
local env = require("santoku.env")
local fs = require("santoku.fs")
local base = fs.runfile("make.common.lua")
return {
  type = "web",
  env = {
    name = "envshape",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = {
      domain = "localhost",
      port = "8080",
      workers = env.var("WORKERS", "auto"),
      extra = base.extra,
    },
  },
}
]]

local mutating_descriptor = [[
local env = require("santoku.env")
return {
  type = "web",
  env = {
    name = "envshape",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = {
      domain = "localhost",
      port = "8080",
      workers = env.var("WORKERS", "auto"),
      extra = "one",
    },
    configure = function (submake, envs)
      local nginx = envs.root.nginx
      nginx.rounds = (nginx.rounds or 0) + 1
      envs.root.server.rounds = nginx.rounds
    end,
  },
}
]]

local template = "<% return nginx.workers %>|<% return nginx.extra %>\n"

local function write_project (dir, desc)
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  local files = {
    ["make.lua"] = desc or descriptor,
    ["make.common.lua"] = "return { extra = \"one\" }\n",
    ["client/static/index.tk.html"] = template,
  }
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function out_file (dir)
  return fs.join(dir, "build", "default", "main", "dist", "public-staging", "index.html")
end

local function stamp_file (dir)
  return fs.join(dir, "build", "default", "config.stamp")
end

local function build (dir)
  return fs.pushd(dir, function ()
    local p = project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    })
    p.submake.build({ fs.absolute(out_file(".")) }, 0)
  end)
end

local function marks (dir)
  return str.format("%d:%d", posix.time(stamp_file(dir)), posix.time(out_file(dir)))
end

local function settle (dir, limit)
  for i = 1, limit do
    local before = marks(dir)
    sys.sleep(1.1)
    build(dir)
    if marks(dir) == before then
      return i
    end
  end
end

test("the resolved environment invalidates descriptor-dependent targets", function ()

  local dir = fs.join(root, "workers")
  write_project(dir)

  sys.setenv("WORKERS", "auto")
  build(dir)
  assert(eq("auto|one", fs.readfile(out_file(dir))))

  sys.sleep(1.1)
  sys.setenv("WORKERS", "4")
  build(dir)
  assert(eq("4|one", fs.readfile(out_file(dir))))

  local stamp_at = posix.time(stamp_file(dir))
  assert(settle(dir, 5), "identical builds must reach a fixed point")
  assert(eq(stamp_at, posix.time(stamp_file(dir))),
    "an unchanged environment must never rewrite the stamp")
  assert(eq("4|one", fs.readfile(out_file(dir))))

  sys.sleep(1.1)
  sys.setenv("WORKERS", "2")
  build(dir)
  assert(eq("2|one", fs.readfile(out_file(dir))))

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "make.common.lua"), "return { extra = \"two\" }\n")
  build(dir)
  assert(eq("2|two", fs.readfile(out_file(dir))))

  assert(settle(dir, 5), "identical builds must reach a fixed point after a config edit")

  sys.execute({ "rm", "-rf", dir })

end)

test("a configure hook that mutates the config cannot destabilise the stamp", function ()

  local dir = fs.join(root, "mutating")
  write_project(dir, mutating_descriptor)

  sys.setenv("WORKERS", "auto")
  build(dir)
  assert(eq("auto|one", fs.readfile(out_file(dir))))

  local stamp_at = posix.time(stamp_file(dir))
  assert(settle(dir, 5), "a mutating configure hook must still reach a fixed point")
  assert(eq(stamp_at, posix.time(stamp_file(dir))),
    "configure mutations must not reach the stamp")

  sys.sleep(1.1)
  sys.setenv("WORKERS", "4")
  build(dir)
  assert(eq("4|one", fs.readfile(out_file(dir))))

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
