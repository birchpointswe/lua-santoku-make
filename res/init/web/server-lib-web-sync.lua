local db = require("__NAME__.db.loaded")

local auth = ngx.var.http_authorization
if not auth then
  ngx.status = 401
  ngx.header.content_type = "text/plain"
  ngx.say("Missing Authorization header")
  return
end

local session = db.get_or_create_session(auth)
local args = ngx.req.get_uri_args()
local since = tonumber(args.since) or 0

ngx.req.read_body()
local changes = ngx.req.get_body_data()

ngx.header.content_type = "application/json"
ngx.say(db.sync(session, changes, since))
