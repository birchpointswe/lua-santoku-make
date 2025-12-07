local fs = require("santoku.fs")
local sys = require("santoku.system")

-- iOS icon/splash screen sizes (width, height, pixel ratio)
local icon_sizes = { 192, 512 }
local apple_icon_size = 180
local splash_screens = {
  { 430, 932, 3 }, -- iPhone 14 Pro Max
  { 393, 852, 3 }, -- iPhone 14 Pro
  { 428, 926, 3 }, -- iPhone 14 Plus, 13 Pro Max, 12 Pro Max
  { 390, 844, 3 }, -- iPhone 14, 13, 13 Pro, 12, 12 Pro
  { 375, 812, 3 }, -- iPhone 13 mini, 12 mini, X, XS, 11 Pro
  { 414, 896, 3 }, -- iPhone 11 Pro Max, XS Max
  { 414, 896, 2 }, -- iPhone 11, XR
  { 414, 736, 3 }, -- iPhone 8 Plus
  { 375, 667, 2 }, -- iPhone SE, 8
  { 320, 568, 2 }, -- iPhone SE (1st gen)
  { 1024, 1366, 2 }, -- iPad Pro 12.9"
  { 834, 1194, 2 }, -- iPad Pro 11"
  { 820, 1180, 2 }, -- iPad Air
  { 810, 1080, 2 }, -- iPad 10th gen
  { 768, 1024, 2 }, -- iPad mini, iPad
}

return {
  env = {

    name = "<% return name %>",
    version = "0.0.1-1",
    version_check = true,
    dependencies = {
      "lua == 5.1",
      "santoku >= 0.0.305-1",
    },
    build = {
      dependencies = {
        "santoku-web >= 0.0.390-1",
      }
    },

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.305-1",
        "santoku-mustache >= 0.0.13-1",
        "santoku-sqlite >= 0.0.27-1",
        "santoku-sqlite-migrate >= 0.0.17-1",
        "lsqlite3 >= 0.9.6-1",
        "argparse >= 0.7.1-1",
      },
      domain = "localhost",
      port = "8080",
      workers = "auto",
      ssl = false,
      init = "<% return name %>.web.init",
      routes = {
        { "POST", "/session/create", "<% return name %>.web.session-create" },
        { "POST", "/sync", "<% return name %>.web.sync" },
      }
    },

    client = {
      files = true,
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.305-1",
        "santoku-web >= 0.0.390-1",
        "santoku-http >= 0.0.18-1",
        "santoku-sqlite >= 0.0.27-1",
        "santoku-sqlite-migrate >= 0.0.17-1",
      },
      rules = {
        ["bundle$"] = {
          ldflags = {
            "--pre-js", "res/pre.js",
            "--extern-pre-js", "deps/sqlite/jswasm/sqlite3.js"
          }
        }
      },
      opts = {
        title = "<% return name %>",
        description = "A web app built with santoku",
        theme_color = "#1e293b",
        background_color = "#f5f5f5",
      },
    },

    configure = function (submake, envs)
      local client_env = envs.client
      if not client_env then return end
      local htmx_file = fs.join(client_env.public_dir, "htmx.min.js")
      submake.target({ client_env.target }, { htmx_file })
      submake.target({ htmx_file }, {}, function ()
        sys.execute({
          "curl", "-sL", "-o", htmx_file,
          "https://unpkg.com/htmx.org@2.0.7/dist/htmx.min.js"
        })
      end)
      local idiomorph_file = fs.join(client_env.public_dir, "idiomorph-ext.min.js")
      submake.target({ client_env.target }, { idiomorph_file })
      submake.target({ idiomorph_file }, {}, function ()
        sys.execute({
          "curl", "-sL", "-o", idiomorph_file,
          "https://unpkg.com/idiomorph@0.7.4/dist/idiomorph-ext.min.js"
        })
      end)
      local roboto_weights = { "300", "400", "500", "700" }
      local roboto_urls = {
        ["300"] = "https://fonts.gstatic.com/s/roboto/v32/KFOlCnqEu92Fr1MmSU5fCxc4EsA.woff2",
        ["400"] = "https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Mu7GxKOzY.woff2",
        ["500"] = "https://fonts.gstatic.com/s/roboto/v32/KFOlCnqEu92Fr1MmEU9fCxc4EsA.woff2",
        ["700"] = "https://fonts.gstatic.com/s/roboto/v32/KFOlCnqEu92Fr1MmWUlfCxc4EsA.woff2",
      }
      for _, weight in ipairs(roboto_weights) do
        local font_file = fs.join(client_env.public_dir, "roboto-" .. weight .. ".woff2")
        submake.target({ client_env.target }, { font_file })
        submake.target({ font_file }, {}, function ()
          sys.execute({
            "curl", "-sL", "-o", font_file, roboto_urls[weight]
          })
        end)
      end
      local css_out = fs.join(client_env.public_dir, "index.css")
      local css_in = fs.join(client_env.root_dir, "client/res/index.css")
      submake.target({ client_env.target }, { css_out })
      submake.target({ css_out }, { css_in }, function ()
        sys.execute({
          "tailwindcss",
          "--cwd", client_env.root_dir,
          "-i", css_in,
          "-o", css_out,
          "--minify"
        })
      end)
      local icon_svg_src = fs.join(client_env.build_dir, "res/icon.svg")
      local theme = envs.root.client.opts.theme_color
      local bg = envs.root.client.opts.background_color or theme
      local favicon_svg = fs.join(client_env.public_dir, "favicon.svg")
      submake.target({ client_env.target }, { favicon_svg })
      submake.target({ favicon_svg }, { icon_svg_src }, function ()
        fs.writefile(favicon_svg, fs.readfile(icon_svg_src))
      end)
      local manifest_icons = {}
      for _, size in ipairs(icon_sizes) do
        local icon_file = fs.join(client_env.public_dir, "icon-" .. size .. ".png")
        submake.target({ client_env.target }, { icon_file })
        submake.target({ icon_file }, { icon_svg_src }, function ()
          sys.execute({
            "rsvg-convert", "-w", tostring(size), "-h", tostring(size),
            "-o", icon_file, icon_svg_src
          })
        end)
        table.insert(manifest_icons, {
          src = "/icon-" .. size .. ".png",
          sizes = size .. "x" .. size,
          type = "image/png"
        })
      end
      local apple_icon = fs.join(client_env.public_dir, "apple-touch-icon.png")
      submake.target({ client_env.target }, { apple_icon })
      submake.target({ apple_icon }, { icon_svg_src }, function ()
        sys.execute({
          "rsvg-convert", "-w", tostring(apple_icon_size), "-h", tostring(apple_icon_size),
          "-o", apple_icon, icon_svg_src
        })
      end)
      local splash_opts = {}
      for _, spec in ipairs(splash_screens) do
        local w, h, dpr = spec[1], spec[2], spec[3]
        local pw, ph = w * dpr, h * dpr
        local splash_file = fs.join(client_env.public_dir, "splash-" .. w .. "x" .. h .. "@" .. dpr .. "x.png")
        submake.target({ client_env.target }, { splash_file })
        submake.target({ splash_file }, { icon_svg_src }, function ()
          local icon_size = math.min(pw, ph) * 0.3
          sys.execute({
            "sh", "-c", string.format(
              "convert -size %dx%d xc:'%s' \\( %s -resize %dx%d \\) -gravity center -composite %s",
              pw, ph, bg, icon_svg_src, icon_size, icon_size, splash_file
            )
          })
        end)
        table.insert(splash_opts, {
          width = w,
          height = h,
          dpr = dpr,
          src = "/splash-" .. w .. "x" .. h .. "@" .. dpr .. "x.png"
        })
      end
      envs.root.client.opts.manifest_icons = manifest_icons
      envs.root.client.opts.favicon_svg = "/favicon.svg"
      envs.root.client.opts.ios_icon = "/apple-touch-icon.png"
      envs.root.client.opts.splash_screens = splash_opts
    end,

  }
}
