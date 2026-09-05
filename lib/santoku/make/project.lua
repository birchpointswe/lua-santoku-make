local fs = require("santoku.fs")
local runfile = fs.runfile

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local hasindex = validate.hasindex
local istable = validate.istable

local unified = require("santoku.make.project.unified")
local lib = require("santoku.make.project.lib")
local web = require("santoku.make.project.web")
local api = require("santoku.make.project.api")

local sys = require("santoku.system")

local str = require("santoku.string")
local arr = require("santoku.array")

local sformat = str.format
local sgsub = str.gsub
local ssub = str.sub

local creates = {
  lib = lib.create,
  web = web.create,
  api = api.create,
}

local function snapshot (kind, opts)
  opts = opts or {}
  local create = creates[kind]
  assert(create ~= nil, sformat("unknown snapshot kind: %s", tostring(kind)))
  local name = opts.name or ("my-" .. kind)
  local dir = opts.dir or fs.tmpname()
  sys.execute({ "rm", "-rf", dir })
  create({ name = name, dir = dir, git = false, quiet = true })
  local all = {}
  for fp in fs.files(dir, true) do
    all[#all + 1] = ssub(fp, #dir + 2)
  end
  arr.sort(all)
  local files = {}
  for i = 1, #all do
    files[i] = { path = all[i], code = fs.readfile(fs.join(dir, all[i])) }
  end
  sys.execute({ "rm", "-rf", dir })
  return {
    name = name,
    mod = (sgsub(name, "%-", "_")),
    files = files,
    all = all,
  }
end

local run_env = { __index = _G }

local function init (opts)
  opts = opts or {}
  assert(hasindex(opts))
  opts.env = opts.env or "default"
  opts.dir = opts.dir or fs.absolute("build")
  if not istable(opts.config) and not opts.config_file then
    opts.config = opts.config or ((opts.env ~= "default")
      and sformat("make.%s.lua", opts.env)
      or "make.lua")
    opts.config_file = opts.config
    opts.config = runfile(opts.config, setmetatable({}, run_env))
  end
  assert(istable(opts.config), "config is not a table")
  return unified.init(opts)
end

return {
  init = init,
  create = lib.create,
  create_lib = lib.create,
  create_web = web.create,
  create_api = api.create,
  snapshot = snapshot,
}
