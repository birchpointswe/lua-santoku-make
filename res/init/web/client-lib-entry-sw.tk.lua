<%
  local fs = require("santoku.fs")
  local mch = require("santoku.mustache")
  local loader = fs.runfile(fs.join(root_dir, "res/web/template-loader.lua"))
  local partials = loader(readfile, root_dir)
  local sw_body = mch(partials["sw-body"], { partials = partials })()
  index_html = require("santoku.web.pwa.index")({
    title = client.opts.title,
    description = client.opts.description,
    theme_color = client.opts.theme_color,
    sw_inline = true,
    bundle = "/bundle.js",
    manifest = "/manifest.json",
    favicon_svg = client.opts.favicon_svg,
    ios_icon = client.opts.ios_icon,
    splash_screens = client.opts.splash_screens,
    head = [[
      <link rel="stylesheet" href="/index.css">
      <script src="/htmx.min.js"></script>
      <script src="/idiomorph-ext.min.js"></script>
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
    "/roboto-400.woff2",
    "/roboto-500.woff2",
    "/roboto-700.woff2",
  },
  routes = routes,
})
