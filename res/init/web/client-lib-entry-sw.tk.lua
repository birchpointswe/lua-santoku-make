<%
  local fs = require("santoku.fs")
  local mch = require("santoku.mustache")
  local tpl_dir = fs.join(root_dir, "res/web/templates")
  local sw_body_file = fs.join(tpl_dir, "sw-body.html")
  local app_file = fs.join(tpl_dir, "app.html")
  local sw_body = mch(readfile(sw_body_file), { partials = { app = readfile(app_file) } })()
  index_html = require("santoku.web.pwa.index")({
    title = client.opts.title,
    description = client.opts.description,
    theme_color = client.opts.theme_color,
    sw_inline = true,
    bundle = "/bundle.js",
    head = [[
      <link rel="stylesheet" href="/index.css">
      <script src="/htmx.min.js"></script>
    ]],
    body_tag = sw_body,
  })
%>
local sw = require("santoku.web.pwa.sw")
local routes = require("__NAME__.routes")

return sw({
  service_worker_version = (<% return tostring(os.time()) %>),
  sqlite = true,
  index_html = [[<% return index_html, false %>]],
  cached_files = {
    "/sqlite3.wasm",
    "/roboto-300.woff2",
    "/roboto-500.woff2",
    "/roboto-700.woff2",
  },
  routes = routes,
})
