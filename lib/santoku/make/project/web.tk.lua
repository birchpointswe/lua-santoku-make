<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
%>

local bundle = require("santoku.bundle")
local env = require("santoku.env")
local fun = require("santoku.functional")
local make = require("santoku.make")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local tmpl = require("santoku.template")
local varg = require("santoku.varg")
local vdt = require("santoku.validate")
local err = require("santoku.error")
local fs = require("santoku.fs")

local arr = require("santoku.array")
local amap = arr.map
local spread = arr.spread
local aincludes = arr.includes
local extend = arr.extend
local push = arr.push
local concat = arr.concat

local it = require("santoku.iter")
local find = it.find
local chain = it.chain
local ivals = it.ivals
local collect = it.collect
local filter = it.filter
local map = it.map

local str = require("santoku.string")
local from_base64 = str.from_base64
local stripprefix = str.stripprefix
local supper = string.upper
local sformat = string.format
local smatch = string.match
local gsub = string.gsub

local function create ()
  err.error("create web not yet implemented")
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

  -- TODO: It would be nice if santoku ivals returned an empty iterator for
  -- nil instead of erroring. It would allow omitting the {} below
  local function get_action (fp)
    local ext = fs.extension(fp)
    local match_fp = fun.bind(smatch, fp)
    if (opts.exts and not aincludes(opts.exts, ext)) or
        find(match_fp, ivals(tbl.get(opts, "rules", "exclude") or {}))
    then
      return "ignore"
    elseif find(match_fp, ivals(tbl.get(opts, "rules", "copy") or {}))
      or not (str.find(fp, "%.tk$") or
              str.find(fp, "%.tk%."))
    then
      return "copy"
    else
      return "template"
    end
  end

  local function force_template (fp)
    local match_fp = fun.bind(smatch, fp)
    return find(match_fp, ivals(tbl.get(opts.config, "rules", "template") or {}))
  end

  local function force_template_client (fp)
    local match_fp = fun.bind(smatch, fp)
    return find(match_fp, ivals(tbl.get(opts.config, "rules", "template_client") or {}))
  end

  local function remove_tk (fp)
    return get_action(fp) == "template"
      and str.gsub(fp, "%.tk", "")
      or fp
  end

  -- TODO: use fs.copy
  local function add_copied_target (dest, src, extra_srcs)
    extra_srcs = extra_srcs or {}
    target({ dest }, extend({ src }, extra_srcs), function ()
      fs.mkdirp(fs.dirname(dest))
      fs.writefile(dest, fs.readfile(src))
    end)
  end

  local function add_file_target (dest, src, env, extra_srcs)
    extra_srcs = extra_srcs or {}
    local action = get_action(src, opts.config)
    if action == "copy" then
      return add_copied_target(dest, src, extra_srcs)
    elseif action == "template" then
      dest = str.gsub(dest, "%.tk", "")
      target({ dest }, extend({ src, opts.config_file }, extra_srcs), function ()
        fs.mkdirp(fs.dirname(dest))
        local t, ds = tmpl.renderfile(src, env, _G)
        fs.writefile(dest, t)
        fs.writefile(dest .. ".d", tmpl.serialize_deps(src, dest, ds))
      end)
    end
  end

  local function add_templated_target_base64 (dest, data, env, extra_srcs)
    extra_srcs = extra_srcs or {}
    target({ dest }, extend({ opts.config_file }, extra_srcs), function ()
      fs.mkdirp(fs.dirname(dest))
      local t, ds = tmpl.render(from_base64(data), env, _G)
      fs.writefile(dest, t)
      fs.writefile(dest .. ".d", tmpl.serialize_deps(dest, opts.config_file, ds))
    end)
  end

  local function get_lua_version ()
    return (smatch(_VERSION, "(%d+.%d+)"))
  end

  local function get_require_paths (prefix, ...)
    local pfx = prefix and fs.join(prefix, "lua_modules") or "lua_modules"
    local ver = get_lua_version()
    return concat(varg.reduce(function (t, n)
      return push(t, fs.join(pfx, sformat(n, ver)))
    end, {}, ...), ";")
  end

  local function get_lua_path (prefix)
    return get_require_paths(prefix,
      "share/lua/%s/?.lua",
      "share/lua/%s/?/init.lua",
      "lib/lua/%s/?.lua",
      "lib/lua/%s/?/init.lua")
  end

  local function get_lua_cpath (prefix)
    return get_require_paths(prefix,
      "lib/lua/%s/?.so",
      "lib/lua/%s/loadall.so")
  end

  local function get_files (dir, check_tpl, check_tpl_client)
    local tpl = check_tpl and {} or nil
    local tpl_client = check_tpl_client and {} or nil
    if not fs.exists(dir) then
      return {}, tpl, tpl_client
    end
    return collect(filter(function (fp)
      if check_tpl and force_template(fp) then
        push(tpl, fp)
        return false
      end
      if check_tpl_client and force_template_client(fp) then
        push(tpl_client, fp)
        return false
      end
      return get_action(fp) ~= "ignore"
    end, fs.files(dir, true))), tpl, tpl_client
  end

  local base_server_libs = get_files("server/lib")
  local base_server_deps = get_files("server/deps")
  local base_server_test_specs = get_files("server/test/spec")
  local base_server_test_res, base_server_test_res_templated = get_files("server/test/res", true)
  local base_server_run_sh = "run.sh"
  local base_server_nginx_cfg = "nginx.conf"
  local base_server_nginx_daemon_cfg = "nginx-daemon.conf"
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

  local base_client_lua_modules_ok = "lua_modules.ok"
  local base_client_lua_modules_deps_ok = "lua_modules.deps.ok"

  local base_client_pages = collect(map(function (fp)
    return fs.stripparts(fs.stripextensions(fp) .. ".js", 2)
  end, ivals(base_client_bins)))

  local function wrap_require (env)
    env = env or {}
    return function (mod)
      local oldpath = package.path
      local oldcpath = package.cpath
      package.path = env.lua_path or ""
      package.cpath = env.lua_cpath or ""
      return varg.tup(function (...)
        package.path = oldpath
        package.cpath = oldcpath
        return ...
      end, require(mod))
    end
  end

  local base_env = {
    root_dir = fs.cwd(),
    profile = opts.profile,
    trace = opts.trace,
    skip_check = opts.skip_check,
    coverage = opts.coverage,
    var = function (n)
      err.assert(vdt.isstring(n))
      return concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local server_env = {
    environment = "main",
    component = "server",
    target = "build",
    background = opts.background,
    libs = base_server_libs,
    dist_dir = dist_dir(),
    public_dir = dist_dir_client(),
    work_dir = server_dir(),
    openresty_dir = opts.openresty_dir,
    lua_modules = dist_dir(base_server_lua_modules),
    luarocks_cfg = server_dir(base_server_luarocks_cfg),
  }

  local server_daemon_env = {
    background = true
  }

  local test_server_env = {
    environment = "test",
    component = "server",
    target = "test-build",
    background = opts.background,
    libs = base_server_libs,
    dist_dir = test_dist_dir(),
    public_dir = test_dist_dir_client(),
    work_dir = test_server_dir(),
    openresty_dir = opts.openresty_dir,
    luarocks_cfg = test_server_dir(base_server_luarocks_cfg),
    luacov_config = test_server_dir("build", "default", "test", "luacov.lua"),
    lua = env.interpreter()[1],
    lua_path = get_lua_path(test_dist_dir()),
    lua_cpath = get_lua_cpath(test_dist_dir()),
    lua_modules = test_dist_dir(base_server_lua_modules),
  }

  local test_server_daemon_env = {
    background = true
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

  -- TODO: Expose both require_client and require_server to both client and
  -- server builds
  client_env.require_client = wrap_require(client_env)
  test_client_env.require_client = wrap_require(test_client_env)

  tbl.merge(server_env, base_env, opts.config.env.server)
  tbl.merge(server_daemon_env, server_env)
  tbl.merge(test_server_env, base_env, opts.config.env.server)
  tbl.merge(test_server_daemon_env, test_server_env)
  tbl.merge(client_env, base_env, opts.config.env.client)
  tbl.merge(test_client_env, base_env, opts.config.env.client)

  opts.config.env.variable_prefix =
    opts.config.env.variable_prefix or
    supper((gsub(opts.config.env.name, "%W+", "_")))

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

  add_templated_target_base64(server_dir(base_server_nginx_daemon_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.tk.conf"))) %>, server_daemon_env, -- luacheck: ignore
    { server_dir(base_server_lua_modules_ok) })

  add_templated_target_base64(test_server_dir(base_server_nginx_daemon_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.tk.conf"))) %>, test_server_daemon_env, -- luacheck: ignore
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
    dist_dir(base_server_nginx_daemon_cfg),
    server_dir(base_server_nginx_daemon_cfg))

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

  add_copied_target(
    test_dist_dir(base_server_nginx_daemon_cfg),
    test_server_dir(base_server_nginx_daemon_cfg))

  for flag in ivals({
    "profile", "trace", "coverage", "skip_check"
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
    amap({ "profile.flag", "trace.flag", "coverage.flag", "skip_check.flag" }, work_dir))

  for fp in ivals(base_server_libs) do
    add_file_target(server_dir_stripped(remove_tk(fp)), fp, server_env)
  end

  for fp in ivals(base_server_libs) do
    add_file_target(test_server_dir_stripped(remove_tk(fp)), fp, test_server_env)
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
          bundle(pre, fs.dirname(post), {
            cc = "emcc",
            ignores = { "debug" },
            path = get_lua_path(cdir("build", "default-wasm", "build")),
            cpath = get_lua_cpath(cdir("build", "default-wasm", "build")),
            flags = extend({
              "-sASSERTIONS", "-sSINGLE_FILE", "-sALLOW_MEMORY_GROWTH",
              "-I" .. cdir("build", "default-wasm", "build", "lua-5.1.5", "include"),
              "-L" .. cdir("build", "default-wasm", "build", "lua-5.1.5", "lib"),
              "-llua", "-lm",
            }, extra_flags,
              tbl.get(env, "cxxflags") or {},
              tbl.get(env, "ldflags") or {})
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
            profile = opts.profile,
            trace = opts.trace,
            skip_check = opts.skip_check,
            coverage = opts.coverage,
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
        amap(extend({}, base_client_bins, base_client_libs, base_client_deps), cdir_stripped)),
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
            profile = opts.profile,
            trace = opts.trace,
            skip_check = opts.skip_check,
            coverage = opts.coverage,
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
      amap(amap(extend({}, base_server_libs, base_server_deps), server_dir_stripped), remove_tk)),
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
          profile = opts.profile,
          trace = opts.trace,
          skip_check = opts.skip_check,
          coverage = opts.coverage,
          skip_tests = true,
          dir = server_dir(),
        }).install()
        fs.touch(base_server_lua_modules_ok)
      end)
    end)

  target(
    { test_server_dir(base_server_lua_modules_ok) },
    extend({ test_server_dir(base_server_luarocks_cfg) },
      amap(amap(extend({}, base_server_libs, base_server_deps), test_server_dir_stripped), remove_tk)),
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
          profile = opts.profile,
          trace = opts.trace,
          skip_check = opts.skip_check,
          coverage = opts.coverage,
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
      dist_dir(base_server_nginx_daemon_cfg),
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
      test_dist_dir(base_server_nginx_daemon_cfg),
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
    function (_, _, background)
      fs.mkdirp(dist_dir())
      return fs.pushd(dist_dir(), function ()
        sys.execute({
          "sh", "run.sh",
          env = {
            [base_env.var("BACKGROUND")] = (background or opts.background) and "1" or "0"
          },
        })
      end)
    end)

  target(
    { "test-start" },
    { "test-build" },
    function (_, _, background)
      fs.mkdirp(test_dist_dir())
      return fs.pushd(test_dist_dir(), function ()
        sys.execute({
          "sh", "run.sh",
          env = {
            [base_env.var("BACKGROUND")] = (background or opts.background) and "1" or "0"
          },
        })
      end)
    end)

  target(
    { "test" },
    amap(extend({},
      amap(extend({}, base_server_test_specs, base_server_test_res_templated), remove_tk),
      base_server_test_res), test_server_dir_stripped),
    function (_, _, iterating)
      build({ "stop", "test-stop" }, opts.verbosity)
      build({ "test-start" }, opts.verbosity, true)
      local config_file = fs.absolute(opts.config_file)
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
          single = opts.single and remove_tk(opts.single) or nil,
          profile = opts.profile,
          trace = opts.trace,
          skip_check = opts.skip_check,
          coverage = opts.coverage,
          wasm = true,
          dir = test_client_dir(),
        }).test()
      end)
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
          single = opts.single and remove_tk(opts.single) or nil,
          profile = opts.profile,
          trace = opts.trace,
          skip_check = opts.skip_check,
          coverage = opts.coverage,
          lua = test_server_env.lua,
          lua_path = test_server_env.lua_path,
          lua_cpath = test_server_env.lua_cpath,
          dir = test_server_dir(),
        })
        lib.test({ skip_check = true })
        if not iterating then
          build({ "test-stop" }, opts.verbosity)
        end
        lib.check()
      end)
    end)

  target({ "iterate" }, {}, function (_, _)
    varg.tup(function (ok, ...)
      if not ok then
        err.error("inotify not found", ...)
      end
    end, err.pcall(sys.execute, { "sh", "-c", "type inotifywait >/dev/null 2>/dev/null" }))
    while true do
      varg.tup(function (ok, ...)
        if not ok then
          print(...)
        end
      end, err.pcall(build, { "test" }, opts.verbosity, true))
      sys.execute({
        "inotifywait", "-qr",
        "-e", "close_write", "-e", "modify",
        "-e", "move", "-e", "create", "-e", "delete",
        spread(collect(filter(function (fp)
          return fs.exists(fp)
        end, chain(fs.files("."), ivals({ "client", "server" })))))
      })
      sys.sleep(.25)
    end
  end)

  target({ "stop" }, {}, function ()
    fs.mkdirp(dist_dir())
    return fs.pushd(dist_dir(), function ()
      if fs.exists("server.pid") then
        err.pcall(function ()
          sys.execute({ "kill", smatch(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  target({ "test-stop" }, {}, function (_, _)
    fs.mkdirp(test_dist_dir())
    return fs.pushd(test_dist_dir(), function ()
      if fs.exists("server.pid") then
        err.pcall(function ()
          sys.execute({ "kill", smatch(fs.readfile("server.pid"), "(%d+)") })
        end)
      end
    end)
  end)

  local configure = tbl.get(opts, "config", "env", "configure")
  if configure then
    configure(submake, client_env, server_env)
    configure(submake, test_client_env, test_server_env)
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
