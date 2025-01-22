local fs = require("santoku.fs")
local runfile = fs.runfile

local err = require("santoku.error")
local error = err.error
local assert = err.assert

local validate = require("santoku.validate")
local hasindex = validate.hasindex
local istable = validate.istable

local lib = require("santoku.make.project.lib")
local lib_init = lib.init

local web = require("santoku.make.project.web")
local web_init = web.init

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
  if not istable(opts.config) then
    error("config is not a table", opts.config)
  elseif opts.config.type == "lib" then
    return lib_init(opts)
  elseif opts.config.type == "web" then
    return web_init(opts)
  else
    return error("unexpected project type", opts.config.type)
  end
end

return {
  init = init,
  create_lib = lib.create,
  create_web = web.create,
}
