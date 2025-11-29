local tpl = require("<% return name %>.web.templates")
local db = require("<% return name %>.db.loaded")

local session_id = ngx.var.cookie_session
if not session_id then
  ngx.header.content_type = "text/html"
  ngx.say("")
  return
end

local session = db.get_or_create_session(session_id)
local raw_numbers = db.get_numbers(session)
local numbers = {}
for i, n in ipairs(raw_numbers) do
  numbers[i] = { number = n, tag = "API", api = true }
end

ngx.header.content_type = "text/html"
ngx.say(tpl["number-items"]({ numbers = numbers }))
