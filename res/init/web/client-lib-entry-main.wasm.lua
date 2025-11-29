local wrpc = require("santoku.web.worker.rpc.client")
local shared = require("santoku.web.sqlite.shared")

local db = wrpc.init("/bundle.js")

local service = shared.SharedService("<% return name %>-db", function ()
  return shared.create_provider_port(db, true)
end)

service.activate()
