local common = require("<% return name %>.common")

local M = {}

function M.hello()
  return "Hello from <% return name %> client", common.hello()
end

return M
