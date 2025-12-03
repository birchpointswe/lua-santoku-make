local tpl = require("<% return name %>.web.templates")
local db = require("<% return name %>.db.loaded")

local session_id = ngx.var.cookie_session
if not session_id then
  ngx.status = 401
  ngx.header.content_type = "text/html"
  ngx.say("Session required")
  return
end

local session_pk = db.get_or_create_session(session_id)
local number = math.random(1, 1000)
db.add_number(session_pk, number)

ngx.header.content_type = "text/html"
ngx.say(tpl["number-item"]({ number = number, tag = "API", api = true }))
