-- Unified project dispatcher
-- Auto-detects project type based on directory structure

local fs = require("santoku.fs")
local lib = require("santoku.make.project.lib")
local web = require("santoku.make.project.web")

local function init(opts)
  -- If config.type is explicitly provided, use it
  if opts.config and opts.config.type == "lib" then
    return lib.init(opts)
  elseif opts.config and opts.config.type == "web" then
    return web.init(opts)
  end

  -- Auto-detect project type from directory structure
  local root = opts.dir and fs.dirname(opts.dir) or "."
  local has_client = fs.exists(fs.join(root, "client"))
  local has_server = fs.exists(fs.join(root, "server"))

  -- Web project if client/ or server/ exists
  if has_client or has_server then
    return web.init(opts)
  else
    -- Library project (may have lib/, bin/, test/)
    return lib.init(opts)
  end
end

return {
  init = init,
}
