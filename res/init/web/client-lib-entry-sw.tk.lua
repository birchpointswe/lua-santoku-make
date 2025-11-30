local sw = require("santoku.web.pwa.sw")
local routes = require("<% return name %>.routes")

return sw({
  service_worker_version = (<% return tostring(os.time()) %>),
  sqlite = true,
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
  routes = routes,
})
