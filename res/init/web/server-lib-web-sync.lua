local db = require("__NAME__.db.loaded")

-- Get session from Authorization header
local auth = ngx.var.http_authorization
if not auth then
  ngx.status = 401
  ngx.header.content_type = "text/plain"
  ngx.say("Missing Authorization header")
  return
end

local session = db.get_or_create_session(auth)

-- Get 'since' from query params (default to 0 for full sync)
local args = ngx.req.get_uri_args()
local since = tonumber(args.since) or 0

ngx.req.read_body()
local changes = ngx.req.get_body_data()
if changes then
  db.apply_changes(session, changes)
end

-- TODO: stream this
ngx.header.content_type = "application/json"
ngx.say(db.get_changes(session, since))
