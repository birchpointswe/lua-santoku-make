<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local bundle = require("santoku.bundle")
local env = require("santoku.env")
local make = require("santoku.make")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local varg = require("santoku.varg")
local vdt = require("santoku.validate")
local err = require("santoku.error")
local fs = require("santoku.fs")
local common = require("santoku.make.common")
local wasm = require("santoku.make.wasm")
local clean = require("santoku.make.clean")

local arr = require("santoku.array")
local amap = arr.map
local spread = arr.spread
local extend = arr.extend
local concat = arr.concat

local it = require("santoku.iter")
local chain = it.chain
local ivals = it.ivals
local collect = it.collect
local filter = it.filter
local map = it.map

local str = require("santoku.string")
local stripprefix = str.stripprefix
local supper = string.upper
local smatch = string.match
local gsub = string.gsub
local from_base64 = str.from_base64

local tmpl = require("santoku.template")

-- Embedded templates for web init
local init_templates = {
  -- Root level config
  make_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/make.lua"))) %>), -- luacheck: ignore
  make_common_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/make-common.lua"))) %>), -- luacheck: ignore
  make_prod_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/make-prod.lua"))) %>), -- luacheck: ignore
  -- Root level lib/bin/test
  bin_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/bin.lua"))) %>), -- luacheck: ignore
  lib_common_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/lib-common.lua"))) %>), -- luacheck: ignore
  lib_web_templates_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/lib-web-templates.tk.lua"))) %>), -- luacheck: ignore
  test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/test-spec.lua"))) %>), -- luacheck: ignore
  -- Client
  client_bin_bundle_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-bin-bundle.tk.lua"))) %>), -- luacheck: ignore
  client_lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib.lua"))) %>), -- luacheck: ignore
  client_lib_entry_sw_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib-entry-sw.tk.lua"))) %>), -- luacheck: ignore
  client_lib_entry_main_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib-entry-main.lua"))) %>), -- luacheck: ignore
  client_lib_db_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib-db.tk.lua"))) %>), -- luacheck: ignore
  client_lib_routes_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib-routes.tk.lua"))) %>), -- luacheck: ignore
  client_deps_sqlite_makefile = from_base64(<% return squote(to_base64(readfile("res/init/web/client-deps-sqlite-Makefile.tk"))) %>), -- luacheck: ignore
  client_test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-test-spec.lua"))) %>), -- luacheck: ignore
  client_static_index_html = from_base64(<% return squote(to_base64(readfile("res/init/web/client-static-index.tk.html"))) %>), -- luacheck: ignore
  client_res_index_css = from_base64(<% return squote(to_base64(readfile("res/init/web/client-res-index.css"))) %>), -- luacheck: ignore
  client_res_pre_js = from_base64(<% return squote(to_base64(readfile("res/init/web/client-res-pre.tk.js"))) %>), -- luacheck: ignore
  client_static_manifest_json = from_base64(<% return squote(to_base64(readfile("res/init/web/client-static-manifest.tk.json"))) %>), -- luacheck: ignore
  -- Server
  server_bin_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-bin.lua"))) %>), -- luacheck: ignore
  server_lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib.lua"))) %>), -- luacheck: ignore
  server_lib_web_init_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib-web-init.lua"))) %>), -- luacheck: ignore
  server_lib_web_sync_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib-web-sync.lua"))) %>), -- luacheck: ignore
  server_lib_web_session_create_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib-web-session-create.lua"))) %>), -- luacheck: ignore
  server_lib_db_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib-db.tk.lua"))) %>), -- luacheck: ignore
  server_test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-test-spec.lua"))) %>), -- luacheck: ignore
  -- Resources
  res_server_migrations_sql = from_base64(<% return squote(to_base64(readfile("res/init/web/res-server-migrations-0.0.1.sql"))) %>), -- luacheck: ignore
  res_client_migrations_sql = from_base64(<% return squote(to_base64(readfile("res/init/web/res-client-migrations-0.0.1.sql"))) %>), -- luacheck: ignore
  res_templates_body_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-body.html"))) %>), -- luacheck: ignore
  res_templates_sw_body_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-sw-body.html"))) %>), -- luacheck: ignore
  res_templates_app_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-app.html"))) %>), -- luacheck: ignore
  res_templates_number_item_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-number-item.html"))) %>), -- luacheck: ignore
  res_templates_number_items_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-number-items.html"))) %>), -- luacheck: ignore
  res_templates_session_state_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-session-state.html"))) %>), -- luacheck: ignore
  res_templates_sync_state_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-sync-state.html"))) %>), -- luacheck: ignore
  res_templates_icon_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icon.html"))) %>), -- luacheck: ignore
  res_templates_number_item_delete_html = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-number-item-delete.html"))) %>), -- luacheck: ignore
  res_templates_icons_sync_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-sync.svg"))) %>), -- luacheck: ignore
  res_templates_icons_check_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-check.svg"))) %>), -- luacheck: ignore
  res_templates_icons_x_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-x.svg"))) %>), -- luacheck: ignore
  res_templates_icons_question_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-question.svg"))) %>), -- luacheck: ignore
  res_templates_icons_chevron_left_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-chevron-left.svg"))) %>), -- luacheck: ignore
  res_templates_icons_chevron_right_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-web-templates-icons-chevron-right.svg"))) %>), -- luacheck: ignore
  res_tailwind_theme_css = from_base64(<% return squote(to_base64(readfile("res/init/web/res-tailwind-theme.css"))) %>), -- luacheck: ignore
  res_icon_svg = from_base64(<% return squote(to_base64(readfile("res/init/web/res-icon.tk.svg"))) %>), -- luacheck: ignore
  -- Common
  gitignore = from_base64(<% return squote(to_base64(readfile("res/init/web/gitignore"))) %>), -- luacheck: ignore
}

local function create (opts)
  err.assert(vdt.istable(opts), "opts must be a table")
  err.assert(vdt.isstring(opts.name), "opts.name is required")

  local name = opts.name
  local dir = opts.dir or name

  -- Validate name format
  if not smatch(name, "^[a-z][a-z0-9%-]*$") then
    err.error("Invalid name: must start with lowercase letter and contain only lowercase letters, numbers, and hyphens")
  end

  -- Create environment for template evaluation
  local template_env = setmetatable({
    name = name,
  }, { __index = _G })

  -- Evaluate templates for full web project structure
  local files = {
    -- Root level config
    ["make.lua"] = tmpl.render(init_templates.make_lua, template_env),
    ["make.common.lua"] = tmpl.render(init_templates.make_common_lua, template_env),
    ["make.prod.lua"] = init_templates.make_prod_lua,
    -- Root level lib/bin/test
    [fs.join("bin", name .. ".lua")] = tmpl.render(init_templates.bin_lua, template_env),
    [fs.join("lib", name, "common.lua")] = tmpl.render(init_templates.lib_common_lua, template_env),
    [fs.join("lib", name, "web", "templates.tk.lua")] = init_templates.lib_web_templates_lua,
    [fs.join("test/spec", name .. ".lua")] = tmpl.render(init_templates.test_spec_lua, template_env),
    -- Client
    [fs.join("client/bin", "bundle.tk.lua")] = tmpl.render(init_templates.client_bin_bundle_lua, template_env),
    [fs.join("client/lib", name .. ".lua")] = tmpl.render(init_templates.client_lib_lua, template_env),
    [fs.join("client/lib", name, "sw.tk.lua")] = gsub(init_templates.client_lib_entry_sw_lua, "__NAME__", name),
    [fs.join("client/lib", name, "main.lua")] = tmpl.render(init_templates.client_lib_entry_main_lua, template_env),
    [fs.join("client/lib", name, "db.tk.lua")] = gsub(init_templates.client_lib_db_lua, "__NAME__", name),
    [fs.join("client/lib", name, "routes.lua")] = gsub(init_templates.client_lib_routes_lua, "__NAME__", name),
    [fs.join("client/deps/sqlite", "Makefile.tk")] = init_templates.client_deps_sqlite_makefile,
    [fs.join("client/test/spec", name .. ".lua")] = tmpl.render(init_templates.client_test_spec_lua, template_env),
    [fs.join("client/static", "index.tk.html")] = init_templates.client_static_index_html,
    [fs.join("client/static", "manifest.tk.json")] = init_templates.client_static_manifest_json,
    [fs.join("client/res", "index.css")] = init_templates.client_res_index_css,
    [fs.join("client/res", "pre.tk.js")] = init_templates.client_res_pre_js,
    -- Server
    [fs.join("server/bin", name .. ".lua")] = tmpl.render(init_templates.server_bin_lua, template_env),
    [fs.join("server/lib", name .. ".lua")] = tmpl.render(init_templates.server_lib_lua, template_env),
    [fs.join("server/lib", name, "web", "init.lua")] = tmpl.render(init_templates.server_lib_web_init_lua, template_env),
    [fs.join("server/lib", name, "web", "sync.lua")] = gsub(init_templates.server_lib_web_sync_lua, "__NAME__", name),
    [fs.join("server/lib", name, "web", "session-create.lua")] = tmpl.render(init_templates.server_lib_web_session_create_lua, template_env),
    [fs.join("server/lib", name, "db.tk.lua")] = init_templates.server_lib_db_lua,
    [fs.join("server/test/spec", name .. ".lua")] = tmpl.render(init_templates.server_test_spec_lua, template_env),
    -- Resources
    [fs.join("res/server/migrations", "0.0.1.sql")] = init_templates.res_server_migrations_sql,
    [fs.join("res/client/migrations", "0.0.1.sql")] = init_templates.res_client_migrations_sql,
    [fs.join("res/web/templates", "body.html")] = init_templates.res_templates_body_html,
    [fs.join("res/web/templates", "sw-body.html")] = init_templates.res_templates_sw_body_html,
    [fs.join("res/web/templates", "app.html")] = tmpl.render(init_templates.res_templates_app_html, template_env),
    [fs.join("res/web/templates", "number-item.html")] = init_templates.res_templates_number_item_html,
    [fs.join("res/web/templates", "number-items.html")] = init_templates.res_templates_number_items_html,
    [fs.join("res/web/templates", "number-item-delete.html")] = init_templates.res_templates_number_item_delete_html,
    [fs.join("res/web/templates", "session-state.html")] = init_templates.res_templates_session_state_html,
    [fs.join("res/web/templates", "sync-state.html")] = init_templates.res_templates_sync_state_html,
    [fs.join("res/web/templates", "icon.html")] = init_templates.res_templates_icon_html,
    [fs.join("res/web/templates/icons", "sync.svg")] = init_templates.res_templates_icons_sync_svg,
    [fs.join("res/web/templates/icons", "check.svg")] = init_templates.res_templates_icons_check_svg,
    [fs.join("res/web/templates/icons", "x.svg")] = init_templates.res_templates_icons_x_svg,
    [fs.join("res/web/templates/icons", "question.svg")] = init_templates.res_templates_icons_question_svg,
    [fs.join("res/web/templates/icons", "chevron-left.svg")] = init_templates.res_templates_icons_chevron_left_svg,
    [fs.join("res/web/templates/icons", "chevron-right.svg")] = init_templates.res_templates_icons_chevron_right_svg,
    [fs.join("res/tailwind", "theme.css")] = init_templates.res_tailwind_theme_css,
    [fs.join("res", "icon.tk.svg")] = init_templates.res_icon_svg,
    -- Common
    [".gitignore"] = init_templates.gitignore,
  }

  -- Create directories and write files
  local pairs = it.pairs
  for fpath, content in pairs(files) do
    local full_path = fs.join(dir, fpath)
    fs.mkdirp(fs.dirname(full_path))
    fs.writefile(full_path, content)
  end

  -- Initialize git if requested
  if opts.git ~= false then
    sys.execute({ "git", "init", dir })
  end

  io.stdout:write("Created web project: " .. name .. "\n")
  io.stdout:write("\nNext steps:\n")
  io.stdout:write("  cd " .. dir .. "\n")
  io.stdout:write("  toku web test-build  # Build for testing\n")
  io.stdout:write("  toku web test-start  # Start development server\n")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build

  err.assert(vdt.istable(opts))
  err.assert(vdt.istable(opts.config))

  opts.single = opts.single and opts.single:gsub("^[^/]+/", "") or nil
  opts.skip_check = opts.skip_check or nil
  opts.openresty_dir = opts.openresty_dir or opts.config.openresty_dir or env.var("OPENRESTY_DIR")

  local function work_dir (...)
    return fs.join(opts.dir, opts.env, ...)
  end

  local function dist_dir (...)
    return work_dir("main", "dist", ...)
  end

  local function server_dir (...)
    return work_dir("main", "server", ...)
  end

  local function server_dir_stripped (...)
    return server_dir(varg.map(function (fp)
      return stripprefix(fp, "server/")
    end, ...))
  end

  local function test_dist_dir (...)
    return work_dir("test", "dist", ...)
  end

  local function test_server_dir (...)
    return work_dir("test", "server", ...)
  end

  local function test_server_dir_stripped (...)
    return test_server_dir(varg.map(function (fp)
      return stripprefix(fp, "server/")
    end, ...))
  end

  local function client_dir (...)
    return work_dir("main", "client", ...)
  end

  local function client_dir_stripped (...)
    return client_dir(varg.map(function (fp)
      return stripprefix(fp, "client/")
    end, ...))
  end

  local function test_client_dir (...)
    return work_dir("test", "client", ...)
  end

  local function test_client_dir_stripped (...)
    return test_client_dir(varg.map(function (fp)
      return stripprefix(fp, "client/")
    end, ...))
  end

  local function dist_dir_client (...)
    return dist_dir("public", ...)
  end

  local function test_dist_dir_client (...)
    return test_dist_dir("public",...)
  end

  local function dist_dir_client_stripped (...)
    return dist_dir("public", varg.map(function (fp)
      return fs.stripparts(fp, 2)
    end, ...))
  end

  local function test_dist_dir_client_stripped (...)
    return test_dist_dir("public", varg.map(function (fp)
      return fs.stripparts(fp, 2)
    end, ...))
  end

  local function remove_tk(fp)
    return common.remove_tk(fp, opts.config)
  end

  local function add_copied_target(dest, src, extra_srcs)
    return common.add_copied_target(target, dest, src, extra_srcs)
  end

  -- Build dependencies directory (host-native, for template processing)
  local build_deps_dir = work_dir("build-deps")
  local build_deps_ok = work_dir("build-deps.ok")
  local build_deps = tbl.get(opts, "config", "env", "build", "dependencies") or {}
  local has_build_deps = #build_deps > 0

  local function add_file_target(dest, src, env, extra_srcs)
    return common.add_file_target(target, dest, src, env, opts.config, opts.config_file, extra_srcs,
      has_build_deps and build_deps_dir or nil,
      has_build_deps and build_deps_ok or nil)
  end

  local function add_templated_target_base64(dest, data, env, extra_srcs)
    return common.add_templated_target_base64(target, dest, data, env, opts.config_file, extra_srcs,
      has_build_deps and build_deps_dir or nil,
      has_build_deps and build_deps_ok or nil)
  end

  local function get_lua_path(prefix)
    return common.get_lua_path(prefix)
  end

  local function get_lua_cpath(prefix)
    return common.get_lua_cpath(prefix)
  end

  local function get_files(dir, check_tpl)
    return common.get_files(dir, opts.config, check_tpl)
  end

  local base_server_libs = get_files("server/lib")
  local base_server_deps = get_files("server/deps")
  local base_server_test_specs = get_files("server/test/spec")
  local base_server_test_res, base_server_test_res_templated = get_files("server/test/res", true)
  local base_server_run_sh = "run.sh"
  local base_server_nginx_cfg = "nginx.conf"
  local base_server_init_test_lua = "init-test.lua"
  local base_server_init_worker_test_lua = "init-worker-test.lua"
  local base_server_luarocks_cfg = "luarocks.lua"
  local base_server_lua_modules = "lua_modules"
  local base_server_lua_modules_ok = "lua_modules.ok"

  local base_client_static = get_files("client/static")
  local base_client_assets = get_files("client/assets")
  local base_client_deps = get_files("client/deps")
  local base_client_libs = get_files("client/lib")
  local base_client_bins = get_files("client/bin")
  local base_client_res, base_client_res_templated = get_files("client/res", true)
  local base_client_test_specs = get_files("client/test/spec")

  local base_root_test_specs = get_files("test/spec")
  local base_root_libs = get_files("lib")
  local base_root_res = get_files("res")

  local base_client_lua_modules_ok = "lua_modules.ok"
  local base_client_lua_modules_deps_ok = "lua_modules.deps.ok"

  local base_client_pages = collect(map(function (fp)
    return fs.stripparts(fs.stripextensions(fp) .. ".js", 2)
  end, ivals(base_client_bins)))

  local base_client_wasm = collect(map(function (fp)
    return fs.stripparts(fs.stripextensions(fp) .. ".wasm", 2)
  end, ivals(base_client_bins)))

  local base_env = {
    root_dir = fs.cwd(),
    skip_check = opts.skip_check,
    var = function (n)
      err.assert(vdt.isstring(n))
      return concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local server_env = {
    environment = "main",
    component = "server",
    target = "build",
    libs = base_server_libs,
    dist_dir = dist_dir(),
    public_dir = dist_dir_client(),
    work_dir = server_dir(),
    openresty_dir = opts.openresty_dir,
    lua_modules = dist_dir(base_server_lua_modules),
    luarocks_cfg = server_dir(base_server_luarocks_cfg),
  }

  local test_server_env = {
    environment = "test",
    component = "server",
    target = "test-build",
    libs = base_server_libs,
    dist_dir = test_dist_dir(),
    public_dir = test_dist_dir_client(),
    work_dir = test_server_dir(),
    openresty_dir = opts.openresty_dir,
    luarocks_cfg = test_server_dir(base_server_luarocks_cfg),
    lua = env.interpreter()[1],
    lua_path = get_lua_path(test_dist_dir()),
    lua_cpath = get_lua_cpath(test_dist_dir()),
    lua_modules = test_dist_dir(base_server_lua_modules),
  }

  local client_env = {
    environment = "main",
    component = "client",
    target = "build",
    dist_dir = dist_dir(),
    public_dir = dist_dir_client(),
    work_dir = client_dir(),
    bundler_post_dir = client_dir("bundler-post"),
    build_dir = client_dir("build", "default-wasm", "build"),
    lua_path = get_lua_path(client_dir("build", "default-wasm", "build")),
    lua_cpath = get_lua_cpath(client_dir("build", "default-wasm", "build")),
    luarocks_cfg = client_dir("build", "default-wasm", "build", base_server_luarocks_cfg),
  }

  local test_client_env = {
    environment = "test",
    component = "client",
    target = "test-build",
    dist_dir = test_dist_dir(),
    public_dir = test_dist_dir_client(),
    work_dir = test_client_dir(),
    bundler_post_dir = test_client_dir("bundler-post"),
    build_dir = test_client_dir("build", "default-wasm", "build"),
    lua_path = get_lua_path(test_client_dir("build", "default-wasm", "build")),
    lua_cpath = get_lua_cpath(test_client_dir("build", "default-wasm", "build")),
    luarocks_cfg = test_client_dir("build", "default-wasm", "build", base_server_luarocks_cfg),
  }

  local root_env = {
    environment = "main",
    component = "root",
    target = "build",
    dist_dir = dist_dir(),
    work_dir = work_dir(),
  }

  local test_root_env = {
    environment = "test",
    component = "root",
    target = "test-build",
    dist_dir = test_dist_dir(),
    work_dir = work_dir("test"),
    lua = env.interpreter()[1],
    lua_path = get_lua_path(work_dir("test", "build")),
    lua_cpath = get_lua_cpath(work_dir("test", "build")),
  }

  -- Merge base_env into all environments (root_dir, var(), etc.)
  tbl.merge(server_env, base_env)
  tbl.merge(test_server_env, base_env)
  tbl.merge(client_env, base_env)
  tbl.merge(test_client_env, base_env)
  tbl.merge(root_env, base_env)
  tbl.merge(test_root_env, base_env)

  -- Namespaced access to component configs from all environments
  -- Templates use client.opts.X, server.domain, etc. consistently
  local client_cfg = opts.config.env.client or {}
  local server_cfg = opts.config.env.server or {}
  local all_envs = {
    server_env, test_server_env,
    client_env, test_client_env,
    root_env, test_root_env,
  }
  for _, e in ipairs(all_envs) do
    e.client = client_cfg
    e.server = server_cfg
    e.name = opts.config.env.name
    e.version = opts.config.env.version
  end
  -- Copy component-specific build flags into component envs
  for _, e in ipairs({ client_env, test_client_env }) do
    e.rules = client_cfg.rules
    e.ldflags = client_cfg.ldflags
    e.cxxflags = client_cfg.cxxflags
  end
  for _, e in ipairs({ server_env, test_server_env }) do
    e.rules = server_cfg.rules
    e.ldflags = server_cfg.ldflags
    e.cxxflags = server_cfg.cxxflags
  end

  opts.config.env.variable_prefix =
    opts.config.env.variable_prefix or
    supper((gsub(opts.config.env.name, "%W+", "_")))

  -- Install build dependencies (host-native, for template processing)
  local build_deps_luarocks_cfg = work_dir("build-deps-luarocks.lua")
  if has_build_deps then
    target(
      { build_deps_ok },
      { opts.config_file },
      function ()
        fs.mkdirp(build_deps_dir)
        local config_file = fs.absolute(opts.config_file)
        local lua_modules_dir = fs.join(fs.absolute(build_deps_dir), "lua_modules")
        -- Generate minimal luarocks config for build deps
        fs.writefile(build_deps_luarocks_cfg, str.interp([[
rocks_trees = {
  { name = "build-deps",
    root = "%s#(lua_modules)"
  } }
lua_version = "5.1"
rocks_provided = { lua = "5.1" }
]], { lua_modules = lua_modules_dir }))
        local build_config = {
          type = "lib",
          env = {
            name = opts.config.env.name .. "-build-deps",
            version = opts.config.env.version,
            dependencies = build_deps,
          },
        }
        fs.pushd(build_deps_dir, function ()
          require("santoku.make.project").init({
            config_file = config_file,
            config = build_config,
            luarocks_config = fs.absolute(build_deps_luarocks_cfg),
            skip_tests = true,
            dir = build_deps_dir,
          }).install_deps()
        end)
        fs.touch(build_deps_ok)
      end)
  end

  add_templated_target_base64(server_dir(base_server_run_sh),
    <% return squote(to_base64(readfile("res/web/run.sh"))) %>, server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_run_sh),
    <% return squote(to_base64(readfile("res/web/run.sh"))) %>, test_server_env) -- luacheck: ignore

  add_templated_target_base64(server_dir(base_server_nginx_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.tk.conf"))) %>, server_env, -- luacheck: ignore
    { server_dir(base_server_lua_modules_ok) })

  add_templated_target_base64(test_server_dir(base_server_nginx_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.tk.conf"))) %>, test_server_env, -- luacheck: ignore
    { test_server_dir(base_server_lua_modules_ok),
      test_server_dir(base_server_init_test_lua),
      test_server_dir(base_server_init_worker_test_lua) })

  add_templated_target_base64(server_dir(base_server_luarocks_cfg),
    <% return squote(to_base64(readfile("res/web/luarocks.lua"))) %>, server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_luarocks_cfg),
    <% return squote(to_base64(readfile("res/web/luarocks.lua"))) %>, test_server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_init_test_lua),
    <% return squote(to_base64(readfile("res/web/init-test.lua"))) %>, test_server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_init_worker_test_lua),
    <% return squote(to_base64(readfile("res/web/init-worker-test.lua"))) %>, test_server_env) -- luacheck: ignore

  add_copied_target(
    dist_dir(base_server_run_sh),
    server_dir(base_server_run_sh))

  add_copied_target(
    dist_dir(base_server_nginx_cfg),
    server_dir(base_server_nginx_cfg))

  add_copied_target(
    test_dist_dir(base_server_init_test_lua),
    test_server_dir(base_server_init_test_lua))

  add_copied_target(
    test_dist_dir(base_server_init_worker_test_lua),
    test_server_dir(base_server_init_worker_test_lua))

  add_copied_target(
    test_dist_dir(base_server_run_sh),
    test_server_dir(base_server_run_sh))

  add_copied_target(
    test_dist_dir(base_server_nginx_cfg),
    test_server_dir(base_server_nginx_cfg),
    { test_dist_dir(base_server_init_test_lua), test_dist_dir(base_server_init_worker_test_lua) })

  for flag in ivals({
    "skip_check"
  }) do
    local fp = work_dir(flag .. ".flag")
    fs.mkdirp(fs.dirname(fp))
    local strval = tostring(opts[flag])
    if not fs.exists(fp) then
      fs.writefile(fp, strval)
    else
      local val = fs.readfile(fp)
      if val ~= strval then
        fs.writefile(fp, strval)
      end
    end
  end

  target(
    amap({ base_server_init_test_lua, base_server_init_worker_test_lua }, test_server_dir),
    amap({ "skip_check.flag" }, work_dir))

  for fp in ivals(base_server_libs) do
    add_file_target(server_dir_stripped(remove_tk(fp)), fp, server_env)
  end

  for fp in ivals(base_server_libs) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_root_libs) do
    add_file_target(server_dir(remove_tk(fp)), fp, server_env)
  end

  for fp in ivals(base_root_libs) do
    add_file_target(test_server_dir(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_root_res) do
    add_file_target(server_dir(remove_tk(fp)), fp, server_env)
  end

  for fp in ivals(base_root_res) do
    add_file_target(test_server_dir(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_server_deps) do
    add_file_target(server_dir_stripped(remove_tk(fp)), fp, server_env)
  end

  for fp in ivals(base_server_deps) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_server_test_specs) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_server_test_res) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_server_test_res_templated) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for fp in ivals(base_client_test_specs) do
    add_file_target(test_client_dir_stripped(remove_tk(fp)), fp, test_client_env)
  end

  for ddir, ddir_stripped, cdir, cdir_stripped, env in map(spread, ivals({
    { dist_dir_client, dist_dir_client_stripped, client_dir,
      client_dir_stripped, client_env },
    { test_dist_dir_client, test_dist_dir_client_stripped,
      test_client_dir, test_client_dir_stripped, test_client_env }
  })) do

    fs.mkdirp(ddir())
    fs.mkdirp(cdir())

    for fp in ivals(base_client_assets) do
      add_copied_target(ddir_stripped(remove_tk(fp)), fp,
        { cdir(base_client_lua_modules_deps_ok) })
    end

    for fp in ivals(base_client_static) do
      add_copied_target(cdir_stripped(fp), fp)
      add_file_target(cdir(remove_tk(fp)), cdir_stripped(fp), env,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(amap(extend({}, base_client_res, base_client_res_templated), remove_tk), cdir_stripped)))
      add_copied_target(ddir_stripped(remove_tk(fp)),
        cdir(remove_tk(fp)))
    end

    for fp in ivals(base_client_deps) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(amap(extend({}, base_client_res, base_client_res_templated), remove_tk), cdir_stripped)))
    end

    for fp in ivals(base_client_libs) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(amap(extend({}, base_client_res, base_client_res_templated), remove_tk), cdir_stripped)))
    end

    for fp in ivals(base_root_libs) do
      add_file_target(cdir(remove_tk(fp)), fp, env,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(amap(extend({}, base_client_res, base_client_res_templated), remove_tk), cdir_stripped),
          amap(amap(extend({}, base_root_res), remove_tk), cdir)))
    end

    for fp in ivals(base_root_res) do
      add_file_target(cdir(remove_tk(fp)), fp, env)
    end

    for fp in ivals(base_client_bins) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(amap(extend({}, base_client_res, base_client_res_templated), remove_tk), cdir_stripped)))
    end

    for fp in ivals(base_client_res) do
      add_file_target(cdir_stripped(remove_tk(fp)), fp, env,
        amap(extend({}, base_client_static), cdir_stripped))
    end

    for fp in ivals(base_client_res_templated) do
      add_file_target(cdir_stripped(remove_tk(fp)), fp, env,
        amap(extend({}, base_client_static), cdir_stripped))
    end

    for fp in ivals(base_client_pages) do
      local nested_env = env.environment == "test" and "test" or "build"
      local pre = cdir("build", "default-wasm", nested_env, "bin", fs.stripextensions(fp)) .. ".lua"
      local post = cdir("bundler-post", fs.stripextensions(fp))
      local deps = { cdir(base_client_lua_modules_ok), pre }
      if has_build_deps then
        arr.push(deps, build_deps_ok)
      end
      local extra_rule_cflags = {}
      local extra_rule_ldflags = {}
      for k, v in it.pairs(tbl.get(env, "rules") or {}) do
        if (type(k) == "string" and str.find(post, k)) or (type(k) == "function" and k(post)) then
          if v.cxxflags then
            arr.extend(extra_rule_cflags, v.cxxflags)
          end
          if v.ldflags then
            arr.extend(extra_rule_ldflags, v.ldflags)
          end
        end
      end
      target({ post }, deps, function ()
        fs.mkdirp(cdir("build", "default-wasm", nested_env))
        fs.pushd(cdir("build", "default-wasm", nested_env), function ()
          local lua_dir = cdir("build", "default-wasm", nested_env, "lua-5.1.5")
          local luac_bin = fs.join(lua_dir, "bin", "luac")
          local extra_cflags = extend({}, extra_rule_cflags, tbl.get(env, "cxxflags") or {})
          local extra_ldflags = extend({}, extra_rule_ldflags, tbl.get(env, "ldflags") or {})
          local use_files = tbl.get(env, "client", "files")
          common.with_build_deps(has_build_deps and build_deps_dir or nil, function ()
            bundle(pre, fs.dirname(post), {
              cc = "emcc",
              -- In files mode, skip luac to preserve source info
              luac = not use_files and (luac_bin .. " -s -o %output %input") or nil,
              binary = not use_files,
              files = use_files,
              ignores = { "debug" },
              path = get_lua_path(cdir("build", "default-wasm", nested_env)),
              cpath = get_lua_cpath(cdir("build", "default-wasm", nested_env)),
              flags = wasm.get_bundle_flags(lua_dir, "build", extra_cflags, extra_ldflags)
            })
          end)
        end)
      end)
      add_copied_target(ddir(fp), post)
      local wasm_dest = fs.join(fs.dirname(ddir(fp)), fs.stripextensions(fs.basename(ddir(fp))) .. ".wasm")
      local wasm_src = post .. ".wasm"
      add_copied_target(wasm_dest, wasm_src)
    end

    target(
      { cdir(base_client_lua_modules_deps_ok) },
      extend({ opts.config_file },
        amap(extend({}, amap(extend({}, base_client_res), remove_tk), amap(extend({}, base_client_res_templated), remove_tk)), cdir_stripped)),
      function ()
        local nested_env = env.environment == "test" and "test" or "build"
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
            rules = opts.config.env.rules,
          }, opts.config.env.client or {}, env),
        }
        fs.mkdirp(cdir())
        return fs.pushd(cdir(), function ()
          common.with_build_deps(has_build_deps and build_deps_dir or nil, function ()
            require("santoku.make.project").init({
              config_file = config_file,
              config = config,
              single = opts.single and remove_tk(opts.single) or nil,
              skip_check = opts.skip_check,
              wasm = true,
              skip_tests = env.environment ~= "test",
              dir = cdir("build"),
              environment = nested_env,
            }).install_deps()
          end)
          fs.touch(base_client_lua_modules_deps_ok)
        end)
      end)

    target(
      { cdir(base_client_lua_modules_ok) },
      extend({ opts.config_file, cdir(base_client_lua_modules_deps_ok) },
        has_build_deps and { build_deps_ok } or {},
        amap(extend({}, base_client_bins, base_client_libs, base_client_deps), cdir_stripped),
        amap(amap(extend({}, base_root_libs, base_root_res), remove_tk), cdir)),
      function ()
        local nested_env = env.environment == "test" and "test" or "build"
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
            rules = opts.config.env.rules,
          }, opts.config.env.client or {}, env),
        }
        fs.mkdirp(cdir())
        return fs.pushd(cdir(), function ()
          common.with_build_deps(has_build_deps and build_deps_dir or nil, function ()
            require("santoku.make.project").init({
              config_file = config_file,
              config = config,
              single = opts.single and remove_tk(opts.single) or nil,
              skip_check = opts.skip_check,
              wasm = true,
              skip_tests = env.environment ~= "test",
              dir = cdir("build"),
              environment = nested_env,
            }).install()
          end)
          fs.touch(base_client_lua_modules_ok)
        end)
      end)

  end

  target(
    { server_dir(base_server_lua_modules_ok) },
    extend({ server_dir(base_server_luarocks_cfg) },
      amap(amap(extend({}, base_server_libs, base_server_deps), server_dir_stripped), remove_tk),
      amap(amap(extend({}, base_root_libs, base_root_res), server_dir), remove_tk)),
    function ()
      local config_file = fs.absolute(opts.config_file)
      local config = {
        type = "lib",
        env = tbl.merge({
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
          rules = opts.config.env.rules,
        }, opts.config.env.server or {}),
      }
      fs.mkdirp(server_dir())
      return fs.pushd(server_dir(), function ()
        require("santoku.make.project").init({
          environment = "build",
          config_file = config_file,
          luarocks_config = fs.absolute(base_server_luarocks_cfg),
          config = config,
          single = opts.single and remove_tk(opts.single) or nil,
          skip_check = opts.skip_check,
          skip_tests = true,
          dir = server_dir(),
        }).install()
        fs.touch(base_server_lua_modules_ok)
      end)
    end)

  target(
    { test_server_dir(base_server_lua_modules_ok) },
    extend({ test_server_dir(base_server_luarocks_cfg) },
      amap(amap(extend({}, base_server_libs, base_server_deps), test_server_dir_stripped), remove_tk),
      amap(amap(extend({}, base_root_libs, base_root_res), test_server_dir), remove_tk)),
    function ()
      local config_file = fs.absolute(opts.config_file)
      local config = {
        type = "lib",
        env = tbl.merge({
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
          rules = opts.config.env.rules,
        }, opts.config.env.server or {}),
      }
      fs.mkdirp(test_server_dir())
      return fs.pushd(test_server_dir(), function ()
        require("santoku.make.project").init({
          environment = "test",
          config_file = config_file,
          luarocks_config = fs.absolute(base_server_luarocks_cfg),
          config = config,
          single = opts.single and remove_tk(opts.single) or nil,
          skip_check = opts.skip_check,
          skip_tests = true,
          lua = test_server_env.lua,
          lua_path = test_server_env.lua_path,
          lua_cpath = test_server_env.lua_cpath,
          dir = test_server_dir(),
        }).install()
        fs.touch(base_server_lua_modules_ok)
      end)
    end)

  target(
    { "build" },
    extend({
      dist_dir(base_server_run_sh),
      dist_dir(base_server_nginx_cfg),
      server_dir(base_server_lua_modules_ok),
      client_dir(base_client_lua_modules_ok) },
      amap(amap(extend({},
        base_client_static, base_client_assets),
        dist_dir_client_stripped), remove_tk),
      amap(amap(extend({},
        base_client_pages, base_client_wasm),
        dist_dir_client), remove_tk)), true)

  target(
    { "test-build" },
    extend({
      test_dist_dir(base_server_run_sh),
      test_dist_dir(base_server_nginx_cfg),
      test_server_dir(base_server_lua_modules_ok),
      test_client_dir(base_client_lua_modules_ok) },
      amap(amap(extend({},
        base_client_static, base_client_assets),
        test_dist_dir_client_stripped), remove_tk),
      amap(amap(extend({},
        base_client_pages, base_client_wasm),
        test_dist_dir_client), remove_tk)), true)

  target(
    { "start" },
    { "build" },
    function (_, _, opts)
      opts = opts or {}
      fs.mkdirp(dist_dir())
      return fs.pushd(dist_dir(), function ()
        if opts.fg then
          sys.execp("sh", { "run.sh" })
        else
          sys.execute({ "sh", "-c", "sh run.sh &" })
        end
      end)
    end)

  target(
    { "test-start" },
    { "test-build" },
    function (_, _, opts)
      opts = opts or {}
      fs.mkdirp(test_dist_dir())
      return fs.pushd(test_dist_dir(), function ()
        if opts.fg then
          sys.execp("sh", { "run.sh" })
        else
          sys.execute({ "sh", "-c", "sh run.sh &" })
        end
      end)
    end)

  -- Detect which test set --single belongs to based on path
  local function get_single_target(single)
    if not single then return nil, nil end
    if smatch(single, "^client/test/") or smatch(single, "^client/") then
      return "client", gsub(single, "^client/test/spec/", "test/spec/")
    elseif smatch(single, "^server/test/") or smatch(single, "^server/") then
      return "server", gsub(single, "^server/test/spec/", "test/spec/")
    elseif smatch(single, "^test/") then
      return "root", single
    else
      return nil, single
    end
  end

  local single_target, single_path = get_single_target(opts.single)

  -- Determine which test sets to run (client tests now run via lua_modules.ok)
  local run_root = opts.test_root or (not opts.test_client and not opts.test_server and not single_target)
  local run_server = opts.test_server or (not opts.test_root and not opts.test_client and not single_target)

  -- If --single specified, only run that target
  if single_target == "root" then
    run_root, run_server = true, false
  elseif single_target == "client" then
    run_root, run_server = false, false
  elseif single_target == "server" then
    run_root, run_server = false, true
  end

  target(
    { "test" },
    extend(
      { test_client_dir(base_client_lua_modules_ok) },
      amap(amap(extend({}, base_server_test_specs, base_server_test_res_templated, base_server_test_res), remove_tk), test_server_dir_stripped),
      amap(amap(extend({}, base_client_test_specs), remove_tk), test_client_dir_stripped)),
    function (_, _, iterating)
      local config_file = fs.absolute(opts.config_file)

      -- Run root tests first
      if run_root and #base_root_test_specs > 0 then
        local root_config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name,
            version = opts.config.env.version,
            configure = nil,  -- Don't pass configure to sub-projects
          }, opts.config.env),
        }
        require("santoku.make.project").init({
          config_file = config_file,
          config = root_config,
          single = single_target == "root" and single_path and remove_tk(single_path) or nil,
          skip_check = opts.skip_check,
          dir = fs.absolute("build"),
        }).test()
      end

      -- Client tests are now handled by lua_modules.ok target with skip_tests = false

      -- Run server tests last (only these need the server running)
      if run_server and #base_server_test_specs > 0 then
        -- Start server and verify it started successfully
        build({ "stop", "test-stop" }, opts.verbosity)
        build({ "test-start" }, opts.verbosity)

        -- Wait briefly and verify server is running
        sys.sleep(0.5)
        local pid_file = test_dist_dir("server.pid")
        if not fs.exists(pid_file) then
          err.error("fatal", "Server failed to start: no pid file created")
        end
        local pid = smatch(fs.readfile(pid_file), "(%d+)")
        if not pid then
          err.error("fatal", "Server failed to start: invalid pid file")
        end
        -- Check if process is still alive
        local alive = err.pcall(sys.execute, { "kill", "-0", pid })
        if not alive then
          err.error("fatal", "Server failed to start: process died immediately (check nginx error log)")
        end

        local server_config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-server",
            version = opts.config.env.version,
            rules = opts.config.env.rules,
          }, opts.config.env.server or {}),
        }
        fs.mkdirp(test_server_dir())
        fs.pushd(test_server_dir(), function ()
          local lib = require("santoku.make.project").init({
            config_file = config_file,
            luarocks_config = fs.absolute(base_server_luarocks_cfg),
            config = server_config,
            single = single_target == "server" and single_path and remove_tk(single_path) or nil,
            skip_check = opts.skip_check,
            lua = test_server_env.lua,
            lua_path = test_server_env.lua_path,
            lua_cpath = test_server_env.lua_cpath,
            dir = test_server_dir(),
          })
          lib.test({ skip_check = true })
          lib.check()
        end)

        if not iterating then
          build({ "test-stop" }, opts.verbosity)
        end
      end
    end)

  target({ "iterate" }, {}, function (_, _)
    varg.tup(function (ok, ...)
      if not ok then
        err.error("inotify not found", ...)
      end
    end, err.pcall(sys.execute, { "sh", "-c", "type inotifywait >/dev/null 2>/dev/null" }))
    local config_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
    while true do
      -- Check if config file changed - if so, need to restart
      if config_mtime then
        local new_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
        if new_mtime and new_mtime > config_mtime then
          print("\n[iterate] " .. opts.config_file .. " changed - please restart iterate\n")
          config_mtime = new_mtime
        end
      end
      varg.tup(function (ok, first, ...)
        if not ok then
          if first == "fatal" then
            err.error(first, ...)
          end
          -- Check for interrupt signal
          local msg = tostring(first)
          if smatch(msg, "interrupt") or smatch(msg, "SIGINT") then
            err.error(first, ...)
          end
          print(first, ...)
        end
      end, err.pcall(build, { "test" }, opts.verbosity, true))
      -- Collect directories from .d files
      local dfile_dirs = {}
      err.pcall(function ()
        for dfile in fs.files(work_dir(), true) do
          if str.find(dfile, "%.d$") then
            local data = fs.readfile(dfile)
            local file_deps = tmpl.deserialize_deps(data)
            for fp in it.keys(file_deps) do
              local dir = fs.dirname(fp)
              if dir and dir ~= "" and dir ~= "." then
                dfile_dirs[dir] = true
              end
            end
          end
        end
      end)
      varg.tup(function (ok, first, ...)
        if not ok then
          local msg = tostring(first)
          if smatch(msg, "interrupt") or smatch(msg, "SIGINT") or smatch(msg, "signaled") then
            err.error(first, ...)
          end
        end
      end, err.pcall(function ()
        sys.execute({
          "inotifywait", "-qr",
          "-e", "close_write", "-e", "modify",
          "-e", "move", "-e", "create", "-e", "delete",
          spread(collect(filter(function (fp)
            return fs.exists(fp)
          end, chain(ivals({ "client", "server", "res", "lib", "bin", "test", opts.config_file }), it.keys(dfile_dirs)))))
        })
      end))
      sys.sleep(.25)
    end
  end)

  target({ "stop" }, {}, function ()
    fs.mkdirp(dist_dir())
    return fs.pushd(dist_dir(), function ()
      if fs.exists("server.pid") then
        err.pcall(function ()
          sys.execute({ "kill", "-15", smatch(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  target({ "test-stop" }, {}, function (_, _)
    fs.mkdirp(test_dist_dir())
    return fs.pushd(test_dist_dir(), function ()
      if fs.exists("server.pid") then
        err.pcall(function ()
          sys.execute({ "kill", "-15", smatch(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  -- Load .d file dependencies (tracks files read during template expansion)
  for fp in ivals(submake.targets) do
    local dfile = fp .. ".d"
    if fs.exists(dfile) then
      local chunks = map(str.sub, map(function (line)
        return str.splits(line, "%s*:%s*", false)
      end, fs.lines(dfile)))
      target(chunks(), collect(chunks))
    end
  end

  local configure = tbl.get(opts, "config", "env", "configure")
  if configure then
    configure(submake, { root = root_env, client = client_env, server = server_env })
    configure(submake, { root = test_root_env, client = test_client_env, server = test_server_env })
  end

  return {
    config = opts.config,
    test = function (opts)
      opts = opts or {}
      build(tbl.assign({ "test" }, opts), opts.verbosity)
    end,
    iterate = function (opts)
      opts = opts or {}
      build(tbl.assign({ "iterate" }, opts), opts.verbosity)
    end,
    build = function (opts)
      opts = opts or {}
      build(tbl.assign({ opts.test and "test-build" or "build" }, opts), opts.verbosity)
    end,
    start = function (opts)
      opts = opts or {}
      build({ opts.test and "test-start" or "start" }, opts.verbosity, opts)
    end,
    stop = function (opts)
      opts = opts or {}
      build(tbl.assign({ "stop", "test-stop" }, opts), opts.verbosity)
    end,
    clean = function (clean_opts)
      clean_opts = clean_opts or {}
      return clean.web({
        dir = opts.dir,
        env = clean_opts.env,  -- nil = all envs with --all, otherwise use project env
        all = clean_opts.all,
        deps = clean_opts.deps,
        wasm = clean_opts.wasm,
        client = clean_opts.client,
        server = clean_opts.server,
        dry_run = clean_opts.dry_run,
      })
    end,
  }

end

return {
  init = init,
  create = create,
}
