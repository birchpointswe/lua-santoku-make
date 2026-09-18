local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local neq = validate.isnotequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
local str = require("santoku.string")
local sys = require("santoku.system")
local posix = require("santoku.make.posix")
local common = require("santoku.make.common")

local dir = "test/res/discovery"

local function names (t)
  local out = {}
  for i = 1, #t do
    out[i] = fs.basename(t[i])
  end
  arr.sort(out)
  return arr.concat(out, ",")
end

test("get_action ignores dependency sidecars", function ()
  assert(eq("ignore", common.get_action("test/spec/a.lua.d")))
  assert(eq("copy", common.get_action("test/spec/a.lua")))
  assert(eq("template", common.get_action("test/spec/a.tk.lua")))
end)

test("get_files skips sidecars beside rendered outputs", function ()
  fs.mkdirp(dir)
  fs.writefile(fs.join(dir, "a.lua"), "return 1\n")
  fs.writefile(fs.join(dir, "a.lua.d"), fs.join(dir, "a.lua") .. ": make.lua\n")
  local found = common.get_files(dir, {})
  assert(eq("a.lua", names(found)))
  fs.rm(fs.join(dir, "a.lua"))
  fs.rm(fs.join(dir, "a.lua.d"))
  fs.rmdirs(dir)
end)

test("exclude rules win over template rules", function ()
  fs.mkdirp(dir)
  fs.writefile(fs.join(dir, "keep.css"), "a{}\n")
  fs.writefile(fs.join(dir, "drop.css"), "b{}\n")
  local config = { rules = {
    exclude = { "drop%.css$" },
    template = { "%.css$" },
  } }
  local found, tpl = common.get_files(dir, config, true)
  assert(eq("", names(found)))
  assert(eq("keep.css", names(tpl)))
  fs.rm(fs.join(dir, "keep.css"))
  fs.rm(fs.join(dir, "drop.css"))
  fs.rmdirs(dir)
end)

test("config_key ignores table insertion order", function ()
  local a = { env = { name = "x", nginx = { workers = "auto", port = "8080" } } }
  local b = { env = {} }
  b.env.nginx = {}
  b.env.nginx.port = "8080"
  b.env.nginx.workers = "auto"
  b.env.name = "x"
  assert(eq(common.config_key(a), common.config_key(b)))
end)

test("config_key separates adjacent strings unambiguously", function ()
  assert(neq(
    common.config_key({ "ab", "c" }),
    common.config_key({ "a", "bc" })))
end)

test("config_key tracks resolved environment values", function ()
  assert(neq(
    common.config_key({ env = { nginx = { workers = "auto" } } }),
    common.config_key({ env = { nginx = { workers = "4" } } })))
  assert(neq(
    common.config_key({ env = { nginx = { app_url = "https://a" } } }),
    common.config_key({ env = { nginx = {} } })))
end)

test("config_key tolerates functions and cycles", function ()
  local c = { env = { configure = function () end } }
  c.env.root = c
  local k = common.config_key(c)
  assert(eq(k, common.config_key(c)))
  assert(str.find(k, "<function>", 1, true) ~= nil)
end)

test("write_config_stamp only rewrites when the config changes", function ()
  fs.mkdirp(dir)
  local fp = fs.join(dir, "config.stamp")
  common.write_config_stamp(fp, { env = { nginx = { workers = "auto" } } })
  sys.execute({ "touch", "-t", "202001010000", fp })
  local before = posix.time(fp)
  common.write_config_stamp(fp, { env = { nginx = { workers = "auto" } } })
  assert(eq(before, posix.time(fp)))
  common.write_config_stamp(fp, { env = { nginx = { workers = "4" } } })
  assert(posix.time(fp) > before)
  fs.rm(fp)
  fs.rmdirs(dir)
end)

test("get_config_files tracks the config stamp", function ()
  local files = common.get_config_files("make.lua", "build/default/config.stamp")
  assert(eq("build/default/config.stamp", files[1]))
  assert(eq("make.lua", files[2]))
  assert(eq(0, #common.get_config_files(nil, nil)))
end)
