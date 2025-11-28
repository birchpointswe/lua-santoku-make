local tpl = require("<% return name %>.web.templates")
local db = require("<% return name %>.db.loaded")
local random = require("santoku.random")

local session_id = ngx.var.cookie_session
local is_new = not session_id
if is_new then
  session_id = random.alnum(32)
end

if is_new then
  ngx.header["Set-Cookie"] = "session=" .. session_id .. "; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000"
end

local session_pk = db.get_or_create_session(session_id)
local number = math.random(1, 1000)
db.add_number(session_pk, number)

ngx.header.content_type = "text/html"
ngx.say(tpl["number-item"]({ number = number, tag = "API", color = "text-emerald-600" }))
