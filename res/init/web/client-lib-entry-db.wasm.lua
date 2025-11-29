local js = require("santoku.web.js")
local wrpc = require("santoku.web.worker.rpc.server")
local db_worker = require("<% return name %>.db.worker")
local global = js.self
local Module = global.Module

db_worker.init(function (ok, result)
  if not ok then
    return
  end
  local handlers = result
  wrpc.init(handlers, function (handler)
    Module.on_message = function (_, ev)
      if ev.data and ev.data.REGISTER_PORT then
        ev.data.REGISTER_PORT.onmessage = function (_, port_ev)
          handler(port_ev)
        end
      end
    end
    Module:start()
  end)
end)
