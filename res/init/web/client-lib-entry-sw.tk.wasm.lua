local sw = require("santoku.web.pwa.sw")
local swdb = require("santoku.web.sqlite.sw")

local js = require("santoku.web.js")
local Response = js.Response

-- Connect to the database via SharedService
local db = swdb.connect("__NAME__")

sw({

  service_worker_version = (<% return tostring(os.time()) %>),

  cached_files = {
    "/",
    "/index.css",
    "/htmx.min.js",
    "/bundle.js",
    "/bundle.wasm",
    "/manifest.json",
    "/sqlite3.wasm",
    "/sqlite3-opfs-async-proxy.js",
    "/roboto-300.woff2",
    "/roboto-400.woff2",
    "/roboto-500.woff2",
    "/roboto-700.woff2",
  },

  -- Route handlers - call db worker which returns rendered HTML
  routes = {
    ["/random-sw"] = function (_, _, done)
      db.add_random(function (ok, html)
        done(ok, html or "Failed to add number")
      end)
    end,

    ["/numbers-sw"] = function (_, _, done)
      db.get_numbers(function (ok, html)
        done(ok, html or "Failed to get numbers")
      end)
    end,
  },

  on_message = db.on_message,

  -- Handle /clientId for SharedService coordination
  on_fetch = function (request, client_id, default_handler)
    local url = js.URL:new(request.url)
    if url.pathname == "/clientId" then
      return require("santoku.web.util").promise(function (done)
        done(true, Response:new(client_id, {
          headers = { ["Content-Type"] = "text/plain" }
        }))
      end)
    end
    return default_handler(request)
  end,

})
