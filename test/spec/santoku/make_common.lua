local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
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
