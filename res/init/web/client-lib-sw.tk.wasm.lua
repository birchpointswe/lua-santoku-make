local sw = require("santoku.web.pwa.sw")
local swdb = require("santoku.web.sqlite.sw")
local tpl = require("__NAME__.web.templates")

local js = require("santoku.web.js")
local Math = js.Math
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

  -- Simple route handlers
  routes = {
    ["/random-sw"] = function (req, params, done)
      local num = Math:floor(Math:random() * 1000) + 1
      db.call("add_number", { num }, function (ok, _)
        if ok then
          done(true, tpl["number-item"]({
            number = num,
            tag = "SW",
            sw = true
          }))
        else
          done(false, "Failed to add number")
        end
      end)
    end,

    ["/numbers-sw"] = function (req, params, done)
      db.call("get_numbers", {}, function (ok, rows)
        if ok then
          local numbers = {}
          for i, row in ipairs(rows or {}) do
            numbers[i] = { number = row.number, tag = "SW", sw = true }
          end
          done(true, tpl["number-items"]({ numbers = numbers }))
        else
          done(false, "Failed to get numbers")
        end
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
