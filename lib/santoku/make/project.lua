<% str = require("santoku.string") %>

local fs = require("santoku.fs")
local compat = require("santoku.compat")
local err = require("santoku.err")

local lib = require("santoku.make.project.lib")
local web = require("santoku.make.project.web")

local M = {}

M.create_lib = lib.create
M.create_web = web.create

M.init = function (opts)
  opts = opts or {}
  assert(compat.istype.table(opts))
  return err.pwrap(function (check)
    opts.env = opts.env or "default"
    opts.dir = opts.dir or "build"
    opts.config = opts.config or ((opts.env ~= "default")
      and string.format("make.%s.lua", opts.env)
      or "make.lua")
    opts.config_file = opts.config
    opts.config = check(fs.loadfile(opts.config))()
    if type(opts.config) ~= "table" then
      return check(false, "config is not a table")
    elseif opts.config.type == "lib" then
      return check(lib.init(opts))
    elseif opts.config.type == "web" then
      return check(web.init(opts))
    else
      return check(false, "unexpected project type", opts.config.type)
    end
  end)
end

return M
