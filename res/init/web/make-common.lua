local fs = require("santoku.fs")
local sys = require("santoku.system")

return {
  type = "web",
  env = {
    name = "<%= name %>",
    version = "0.0.1-1",
    dependencies = {
      "lua == 5.1",
      "santoku >= 0.0.297-1",
    },
    build = {
      dependencies = {
        "santoku-web >= 0.0.284-1",
      }
    },
    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
        "santoku-mustache >= 0.0.6-1",
        "santoku-sqlite >= 0.0.15-1",
        "santoku-sqlite-migrate >= 0.0.15-1",
        "lsqlite3 >= 0.9.6-1",
        "argparse >= 0.7.1-1",
      },
      domain = "localhost",
      port = "8080",
      workers = "auto",
      ssl = false,
      init = "<%= name %>.web.init",
      routes = {
        { "GET", "/random", "<%= name %>.web.random" },
        { "GET", "/numbers", "<%= name %>.web.numbers" }
      }
    },
    client = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
        "santoku-web >= 0.0.284-1"
      },
      opts = {
        title = "<%= name %>",
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
      local css_out = fs.join(client_env.public_dir, "index.css")
      local css_in = fs.join(client_env.root_dir, "client/res/index.css")
      local body_html = fs.join(client_env.root_dir, "res/web/templates/body.html")
      submake.target({ client_env.target }, { css_out })
      submake.target({ css_out }, { css_in, body_html }, function ()
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
