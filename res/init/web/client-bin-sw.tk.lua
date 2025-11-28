local sw = require("santoku.web.pwa.sw")
local js = require("santoku.web.js")
local util = require("santoku.web.util")
local templates = require("<% return name %>.web.templates")

sw({
  service_worker_version = (<%% return tostring(os.time()) %%>),
  cached_files = {},
  on_fetch = function(request, _, def)
    local url = js.URL:new(request.url)
    if url.pathname == "/random-sw" then
      local number = math.random(1, 1000)
      local html = templates["number-item"]({ number = number, tag = "SW", color = "text-amber-600" })
      return util.promise(function(complete)
        complete(true, js.Response:new(html, {
          status = 200,
          headers = {
            ["Content-Type"] = "text/html"
          }
        }))
      end)
    end
    return def(request)
  end,
})
