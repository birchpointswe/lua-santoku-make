local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
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

local template = "<% return nginx.workers %>|<% return nginx.extra %>\n"

local function write_project (dir)
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  local files = {
    ["make.lua"] = descriptor,
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

local function build (dir, verbosity)
  return fs.pushd(dir, function ()
    local p = project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    })
    p.submake.build({ fs.absolute(out_file(".")) }, verbosity or 0)
  end)
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

  sys.sleep(1.1)
  local stamp_at = posix.time(stamp_file(dir))
  local out_at = posix.time(out_file(dir))
  build(dir)
  assert(eq(stamp_at, posix.time(stamp_file(dir))),
    "an unchanged environment must leave the stamp untouched")
  assert(eq(out_at, posix.time(out_file(dir))),
    "an unchanged environment must not re-render")

  sys.sleep(1.1)
  sys.setenv("WORKERS", "2")
  build(dir)
  assert(eq("2|one", fs.readfile(out_file(dir))))

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "make.common.lua"), "return { extra = \"two\" }\n")
  build(dir)
  assert(eq("2|two", fs.readfile(out_file(dir))))

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
