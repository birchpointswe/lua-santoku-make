<%
  str = require("santoku.string")
  sys = require("santoku.system")
%>

local bundle = require("santoku.bundle")
local env = require("santoku.env")
local make = require("santoku.make")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local vdt = require("santoku.validate")
local err = require("santoku.error")
local fs = require("santoku.fs")
local common = require("santoku.make.common")
local wasm = require("santoku.make.wasm")
local clean = require("santoku.make.clean")
local arr = require("santoku.array")
local str = require("santoku.string")
local tmpl = require("santoku.template")
local rand = require("santoku.random")
local fun = require("santoku.functional")
local spread = arr.spread

local boilerplate_tar_b64 = <% -- luacheck: ignore
  local fs = require("santoku.fs")
  local tmp = fs.tmpname()
  sys.execute({ "tar", "-C", "submodules/tokuboilerplate-web", "--exclude", ".git", "--exclude", "build", "-czf", tmp, "." })
  local content = fs.readfile(tmp)
  fs.rm(tmp)
  return str.quote(str.to_base64(content))
%>

local function create (opts)
  err.assert(vdt.istable(opts), "opts must be a table")
  err.assert(vdt.isstring(opts.name), "opts.name is required")

  local name = opts.name
  local dir = opts.dir or name

  if not str.match(name, "^[a-z][a-z0-9%-]*$") then
    err.error("Invalid name: must start with lowercase letter and contain only lowercase letters, numbers, and hyphens")
  end

  fs.mkdirp(dir)
  local tmp = fs.tmpname()
  fs.writefile(tmp, str.from_base64(boilerplate_tar_b64))
  sys.execute({ "tar", "-C", dir, "-xzf", tmp })
  fs.rm(tmp)

  for _, d in ipairs({
    "server/lib/tokuboilerplate",
    "client/lib/tokuboilerplate",
    "lib/tokuboilerplate",
  }) do
    local src = fs.join(dir, d)
    if fs.exists(src) then
      fs.mv(src, fs.join(dir, (str.gsub(d, "tokuboilerplate", name))))
    end
  end

  for _, f in ipairs({
    "bin/tokuboilerplate.lua",
    "server/bin/tokuboilerplate.lua",
    "client/lib/tokuboilerplate.lua",
    "server/lib/tokuboilerplate.lua",
    "test/spec/tokuboilerplate.lua",
    "client/test/spec/tokuboilerplate.lua",
    "server/test/spec/tokuboilerplate.lua",
  }) do
    local src = fs.join(dir, f)
    if fs.exists(src) then
      fs.mv(src, fs.join(dir, (str.gsub(f, "tokuboilerplate", name))))
    end
  end

  for fp in fs.files(dir, { recurse = true }) do
    local content = fs.readfile(fp)
    if content:find("tokuboilerplate") then
      fs.writefile(fp, (str.gsub(content, "tokuboilerplate", name)))
    end
  end

  if opts.git ~= false then
    sys.execute({ "git", "init", dir })
  end

  io.stdout:write("Created web project: " .. name .. "\n")
  io.stdout:write("\nNext steps:\n")
  if dir ~= "." then
    io.stdout:write("  cd " .. dir .. "\n")
  end
  io.stdout:write("  toku build --test  # Build for testing\n")
  io.stdout:write("  toku start --test  # Start development server\n")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build

  err.assert(vdt.istable(opts))
  err.assert(vdt.istable(opts.config))

  opts.single = opts.single and str.gsub(opts.single, "^[^/]+/", "") or nil
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
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = str.stripprefix(select(i, ...), "server/")
    end
    return server_dir(spread(t))
  end

  local function test_dist_dir (...)
    return work_dir("test", "dist", ...)
  end

  local function test_server_dir (...)
    return work_dir("test", "server", ...)
  end

  local function test_server_dir_stripped (...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = str.stripprefix(select(i, ...), "server/")
    end
    return test_server_dir(spread(t))
  end

  local function client_dir (...)
    return work_dir("main", "client", ...)
  end

  local function client_dir_stripped (...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = str.stripprefix(select(i, ...), "client/")
    end
    return client_dir(spread(t))
  end

  local function test_client_dir (...)
    return work_dir("test", "client", ...)
  end

  local function test_client_dir_stripped (...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = str.stripprefix(select(i, ...), "client/")
    end
    return test_client_dir(spread(t))
  end

  local function dist_dir_client (...)
    return dist_dir("public", ...)
  end

  local function test_dist_dir_client (...)
    return test_dist_dir("public",...)
  end

  -- Hash public files is always enabled (no longer configurable)

  local function dist_dir_staging (...)
    return dist_dir("public-staging", ...)
  end

  local function test_dist_dir_staging (...)
    return test_dist_dir("public-staging", ...)
  end

  local function dist_dir_staging_stripped (...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = fs.stripparts(select(i, ...), 2)
    end
    return dist_dir("public-staging", spread(t))
  end

  local function test_dist_dir_staging_stripped (...)
    local t = {}
    for i = 1, select("#", ...) do
      t[i] = fs.stripparts(select(i, ...), 2)
    end
    return test_dist_dir("public-staging", spread(t))
  end

  local registered_public_files = {}

  local function register_public_file (filename)
    registered_public_files[filename] = true
  end

  local function make_hashed (get_manifest_path)
    return function (filename)
      local manifest_path = get_manifest_path()
      if fs.exists(manifest_path) then
        local manifest = dofile(manifest_path)
        if manifest[filename] then
          return manifest[filename]
        end
      end
      return filename
    end
  end

  local hashed = make_hashed(function () return dist_dir("hash-manifest-static.lua") end)
  local test_hashed = make_hashed(function () return test_dist_dir("hash-manifest-static.lua") end)
  local hashed_full = make_hashed(function () return dist_dir("hash-manifest.lua") end)
  local test_hashed_full = make_hashed(function () return test_dist_dir("hash-manifest.lua") end)

  local function remove_tk(fp)
    return common.remove_tk(fp, opts.config)
  end

  local function add_copied_target(dest, src, extra_srcs)
    return common.add_copied_target(target, dest, src, extra_srcs)
  end

  -- Build dependencies directory (host-native, for template processing)
  local build_deps_dir = work_dir("build-deps")
  local build_deps_ok = work_dir("build-deps.ok")
  local build_deps = tbl.get(opts, {"config", "env", "build", "dependencies"}) or {}
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
  local base_server_nginx_fg_cfg = "nginx-fg.conf"
  local base_server_luarocks_cfg = "luarocks.lua"
  local base_server_lua_modules = "lua_modules"
  local base_server_lua_modules_ok = "lua_modules.ok"

  local base_server_nginx_user = fs.exists("server/nginx.tk.conf") and "server/nginx.tk.conf"
    or fs.exists("server/nginx.conf") and "server/nginx.conf"
    or nil

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

  local base_client_pages = {}
  for i = 1, #base_client_bins do
    base_client_pages[i] = fs.stripparts(fs.stripextensions(base_client_bins[i]) .. ".js", 2)
  end

  local base_client_wasm = {}
  for i = 1, #base_client_bins do
    base_client_wasm[i] = fs.stripparts(fs.stripextensions(base_client_bins[i]) .. ".wasm", 2)
  end

  local public_files_static = arr.map(arr.map(arr.flatten({base_client_static, base_client_assets}), function (fp)
    return fs.stripparts(fp, 2)
  end), remove_tk)

  local public_files_wasm = arr.map(arr.flatten({base_client_pages, base_client_wasm}), remove_tk)

  local public_files = arr.flatten({public_files_static, public_files_wasm})

  local public_files_static_for_precache = public_files_static

  local base_env = {
    root_dir = fs.cwd(),
    skip_check = opts.skip_check,
    public_files = public_files,
    public_files_static_for_precache = public_files_static_for_precache,
    registered_public_files = registered_public_files,
    hash_public = true,
    var = function (n)
      err.assert(vdt.isstring(n))
      return arr.concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local server_env = {
    environment = "main",
    component = "server",
    target = "build",
    libs = base_server_libs,
    dist_dir = dist_dir(),
    public_dir = dist_dir_staging(),
    work_dir = server_dir(),
    openresty_dir = opts.openresty_dir,
    lua_modules = dist_dir(base_server_lua_modules),
    luarocks_cfg = server_dir(base_server_luarocks_cfg),
    hashed = hashed,
  }

  local test_server_env = {
    environment = "test",
    component = "server",
    target = "test-build",
    libs = base_server_libs,
    dist_dir = test_dist_dir(),
    public_dir = test_dist_dir_staging(),
    work_dir = test_server_dir(),
    openresty_dir = opts.openresty_dir,
    luarocks_cfg = test_server_dir(base_server_luarocks_cfg),
    lua = env.interpreter()[1],
    lua_path = get_lua_path(test_dist_dir()),
    lua_cpath = get_lua_cpath(test_dist_dir()),
    lua_modules = test_dist_dir(base_server_lua_modules),
    hashed = test_hashed,
  }

  local client_env = {
    environment = "main",
    component = "client",
    target = "build",
    dist_dir = dist_dir(),
    public_dir = dist_dir_staging(),
    static_files_ok = dist_dir("static-files.ok"),
    hash_precache_js = dist_dir("hash-precache.js"),
    work_dir = client_dir(),
    bundler_post_dir = client_dir("bundler-post"),
    build_dir = client_dir("build", "default-wasm", "build"),
    lua_path = get_lua_path(client_dir("build", "default-wasm", "build")),
    lua_cpath = get_lua_cpath(client_dir("build", "default-wasm", "build")),
    luarocks_cfg = client_dir("build", "default-wasm", "build", base_server_luarocks_cfg),
    hashed = hashed,
  }

  local test_client_env = {
    environment = "test",
    component = "client",
    target = "test-build",
    dist_dir = test_dist_dir(),
    public_dir = test_dist_dir_staging(),
    static_files_ok = test_dist_dir("static-files.ok"),
    hash_precache_js = test_dist_dir("hash-precache.js"),
    work_dir = test_client_dir(),
    bundler_post_dir = test_client_dir("bundler-post"),
    build_dir = test_client_dir("build", "default-wasm", "build"),
    lua_path = get_lua_path(test_client_dir("build", "default-wasm", "build")),
    lua_cpath = get_lua_cpath(test_client_dir("build", "default-wasm", "build")),
    luarocks_cfg = test_client_dir("build", "default-wasm", "build", base_server_luarocks_cfg),
    hashed = test_hashed,
  }

  local root_env = {
    environment = "main",
    component = "root",
    target = "build",
    dist_dir = dist_dir(),
    work_dir = work_dir(),
    hashed = hashed,
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
    hashed = test_hashed,
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
    e.client = tbl.merge({}, client_cfg, {
      public_files = public_files,
      public_files_static_for_precache = public_files_static_for_precache,
      registered_public_files = registered_public_files,
      hash_public = true,
    })
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
    str.upper(str.gsub(opts.config.env.name, "%W+", "_"))

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
    <% return str.quote(str.to_base64(readfile("res/web/run.sh"))) %>, server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_run_sh),
    <% return str.quote(str.to_base64(readfile("res/web/run.sh"))) %>, test_server_env) -- luacheck: ignore


  add_templated_target_base64(server_dir(base_server_luarocks_cfg),
    <% return str.quote(str.to_base64(readfile("res/web/luarocks.lua"))) %>, server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_luarocks_cfg),
    <% return str.quote(str.to_base64(readfile("res/web/luarocks.lua"))) %>, test_server_env) -- luacheck: ignore

  add_copied_target(
    dist_dir(base_server_run_sh),
    server_dir(base_server_run_sh))

  add_copied_target(
    test_dist_dir(base_server_run_sh),
    test_server_dir(base_server_run_sh))

  for _, flag in ipairs({
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

  for _, fp in ipairs(base_server_libs) do
    add_file_target(server_dir_stripped(remove_tk(fp)), fp, server_env)
  end

  for _, fp in ipairs(base_server_libs) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_root_libs) do
    add_file_target(server_dir(remove_tk(fp)), fp, server_env)
  end

  for _, fp in ipairs(base_root_libs) do
    add_file_target(test_server_dir(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_root_res) do
    add_file_target(server_dir(remove_tk(fp)), fp, server_env)
  end

  for _, fp in ipairs(base_root_res) do
    add_file_target(test_server_dir(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_server_deps) do
    add_file_target(server_dir_stripped(remove_tk(fp)), fp, server_env)
  end

  for _, fp in ipairs(base_server_deps) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_server_test_specs) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_server_test_res) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_server_test_res_templated) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
  end

  for _, fp in ipairs(base_client_test_specs) do
    add_file_target(test_client_dir_stripped(remove_tk(fp)), fp, test_client_env)
  end

  local env_configs = {
    { dist_dir_staging, dist_dir_staging_stripped,
      client_dir, client_dir_stripped, client_env,
      dist_dir_client,
      dist_dir("hash-static.ok"),
      dist_dir("hash-manifest-static.lua"),
      dist_dir("static-files.ok"),
      dist_dir("hash-precache.js") },
    { test_dist_dir_staging, test_dist_dir_staging_stripped,
      test_client_dir, test_client_dir_stripped, test_client_env,
      test_dist_dir_client,
      test_dist_dir("hash-static.ok"),
      test_dist_dir("hash-manifest-static.lua"),
      test_dist_dir("static-files.ok"),
      test_dist_dir("hash-precache.js") }
  }
  for _, config in ipairs(env_configs) do
    local staging_dir, staging_dir_stripped, cdir, cdir_stripped, env, final_dir, hash_static_ok, hash_static_manifest, static_files_ok, hash_precache_js = spread(config)

    fs.mkdirp(staging_dir())
    fs.mkdirp(cdir())

    for _, fp in ipairs(base_client_assets) do
      add_copied_target(staging_dir_stripped(remove_tk(fp)), fp,
        { cdir(base_client_lua_modules_deps_ok) })
    end

    for _, fp in ipairs(base_client_static) do
      add_copied_target(cdir_stripped(fp), fp)
      add_file_target(cdir(remove_tk(fp)), cdir_stripped(fp), env,
        arr.push({ cdir(base_client_lua_modules_deps_ok) },
          arr.spread(arr.map(arr.map(arr.flatten({base_client_res, base_client_res_templated}), remove_tk), cdir_stripped))))
      add_copied_target(staging_dir_stripped(remove_tk(fp)),
        cdir(remove_tk(fp)))
    end

    for _, fp in ipairs(base_client_deps) do
      add_copied_target(cdir_stripped(fp), fp,
        arr.push({ cdir(base_client_lua_modules_deps_ok) },
          arr.spread(arr.map(arr.map(arr.flatten({base_client_res, base_client_res_templated}), remove_tk), cdir_stripped))))
    end

    for _, fp in ipairs(base_client_libs) do
      add_copied_target(cdir_stripped(fp), fp,
        arr.push({ cdir(base_client_lua_modules_deps_ok) },
          arr.spread(arr.map(arr.map(arr.flatten({base_client_res, base_client_res_templated}), remove_tk), cdir_stripped))))
    end

    for _, fp in ipairs(base_root_libs) do
      add_file_target(cdir(remove_tk(fp)), fp, env,
        arr.push(arr.push({ cdir(base_client_lua_modules_deps_ok) },
          arr.spread(arr.map(arr.map(arr.flatten({base_client_res, base_client_res_templated}), remove_tk), cdir_stripped))),
          arr.spread(arr.map(arr.map(arr.copy({}, base_root_res), remove_tk), cdir))))
    end

    for _, fp in ipairs(base_root_res) do
      add_file_target(cdir(remove_tk(fp)), fp, env)
    end

    for _, fp in ipairs(base_client_bins) do
      add_copied_target(cdir_stripped(fp), fp,
        arr.push({ cdir(base_client_lua_modules_deps_ok) },
          arr.spread(arr.map(arr.map(arr.flatten({base_client_res, base_client_res_templated}), remove_tk), cdir_stripped))))
    end

    for _, fp in ipairs(base_client_res) do
      add_file_target(cdir_stripped(remove_tk(fp)), fp, env,
        arr.map(arr.copy({}, base_client_static), cdir_stripped))
    end

    for _, fp in ipairs(base_client_res_templated) do
      add_file_target(cdir_stripped(remove_tk(fp)), fp, env,
        arr.map(arr.copy({}, base_client_static), cdir_stripped))
    end

    for _, fp in ipairs(base_client_pages) do
      local nested_env = env.environment == "test" and "test" or "build"
      local pre = cdir("build", "default-wasm", nested_env, "bin", fs.stripextensions(fp)) .. ".lua"
      local post = cdir("bundler-post", fs.stripextensions(fp))
      local deps = { cdir(base_client_lua_modules_ok), pre }
      if has_build_deps then
        arr.push(deps, build_deps_ok)
      end
      local extra_rule_cflags = {}
      local extra_rule_ldflags = {}
      for k, v in pairs(tbl.get(env, {"rules"}) or {}) do
        if (type(k) == "string" and str.find(post, k)) or (type(k) == "function" and k(post)) then
          if v.cxxflags then arr.copy(extra_rule_cflags, v.cxxflags) end
          if v.ldflags then arr.copy(extra_rule_ldflags, v.ldflags) end
        end
      end
      target({ post }, deps, function ()
        fs.mkdirp(cdir("build", "default-wasm", nested_env))
        fs.pushd(cdir("build", "default-wasm", nested_env), function ()
          local lua_dir = cdir("build", "default-wasm", nested_env, "lua-5.1.5")
          local luac_bin = fs.join(lua_dir, "bin", "luac")
          local extra_cflags = arr.flatten({extra_rule_cflags, tbl.get(env, {"cxxflags"}) or {}})
          local extra_ldflags = arr.flatten({extra_rule_ldflags, tbl.get(env, {"ldflags"}) or {}})
          if hash_precache_js and fs.exists(hash_precache_js) then
            arr.push(extra_ldflags, "--pre-js", hash_precache_js)
          end
          local use_files = tbl.get(env, {"client", "files"})
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
      add_copied_target(staging_dir(fp), post)
      local wasm_dest = fs.join(fs.dirname(staging_dir(fp)), fs.stripextensions(fs.basename(staging_dir(fp))) .. ".wasm")
      local wasm_src = post .. ".wasm"
      add_copied_target(wasm_dest, wasm_src)
    end

    target(
      { cdir(base_client_lua_modules_deps_ok) },
      arr.push({ opts.config_file },
        arr.spread(arr.map(arr.flatten({arr.map(arr.copy({}, base_client_res), remove_tk), arr.map(arr.copy({}, base_client_res_templated), remove_tk)}), cdir_stripped))),
      function ()
        local nested_env = env.environment == "test" and "test" or "build"
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
            rules = opts.config.env.rules,
            public_files_static_for_precache = public_files_static_for_precache,
            registered_public_files = registered_public_files,
            hashed = env.environment == "test" and test_hashed or hashed,
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
      arr.push(arr.push(arr.push({ opts.config_file, cdir(base_client_lua_modules_deps_ok), hash_static_ok },
        arr.spread(has_build_deps and { build_deps_ok } or {})),
        arr.spread(arr.map(arr.flatten({base_client_bins, base_client_libs, base_client_deps}), cdir_stripped))),
        arr.spread(arr.map(arr.map(arr.flatten({base_root_libs, base_root_res}), remove_tk), cdir))),
      function ()
        local nested_env = env.environment == "test" and "test" or "build"
        local config_file = fs.absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
            rules = opts.config.env.rules,
            public_files_static_for_precache = public_files_static_for_precache,
            registered_public_files = registered_public_files,
            hashed = env.environment == "test" and test_hashed or hashed,
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

    local static_staging_files =
      arr.map(arr.map(arr.flatten({base_client_static, base_client_assets}), staging_dir_stripped), remove_tk)
    local wasm_staging_files =
      arr.map(arr.map(arr.flatten({base_client_pages, base_client_wasm}), staging_dir), remove_tk)
    local is_main = env.environment == "main"
    local hash_ok = is_main and dist_dir("hash.ok") or test_dist_dir("hash.ok")
    local hash_manifest = is_main and dist_dir("hash-manifest.lua") or test_dist_dir("hash-manifest.lua")

    target(
      { hash_static_ok },
      arr.push(arr.copy({}, static_staging_files), static_files_ok),
        function ()
          local manifest = {}
          local files_to_hash = {}
          for _, fp in ipairs(static_staging_files) do
            local rel = str.stripprefix(fp, staging_dir() .. "/")
            files_to_hash[rel] = fp
          end
          for rel in pairs(registered_public_files) do
            local fp = staging_dir(rel)
            if fs.exists(fp) then
              files_to_hash[rel] = fp
            end
          end
          for rel, fp in pairs(files_to_hash) do
            local hash = common.compute_file_hash(fp)
            local hashed_rel = common.hash_filename(rel, hash)
            manifest[rel] = hashed_rel
          end
          local manifest_content = "return {\n"
          for orig, h in pairs(manifest) do
            manifest_content = manifest_content .. str.format("  [%q] = %q,\n", orig, h)
          end
          manifest_content = manifest_content .. "}\n"
          fs.writefile(hash_static_manifest, manifest_content)
          local js_parts = { "self.HASH_MANIFEST = {" }
          local first = true
          for orig, h in pairs(manifest) do
            if not first then arr.push(js_parts, ",") end
            first = false
            arr.push(js_parts, str.format("[atob(%q)]:%q", str.to_base64(orig), h))
          end
          for _, wasm_file in ipairs(public_files_wasm) do
            if not first then arr.push(js_parts, ",") end
            first = false
            arr.push(js_parts, str.format("[atob(%q)]:%q", str.to_base64(wasm_file), wasm_file))
          end
          arr.push(js_parts, "};")
          fs.writefile(hash_precache_js, arr.concat(js_parts, ""))
          fs.touch(hash_static_ok)
        end)

      target(
        { hash_ok },
        arr.flatten({ hash_static_ok, wasm_staging_files }),
        function ()
          local static_manifest = fs.exists(hash_static_manifest) and dofile(hash_static_manifest) or {}
          local mapping = {}
          local manifest = {}
          local build_id = rand.alnum(24)
          local function make_placeholder(filename)
            return "___SANTOKU_" .. build_id .. "_" .. str.gsub(filename, "[^%w]", "_") .. "___"
          end
          if fs.exists(final_dir()) then
            arr.ieach(fun.take(fs.rm, 1), fs.files(final_dir(), true))
            fs.rmdirs(final_dir())
          end
          for rel, hashed_rel in pairs(static_manifest) do
            local tag = make_placeholder(rel)
            mapping[tag] = hashed_rel
            manifest[rel] = hashed_rel
          end
          local files_to_hash = {}
          for rel in pairs(static_manifest) do
            local fp = staging_dir(rel)
            if fs.exists(fp) then
              files_to_hash[rel] = fp
            end
          end
          for _, fp in ipairs(wasm_staging_files) do
            local rel = str.stripprefix(fp, staging_dir() .. "/")
            files_to_hash[rel] = fp
          end
          for rel, fp in pairs(files_to_hash) do
            if not manifest[rel] then
              local hash = common.compute_file_hash(fp)
              local hashed_rel = common.hash_filename(rel, hash)
              manifest[rel] = hashed_rel
            end
            local tag = make_placeholder(rel)
            mapping[tag] = manifest[rel]
          end
          for rel, fp in pairs(files_to_hash) do
            local hashed_rel = manifest[rel]
            local dest = final_dir(hashed_rel)
            fs.mkdirp(fs.dirname(dest))
            fs.writefile(dest, fs.readfile(fp))
          end
          local function escape_pattern(s)
            return str.gsub(s, "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
          end
          for rel in pairs(files_to_hash) do
            local hashed_rel = manifest[rel]
            local dest = final_dir(hashed_rel)
            if common.is_text_file(dest) then
              local content = fs.readfile(dest)
              for tag, h in pairs(mapping) do
                content = str.gsub(content, escape_pattern(tag), h)
              end
              for orig, h in pairs(manifest) do
                content = str.gsub(content, "\"" .. escape_pattern(orig) .. "\"", "\"" .. h .. "\"")
                content = str.gsub(content, "'" .. escape_pattern(orig) .. "'", "'" .. h .. "'")
                content = str.gsub(content, "\"/" .. escape_pattern(orig) .. "\"", "\"/" .. h .. "\"")
                content = str.gsub(content, "'/" .. escape_pattern(orig) .. "'", "'/" .. h .. "'")
              end
              fs.writefile(dest, content)
            end
          end
          local manifest_content = "return {\n"
          for orig, h in pairs(manifest) do
            manifest_content = manifest_content .. str.format("  [%q] = %q,\n", orig, h)
          end
          manifest_content = manifest_content .. "}\n"
          fs.writefile(hash_manifest, manifest_content)
          fs.touch(hash_ok)
        end)

  end

  target(
    { server_dir(base_server_lua_modules_ok) },
    arr.push(arr.push({ server_dir(base_server_luarocks_cfg) },
      arr.spread(arr.map(arr.map(arr.flatten({base_server_libs, base_server_deps}), server_dir_stripped), remove_tk))),
      arr.spread(arr.map(arr.map(arr.flatten({base_root_libs, base_root_res}), server_dir), remove_tk))),
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
    arr.push(arr.push({ test_server_dir(base_server_luarocks_cfg) },
      arr.spread(arr.map(arr.map(arr.flatten({base_server_libs, base_server_deps}), test_server_dir_stripped), remove_tk))),
      arr.spread(arr.map(arr.map(arr.flatten({base_root_libs, base_root_res}), test_server_dir), remove_tk))),
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

  local function compute_nginx_context(e, nginx_cfg, foreground)
    local modules = {}
    for _, mod in ipairs(nginx_cfg.modules or {}) do
      local path = env.searchpath(mod, fs.join(e.dist_dir, "lua_modules/share/lua/5.1/?.lua"))
      modules[mod] = path and str.stripprefix(path, e.dist_dir .. "/") or nil
    end
    return {
      nginx = tbl.merge({
        foreground = foreground,
        daemon = "off",
        pid = "server.pid",
        error_log = foreground and "stderr" or "logs/error.log",
        access_log = "logs/access.log",
      }, nginx_cfg),
      modules = modules,
      lua_package_path = "lua_modules/share/lua/5.1/?.lua;lua_modules/share/lua/5.1/?/init.lua;" .. (opts.openresty_dir or "") .. "/lualib/?.lua;" .. (opts.openresty_dir or "") .. "/lualib/?/init.lua;;",
      lua_package_cpath = "lua_modules/lib/lua/5.1/?.so;" .. (opts.openresty_dir or "") .. "/lualib/?.so;;",
      openresty_dir = opts.openresty_dir,
    }
  end

  if base_server_nginx_user then
    local nginx_is_template = str.find(base_server_nginx_user, "%.tk%.")

    local function render_nginx(src, dest, e, nginx_ctx, hashed_fn)
      fs.mkdirp(fs.dirname(dest))
      local env_with_nginx = tbl.assign({}, e, { nginx = nginx_ctx })
      env_with_nginx.hashed = hashed_fn
      if nginx_is_template then
        local t, ds = common.with_build_deps(has_build_deps and build_deps_dir or nil, function ()
          return tmpl.renderfile(src, env_with_nginx, _G)
        end)
        fs.writefile(dest, t)
        fs.writefile(dest .. ".d", tmpl.serialize_deps(src, dest, ds))
      else
        fs.writefile(dest, fs.readfile(src))
      end
    end

    local nginx_deps = { server_dir(base_server_lua_modules_ok), dist_dir("hash.ok"), base_server_nginx_user }
    if has_build_deps then
      arr.push(nginx_deps, build_deps_ok)
    end

    target({ server_dir(base_server_nginx_cfg) }, nginx_deps,
      function ()
        local nginx_cfg = opts.config.env.nginx or {}
        local ctx = compute_nginx_context(server_env, nginx_cfg, false)
        render_nginx(base_server_nginx_user, server_dir(base_server_nginx_cfg), server_env, ctx, hashed_full)
      end)

    target({ server_dir(base_server_nginx_fg_cfg) }, nginx_deps,
      function ()
        local nginx_cfg = opts.config.env.nginx or {}
        local ctx = compute_nginx_context(server_env, nginx_cfg, true)
        render_nginx(base_server_nginx_user, server_dir(base_server_nginx_fg_cfg), server_env, ctx, hashed_full)
      end)

    add_copied_target(dist_dir(base_server_nginx_cfg), server_dir(base_server_nginx_cfg))
    add_copied_target(dist_dir(base_server_nginx_fg_cfg), server_dir(base_server_nginx_fg_cfg))

    local test_nginx_deps = { test_server_dir(base_server_lua_modules_ok), test_dist_dir("hash.ok"), base_server_nginx_user }
    if has_build_deps then
      arr.push(test_nginx_deps, build_deps_ok)
    end

    target({ test_server_dir(base_server_nginx_cfg) }, test_nginx_deps,
      function ()
        local nginx_cfg = opts.config.env.nginx or {}
        local ctx = compute_nginx_context(test_server_env, nginx_cfg, false)
        render_nginx(base_server_nginx_user, test_server_dir(base_server_nginx_cfg), test_server_env, ctx, test_hashed_full)
      end)

    target({ test_server_dir(base_server_nginx_fg_cfg) }, test_nginx_deps,
      function ()
        local nginx_cfg = opts.config.env.nginx or {}
        local ctx = compute_nginx_context(test_server_env, nginx_cfg, true)
        render_nginx(base_server_nginx_user, test_server_dir(base_server_nginx_fg_cfg), test_server_env, ctx, test_hashed_full)
      end)

    add_copied_target(test_dist_dir(base_server_nginx_cfg), test_server_dir(base_server_nginx_cfg))
    add_copied_target(test_dist_dir(base_server_nginx_fg_cfg), test_server_dir(base_server_nginx_fg_cfg))
  end

  local build_deps_list = {
    dist_dir(base_server_run_sh),
    server_dir(base_server_lua_modules_ok),
    client_dir(base_client_lua_modules_ok),
    dist_dir("hash.ok") }

  local test_build_deps_list = {
    test_dist_dir(base_server_run_sh),
    test_server_dir(base_server_lua_modules_ok),
    test_client_dir(base_client_lua_modules_ok),
    test_dist_dir("hash.ok") }

  if base_server_nginx_user then
    arr.push(build_deps_list, dist_dir(base_server_nginx_cfg))
    arr.push(build_deps_list, dist_dir(base_server_nginx_fg_cfg))
    arr.push(test_build_deps_list, test_dist_dir(base_server_nginx_cfg))
    arr.push(test_build_deps_list, test_dist_dir(base_server_nginx_fg_cfg))
  end

  target(
    { "build" },
    arr.push(arr.push(build_deps_list,
      arr.spread(arr.map(arr.map(arr.flatten({base_client_static, base_client_assets}),
        dist_dir_staging_stripped), remove_tk))),
      arr.spread(arr.map(arr.map(arr.flatten({base_client_pages, base_client_wasm}),
        dist_dir_staging), remove_tk))), true)

  target(
    { "test-build" },
    arr.push(arr.push(test_build_deps_list,
      arr.spread(arr.map(arr.map(arr.flatten({base_client_static, base_client_assets}),
        test_dist_dir_staging_stripped), remove_tk))),
      arr.spread(arr.map(arr.map(arr.flatten({base_client_pages, base_client_wasm}),
        test_dist_dir_staging), remove_tk))), true)

  target(
    { "start" },
    { "build" },
    function (_, _, opts)
      opts = opts or {}
      fs.mkdirp(dist_dir())
      return fs.pushd(dist_dir(), function ()
        if opts.fg then
          sys.execp("sh", { "run.sh", "--fg" })
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
          sys.execp("sh", { "run.sh", "--fg" })
        else
          sys.execute({ "sh", "-c", "sh run.sh &" })
        end
      end)
    end)

  -- Detect which test set --single belongs to based on path
  local function get_single_target(single)
    if not single then return nil, nil end
    if str.match(single, "^client/test/") or str.match(single, "^client/") then
      return "client", str.gsub(single, "^client/test/spec/", "test/spec/")
    elseif str.match(single, "^server/test/") or str.match(single, "^server/") then
      return "server", str.gsub(single, "^server/test/spec/", "test/spec/")
    elseif str.match(single, "^test/") then
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
    arr.push(arr.push(
      { test_client_dir(base_client_lua_modules_ok) },
      arr.spread(arr.map(arr.map(arr.flatten({base_server_test_specs, base_server_test_res_templated, base_server_test_res}), remove_tk), test_server_dir_stripped))),
      arr.spread(arr.map(arr.map(arr.copy({}, base_client_test_specs), remove_tk), test_client_dir_stripped))),
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
        local pid = str.match(fs.readfile(pid_file), "(%d+)")
        if not pid then
          err.error("fatal", "Server failed to start: invalid pid file")
        end
        -- Check if process is still alive
        local alive = err.pcall(sys.execute, { "kill", "-0", pid })
        if not alive then
          err.error("fatal", "Server failed to start: process died immediately (check nginx error log)")
        end

        -- Start log tailing if requested (and not already running)
        local tail_pid_file = test_dist_dir("logs", "tail.pid")
        if opts.show_logs then
          local tail_running = false
          if fs.exists(tail_pid_file) then
            local existing_pid = str.match(fs.readfile(tail_pid_file), "(%d+)")
            if existing_pid then
              tail_running = err.pcall(sys.execute, { "kill", "-0", existing_pid })
            end
          end
          if not tail_running then
            sys.execute({ "sh", "-c",
              "tail -f " .. test_dist_dir("logs", "access.log") .. " " .. test_dist_dir("logs", "error.log") ..
              " & echo $! > " .. tail_pid_file })
          end
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
    (function (ok, ...)
      if not ok then
        err.error("inotify not found", ...)
      end
    end)(err.pcall(sys.execute, { "sh", "-c", "type inotifywait >/dev/null 2>/dev/null" }))
    local config_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
    while true do
      if config_mtime then
        local new_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
        if new_mtime and new_mtime > config_mtime then
          print("\n[iterate] " .. opts.config_file .. " changed - please restart iterate\n")
          config_mtime = new_mtime
        end
      end
      (function (ok, first, ...)
        if not ok then
          if first == "fatal" then
            err.error(first, ...)
          end
          local msg = tostring(first)
          if str.match(msg, "interrupt") or str.match(msg, "SIGINT") then
            err.error(first, ...)
          end
          print(first, ...)
        end
      end)(err.pcall(build, { "test" }, opts.verbosity, true))
      local dfile_dirs = {}
      err.pcall(function ()
        for dfile in fs.files(work_dir(), true) do
          if str.find(dfile, "%.d$") then
            local data = fs.readfile(dfile)
            local file_deps = tmpl.deserialize_deps(data)
            for fp in pairs(file_deps) do
              local dir = fs.dirname(fp)
              if dir and dir ~= "" and dir ~= "." then
                dfile_dirs[dir] = true
              end
            end
          end
        end
      end)
      ;(function (ok, first, ...)
        if not ok then
          local msg = tostring(first)
          if str.match(msg, "interrupt") or str.match(msg, "SIGINT") or str.match(msg, "signaled") then
            err.error(first, ...)
          end
        end
      end)(err.pcall(function ()
        local watch_dirs = { "client", "server", "res", "lib", "bin", "test", opts.config_file }
        for dir in pairs(dfile_dirs) do
          watch_dirs[#watch_dirs + 1] = dir
        end
        local existing_dirs = {}
        for i = 1, #watch_dirs do
          if fs.exists(watch_dirs[i]) then
            existing_dirs[#existing_dirs + 1] = watch_dirs[i]
          end
        end
        sys.execute({
          "inotifywait", "-qr",
          "-e", "close_write", "-e", "modify",
          "-e", "move", "-e", "create", "-e", "delete",
          arr.spread(existing_dirs)
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
          sys.execute({ "kill", "-15", str.match(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  target({ "test-stop" }, {}, function (_, _)
    fs.mkdirp(test_dist_dir())
    return fs.pushd(test_dist_dir(), function ()
      if fs.exists("logs/tail.pid") then
        err.pcall(function ()
          sys.execute({ "kill", "-15", str.match(fs.readfile("logs/tail.pid"), "(%d+)") })
        end)
        sys.sleep(0.25)
        fs.rm("logs/tail.pid")
      end
      if fs.exists("server.pid") then
        err.pcall(function ()
          sys.execute({ "kill", "-15", str.match(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  for _, fp in ipairs(submake.targets) do
    local dfile = fp .. ".d"
    if fs.exists(dfile) then
      local all_chunks = {}
      for line in fs.lines(dfile) do
        local parts = str.splits(line, "%s*:%s*", false)
        for i = 1, #parts do
          all_chunks[#all_chunks + 1] = str.sub(parts[i])
        end
      end
      if #all_chunks > 0 then
        target({ all_chunks[1] }, arr.slice(all_chunks, 2))
      end
    end
  end

  local configure = tbl.get(opts, {"config", "env", "configure"})
  if configure then
    configure(submake, { root = root_env, client = client_env, server = server_env }, register_public_file)
    configure(submake, { root = test_root_env, client = test_client_env, server = test_server_env }, register_public_file)
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
