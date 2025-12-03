local fs = require("santoku.fs")
local sys = require("santoku.system")

return {
  env = {
    name = "<% return name %>",
    version = "0.0.1-1",
    dependencies = {
      "lua == 5.1",
      "santoku >= 0.0.297-1",
    },
    build = {
      dependencies = {
        "santoku-web >= 0.0.325-1",
      }
    },
    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
        "santoku-mustache >= 0.0.10-1",
        "santoku-sqlite >= 0.0.15-1",
        "santoku-sqlite-migrate >= 0.0.16-1",
        "lsqlite3 >= 0.9.6-1",
        "argparse >= 0.7.1-1",
      },
      domain = "localhost",
      port = "8080",
      workers = "auto",
      ssl = false,
      init = "<% return name %>.web.init",
      routes = {
        { "GET", "/random", "<% return name %>.web.random" },
        { "GET", "/numbers", "<% return name %>.web.numbers" },
        { "POST", "/session/create", "<% return name %>.web.session-create" }
      }
    },
    client = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
        "santoku-web >= 0.0.325-1",
        "santoku-sqlite >= 0.0.15-1",
        "santoku-sqlite-migrate >= 0.0.16-1",
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
        background_color = "#1e293b",
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
          "https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js"
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
    end,
  }
}
