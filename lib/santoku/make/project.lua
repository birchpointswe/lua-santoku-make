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

local sformat = string.format

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
  create_lib = lib.create,
  create_web = web.create,
}
