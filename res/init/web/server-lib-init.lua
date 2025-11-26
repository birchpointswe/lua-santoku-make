local M = {}

function M.init()

end

function M.hello()
  ngx.say("Hello from <% return name %>!")
end

return M
