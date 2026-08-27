
local fs = require("santoku.fs")
local lib = require("santoku.make.project.lib")
local web = require("santoku.make.project.web")

local function init(opts)

  if opts.config and opts.config.type == "lib" then
    return lib.init(opts)
  elseif opts.config and opts.config.type == "web" then
    return web.init(opts)
  end

  local root = opts.dir and fs.dirname(opts.dir) or "."
  local has_client = fs.exists(fs.join(root, "client"))
  local has_server = fs.exists(fs.join(root, "server"))

  if has_client or has_server then
    opts.config.type = "web"
    return web.init(opts)
  else

    opts.config.type = "lib"
    return lib.init(opts)
  end
end

return {
  init = init,
}
