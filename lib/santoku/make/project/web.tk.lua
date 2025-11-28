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
local fun = require("santoku.functional")
local fs = require("santoku.fs")
local common = require("santoku.make.common")
local wasm = require("santoku.make.wasm")

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

-- Embedded templates for web init (reuse lib templates for root level)
local init_templates = {
  -- Root level (reuse lib templates)
  make_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/make.lua"))) %>), -- luacheck: ignore
  bin_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/bin.lua"))) %>), -- luacheck: ignore
  lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/lib.lua"))) %>), -- luacheck: ignore
  test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/test-spec.lua"))) %>), -- luacheck: ignore
  -- Client
  client_bin_index_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-bin-index.lua"))) %>), -- luacheck: ignore
  client_lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-lib.lua"))) %>), -- luacheck: ignore
  client_test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/client-test-spec.lua"))) %>), -- luacheck: ignore
  -- Server
  server_lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib.lua"))) %>), -- luacheck: ignore
  server_lib_init_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-lib-init.lua"))) %>), -- luacheck: ignore
  server_test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/web/server-test-spec.lua"))) %>), -- luacheck: ignore
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

  -- Evaluate templates for trifecta structure
  local files = {
    -- Root level
    ["make.lua"] = tmpl.render(init_templates.make_lua, template_env),
    [fs.join("bin", name .. ".lua")] = tmpl.render(init_templates.bin_lua, template_env),
    [fs.join("lib", name .. ".lua")] = tmpl.render(init_templates.lib_lua, template_env),
    [fs.join("test/spec", name .. ".lua")] = tmpl.render(init_templates.test_spec_lua, template_env),
    -- Client
    [fs.join("client/bin", "index.lua")] = tmpl.render(init_templates.client_bin_index_lua, template_env),
    [fs.join("client/lib", name .. ".lua")] = tmpl.render(init_templates.client_lib_lua, template_env),
    [fs.join("client/test/spec", name .. ".lua")] = tmpl.render(init_templates.client_test_spec_lua, template_env),
    -- Server
    [fs.join("server/lib", name .. ".lua")] = tmpl.render(init_templates.server_lib_lua, template_env),
    [fs.join("server/lib", name, "init.lua")] = tmpl.render(init_templates.server_lib_init_lua, template_env),
    [fs.join("server/test/spec", name .. ".lua")] = tmpl.render(init_templates.server_test_spec_lua, template_env),
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

  local function get_files(dir, check_tpl, check_tpl_client)
    return common.get_files(dir, opts.config, check_tpl, check_tpl_client)
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
  local base_client_res, base_client_res_templated, base_client_res_templated_client
    = get_files("client/res", true, true)
  local base_client_test_specs = get_files("client/test/spec")

  local base_root_test_specs = get_files("test/spec")
  local base_root_libs = get_files("lib")

  local base_client_lua_modules_ok = "lua_modules.ok"
  local base_client_lua_modules_deps_ok = "lua_modules.deps.ok"

  local base_client_pages = collect(map(function (fp)
    return fs.stripparts(fs.stripextensions(fp) .. ".js", 2)
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

  tbl.merge(server_env, base_env, opts.config.env.server or {})
  tbl.merge(test_server_env, base_env, opts.config.env.server or {})
  tbl.merge(client_env, base_env, opts.config.env.client or {})
  tbl.merge(test_client_env, base_env, opts.config.env.client or {})
  tbl.merge(root_env, base_env)
  tbl.merge(test_root_env, base_env)

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
    add_copied_target(test_server_dir_stripped(fp), fp)
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
          amap(extend({}, base_client_res_templated_client), fun.compose(remove_tk, cdir_stripped))))
      add_copied_target(ddir_stripped(remove_tk(fp)),
        cdir(remove_tk(fp)))
    end

    for fp in ivals(base_client_deps) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(extend({}, base_client_res_templated_client), fun.compose(remove_tk, cdir_stripped))))
    end

    for fp in ivals(base_client_libs) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(extend({}, base_client_res_templated_client), fun.compose(remove_tk, cdir_stripped))))
    end

    for fp in ivals(base_root_libs) do
      add_copied_target(cdir(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(extend({}, base_client_res_templated_client), fun.compose(remove_tk, cdir_stripped))))
    end

    for fp in ivals(base_client_bins) do
      add_copied_target(cdir_stripped(fp), fp,
        extend({ cdir(base_client_lua_modules_deps_ok) },
          amap(extend({}, base_client_res_templated_client), fun.compose(remove_tk, cdir_stripped))))
    end

    for fp in ivals(base_client_res) do
      add_copied_target(cdir_stripped(fp), fp,
        amap(extend({}, base_client_static), cdir_stripped))
    end

    for fp in ivals(base_client_res_templated) do
      add_file_target(cdir_stripped(fp), fp, env,
        amap(extend({}, base_client_static), cdir_stripped))
    end

    for fp in ivals(base_client_res_templated_client) do
      add_file_target(cdir_stripped(remove_tk(fp)), fp, env,
        amap(extend({}, base_client_static), cdir_stripped))
    end

    for fp in ivals(base_client_pages) do
      local pre = cdir("build", "default-wasm", "build", "bin", fs.stripextensions(fp)) .. ".lua"
      local post = cdir("bundler-post", fs.stripextensions(fp))
      local deps = { cdir(base_client_lua_modules_ok), pre }
      local extra_flags = it.reduce(function (a, k, v)
        if (type(k) == "string" and str.find(post, k)) or (type(k) == "function" and k(post)) then
          if v.cxxflags then
            arr.extend(a, v.cxxflags)
          end
          if v.ldflags then
            arr.extend(a, v.ldflags)
          end
        end
        return a
      end, {}, it.pairs(tbl.get(env, "rules") or {}))
      target({ post }, deps, function ()
        fs.mkdirp(cdir("build", "default-wasm", "build"))
        fs.pushd(cdir("build", "default-wasm", "build"), function ()
          local lua_dir = cdir("build", "default-wasm", "build", "lua-5.1.5")
          local extra_cflags = extend({}, extra_flags, tbl.get(env, "cxxflags") or {})
          local extra_ldflags = tbl.get(env, "ldflags") or {}
          bundle(pre, fs.dirname(post), {
            cc = "emcc",
            ignores = { "debug" },
            path = get_lua_path(cdir("build", "default-wasm", "build")),
            cpath = get_lua_cpath(cdir("build", "default-wasm", "build")),
            flags = wasm.get_bundle_flags(lua_dir, "build", extra_cflags, extra_ldflags)
          })
        end)
      end)
      add_copied_target(ddir(fp), post)
    end

    target(
      { cdir(base_client_lua_modules_deps_ok) },
      extend({ opts.config_file },
        amap(extend({}, base_client_res, amap(extend({}, base_client_res_templated), remove_tk)), cdir_stripped)),
      function ()
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
          }, env),
          rules = tbl.get(opts, "config", "rules", "client"),
        }
        fs.mkdirp(cdir())
        return fs.pushd(cdir(), function ()
          require("santoku.make.project").init({
            config_file = config_file,
            config = config,
            single = opts.single and remove_tk(opts.single) or nil,
            skip_check = opts.skip_check,
            wasm = true,
            skip_tests = true,
            dir = cdir("build"),
          }).install_deps()
          fs.touch(base_client_lua_modules_deps_ok)
        end)
      end)

    target(
      { cdir(base_client_lua_modules_ok) },
      extend({ opts.config_file, cdir(base_client_lua_modules_deps_ok) },
        amap(extend({}, base_client_bins, base_client_libs, base_client_deps), cdir_stripped),
        amap(extend({}, base_root_libs), cdir)),
      function ()
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
          }, env),
          rules = tbl.get(opts, "config", "rules", "client"),
        }
        fs.mkdirp(cdir())
        return fs.pushd(cdir(), function ()
          require("santoku.make.project").init({
            config_file = config_file,
            config = config,
            single = opts.single and remove_tk(opts.single) or nil,
            skip_check = opts.skip_check,
            wasm = true,
            skip_tests = true,
            dir = cdir("build"),
          }).install()
          fs.touch(base_client_lua_modules_ok)
        end)
      end)

  end

  target(
    { server_dir(base_server_lua_modules_ok) },
    extend({ server_dir(base_server_luarocks_cfg) },
      amap(amap(extend({}, base_server_libs, base_server_deps), server_dir_stripped), remove_tk),
      amap(amap(extend({}, base_root_libs), server_dir), remove_tk)),
    function ()
      local config_file = fs.absolute(opts.config_file)
      local config = {
        type = "lib",
        env = tbl.assign(opts.config.env.server, {
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
        }),
        rules = tbl.get(opts, "config", "rules", "server"),
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
      amap(amap(extend({}, base_root_libs), test_server_dir), remove_tk)),
    function ()
      local config_file = fs.absolute(opts.config_file)
      local config = {
        type = "lib",
        env = tbl.assign(opts.config.env.server, {
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
        }),
        rules = tbl.get(opts, "config", "rules", "server"),
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
        base_client_pages),
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
        base_client_pages),
        test_dist_dir_client), remove_tk)), true)

  target(
    { "start" },
    { "build" },
    function ()
      fs.mkdirp(dist_dir())
      return fs.pushd(dist_dir(), function ()
        sys.execute({ "sh", "-c", "sh run.sh &" })
      end)
    end)

  target(
    { "test-start" },
    { "test-build" },
    function ()
      fs.mkdirp(test_dist_dir())
      return fs.pushd(test_dist_dir(), function ()
        sys.execute({ "sh", "-c", "sh run.sh &" })
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

  -- Determine which test sets to run
  local run_root = opts.test_root or (not opts.test_client and not opts.test_server and not single_target)
  local run_client = opts.test_client or (not opts.test_root and not opts.test_server and not single_target)
  local run_server = opts.test_server or (not opts.test_root and not opts.test_client and not single_target)

  -- If --single specified, only run that target
  if single_target == "root" then
    run_root, run_client, run_server = true, false, false
  elseif single_target == "client" then
    run_root, run_client, run_server = false, true, false
  elseif single_target == "server" then
    run_root, run_client, run_server = false, false, true
  end

  target(
    { "test" },
    extend(
      { test_client_dir(base_client_lua_modules_ok) },
      amap(extend({},
        amap(extend({}, base_server_test_specs, base_server_test_res_templated), remove_tk),
        base_server_test_res), test_server_dir_stripped),
      amap(amap(extend({}, base_client_test_specs), remove_tk), test_client_dir_stripped)),
    function (_, _, iterating)
      local config_file = fs.absolute(opts.config_file)

      -- Run root tests first
      if run_root and #base_root_test_specs > 0 then
        local root_config = {
          type = "lib",
          env = tbl.assign({}, opts.config.env, {
            name = opts.config.env.name,
            version = opts.config.env.version,
            configure = nil,  -- Don't pass configure to sub-projects
          }),
          rules = tbl.get(opts, "config", "rules"),
        }
        require("santoku.make.project").init({
          config_file = config_file,
          config = root_config,
          single = single_target == "root" and single_path and remove_tk(single_path) or nil,
          skip_check = opts.skip_check,
          dir = fs.absolute("build"),
        }).test()
      end

      -- Run client tests second
      if run_client and #base_client_test_specs > 0 then
        local client_config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
          }, test_client_env),
          rules = tbl.get(opts, "config", "rules", "client"),
        }
        fs.mkdirp(test_client_dir())
        fs.pushd(test_client_dir(), function ()
          require("santoku.make.project").init({
            config_file = config_file,
            config = client_config,
            single = single_target == "client" and single_path and remove_tk(single_path) or nil,
            skip_check = opts.skip_check,
            wasm = true,
            dir = test_client_dir("build"),
          }).test()
        end)
      end

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
          env = tbl.assign(opts.config.env.server, {
            name = opts.config.env.name .. "-server",
            version = opts.config.env.version,
          }),
          rules = tbl.get(opts, "config", "rules", "server"),
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
      err.pcall(function ()
        sys.execute({
          "inotifywait", "-qr",
          "-e", "close_write", "-e", "modify",
          "-e", "move", "-e", "create", "-e", "delete",
          spread(collect(filter(function (fp)
            return fs.exists(fp)
          end, chain(ivals({ "client", "server", "res", "lib", "bin", "test", opts.config_file }), it.keys(dfile_dirs)))))
        })
      end)
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
      build(tbl.assign({ opts.test and "test-start" or "start" }, opts), opts.verbosity)
    end,
    stop = function (opts)
      opts = opts or {}
      build(tbl.assign({ "stop", "test-stop" }, opts), opts.verbosity)
    end,
  }

end

return {
  init = init,
  create = create,
}
