# Santoku Make

A Lua-based build system for creating Lua libraries and web applications with
template processing, dependency management, and testing support.

## Module Reference

### `santoku.make`

Core build system providing target-based dependency resolution and incremental builds.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `make` | `-` | `table` | Creates build system instance with `target`, `build`, `targets`, `deps`, `fns` |

#### Build System Instance Methods

| Method | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `target` | `targets, dependencies, [function/true]` | `-` | Registers build targets with dependencies and optional build function |
| `build` | `targets, [verbosity], ...` | `number` | Builds specified targets, returns max modification time |

### `santoku.make.project`

High-level project initialization and management for library and web projects.

| Function | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `init` | `[options]` | `project` | Initializes project based on make.lua configuration |
| `create_lib` | `-` | `-` | Creates new library project (not yet implemented) |
| `create_web` | `-` | `-` | Creates new web project (not yet implemented) |

#### Init Options

| Option | Type | Description |
|--------|------|-------------|
| `env` | `string` | Build environment (default: "default") |
| `dir` | `string` | Build directory (default: "build") |
| `config` | `table/string` | Configuration table or path to make.lua |
| `config_file` | `string` | Path to configuration file |
| `wasm` | `boolean` | Enable WebAssembly build mode |
| `skip_check` | `boolean` | Skip luacheck validation |

### `santoku.make.project.lib`

Library project type supporting Lua module builds with template processing.

#### Project Methods

| Method | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `build` | `[options]` | `-` | Builds library |
| `test` | `[options]` | `-` | Runs tests |
| `iterate` | `[options]` | `-` | Watches and rebuilds on changes |
| `release` | `[options]` | `-` | Creates release tarball |
| `install` | `[options]` | `-` | Installs to lua_modules |
| `check` | `[options]` | `-` | Runs luacheck |
| `coverage` | `[options]` | `-` | Generates coverage report |

### `santoku.make.project.web`

Web project type supporting client/server builds with OpenResty integration.

#### Project Methods

| Method | Arguments | Returns | Description |
|----------|-----------|---------|-------------|
| `build` | `[options]` | `-` | Builds web application |
| `test` | `[options]` | `-` | Runs tests |
| `iterate` | `[options]` | `-` | Watches, rebuilds, and restarts server |
| `start` | `[options]` | `-` | Starts development server |
| `stop` | `[options]` | `-` | Stops development server |

## Usage with Santoku CLI

Santoku Make is primarily used through the
[lua-santoku-cli](https://github.com/treadwelllane/lua-santoku-cli) `toku`
command. See the CLI documentation for detailed usage instructions.

## Template Processing

Files with `.tk` extension or `.tk.` in their name are processed using
[lua-santoku-template](https://github.com/treadwelllane/lua-santoku-template).
Templates can access the project environment variables and use the full Lua
language for dynamic content generation.

## Project Configuration

### Library Project (`make.lua`)

```lua
return {
  type = "lib",
  env = {
    name = "my-library",
    version = "0.0.1-1",
    license = "MIT",
    homepage = "https://github.com/user/my-library",

    dependencies = {
      "lua >= 5.1",
      "santoku >= 0.0.279-1"
    },

    test = {
      dependencies = {
        "luacov >= 0.15.0-1"
      }
    },

    -- Optional C compilation flags
    cflags = { "-O2", "-Wall" },
    ldflags = { "-shared" }
  },

  -- File processing rules
  rules = {
    exclude = { "%.swp$", "^%.git/" },
    copy = { "%.txt$" },
    template = { "%.tk$" }
  }
}
```

### Web Project (`make.lua`)

```lua
return {
  type = "web",
  env = {
    name = "my-app",
    version = "0.0.1-1",

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.279-1",
        "lua-cjson >= 2.1.0"
      },

      -- OpenResty configuration
      domain = "localhost",
      port = "8080",
      workers = "auto",
      ssl = false,

      -- Server routes
      init = "myapp.init",
      routes = {
        { "GET", "/api/users", "myapp.users.list" },
        { "POST", "/api/users", "myapp.users.create" }
      }
    },

    client = {
      dependencies = {
        "lua == 5.1",
        "santoku-web >= 0.0.253-1"
      },

      -- Application configuration
      opts = {
        app_title = "My Application",
        banner_text = "Welcome to My App",
        theme_color = "#3B82F6"
      }
    }
  }
}
```

### Web Project with Custom Build Steps

```lua
return {
  type = "web",
  env = {
    name = "advanced-app",
    version = "1.0.0",

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.279-1",
        "lua-cjson >= 2.1.0",
        "luasocket >= 3.1.0"
      },

      nginx_env_vars = { "PATH", "DATABASE_URL", "API_KEY" },
      run_env_vars = { LOG_LEVEL = "info" },

      domain = require("santoku.env").var("DOMAIN", "localhost"),
      port = require("santoku.env").var("PORT", "8080"),
      workers = 4,

      init = "app.server.init",
      routes = {
        { "GET",  "/health",         "app.server.health" },
        { "GET",  "/api/products",   "app.server.products.list" },
        { "POST", "/api/products",   "app.server.products.create" },
        { "GET",  "/api/products/:id", "app.server.products.get" },
        { "PUT",  "/api/products/:id", "app.server.products.update" }
      }
    },

    client = {
      dependencies = {
        "lua == 5.1",
        "santoku-web >= 0.0.253-1"
      },

      opts = {
        app_title = "Product Manager",
        company_name = "ACME Corp",
        support_email = "support@example.com"
      }
    },

    -- Custom build configuration
    configure = function(submake, client_env, server_env)
      local fs = require("santoku.fs")

      -- Add custom CSS compilation
      submake.target(
        { fs.join(client_env.build_dir, "res/styles.css") },
        { "client/styles/main.scss" },
        function()
          -- Custom SCSS compilation logic
        end
      )

      -- Add database migration target
      submake.target(
        { server_env.work_dir .. "/migrations.sql" },
        { "database/schema.sql", "database/migrations/*.sql" },
        function()
          -- Combine migration files
        end
      )
    end
  }
}
```

### Multi-Environment Configuration

```lua
-- make.common.lua
return {
  type = "web",
  env = {
    name = "my-service",
    version = "2.0.0",

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.279-1"
      },

      init = "service.init",
      routes = {
        { "GET", "/status", "service.status" }
      }
    }
  }
}

-- make.prod.lua
local fs = require("santoku.fs")
local base = fs.runfile("make.common.lua")
base.env.server.workers = 8
base.env.server.ssl = true
base.env.server.domain = "api.production.com"
return base

-- make.beta.lua
local fs = require("santoku.fs")
local base = fs.runfile("make.common.lua")
base.env.server.workers = 4
base.env.server.domain = "api.beta.com"
base.env.server.port = "8443"
return base
```

## Project Structure

### Library Project

```
project/
├── make.lua             # Project configuration
├── lib/                 # Library source files
│   └── mylib/
│       ├── init.lua
│       └── util.tk.lua  # Template file
├── test/                # Test files
│   └── spec/
│       └── mylib.lua
└── res/                 # Resources
    └── lib/
        └── data.bin     # Luacheck configuration
```

### Web Project

```
project/
├── make.lua            # Project configuration
├── make.common.lua     # Shared configuration
├── client/             # Client-side code
│   ├── bin/            # Client entry points
│   │   └── main.tk.lua
│   ├── lib/            # Client libraries
│   ├── res/            # Client resources
│   └── static/         # Static assets
│       └── public/
└── server/             # Server-side code
    ├── lib/            # Server libraries
    └── test/           # Server tests
```

## License

Copyright 2025 Birch Point SWE

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
