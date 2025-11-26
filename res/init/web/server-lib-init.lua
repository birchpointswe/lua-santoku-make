local M = {}

function M.init()
  -- Server initialization
end

function M.hello()
  ngx.say("Hello from <% return name %>!")
end

return M
