<%
  str = require("santoku.string")
  fs = require("santoku.fs")
  basexx = require("basexx")
%>

local env = require("santoku.env")
local err = require("santoku.err")
local compat = require("santoku.compat")
local tup = require("santoku.tuple")
local fs = require("santoku.fs")
local fun = require("santoku.fun")
local gen = require("santoku.gen")
local inherit = require("santoku.inherit")
local str = require("santoku.string")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local tpl = require("santoku.template")
local vec = require("santoku.vector")
-- local bundle = require("santoku.bundle")

local basexx = require("basexx")

-- TODO: Web projects

local M = {}

local ERR = {
  NO_INOTIFY = "missing inotify"
}

M.create = function ()
  return false, "create web unimplemented"
end

M.init = function (opts)

  local make = require("santoku.make")(opts)

  assert(compat.istype.table(opts))
  assert(compat.istype.table(opts.config))

  return err.pwrap(function (check_init)

    opts.single = opts.single and opts.single:gsub("^[^/]+/", "") or false
    opts.profile = opts.profile or false
    opts.skip_coverage = opts.profile or opts.skip_coverage or false
    opts.iterate = opts.iterate or false

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
      return server_dir(tup.map(fun.bindr(str.stripprefix, "server/"), ...))
    end

    local function test_dist_dir (...)
      return work_dir("test", "dist", ...)
    end

    local function test_server_dir (...)
      return work_dir("test", "server", ...)
    end

    local function test_server_dir_stripped (...)
      return test_server_dir(tup.map(fun.bindr(str.stripprefix, "server/"), ...))
    end

    local function client_dir (...)
      return work_dir("main", "client", ...)
    end

    local function test_client_dir (...)
      return work_dir("test", "client", ...)
    end

    local function dist_dir_client (...)
      return dist_dir("public", tup.map(fun.compose(
        fun.bindr(str.stripprefix, "client/static"),
        fun.bindr(str.stripprefix, "client/assets")), ...))
    end

    local function test_dist_dir_client (...)
      return test_dist_dir("public", tup.map(fun.compose(
        fun.bindr(str.stripprefix, "client/static"),
        fun.bindr(str.stripprefix, "client/assets")), ...))
    end

    -- TODO: use fs.copy
    local function add_copied_target (dest, src, extra_srcs)
      extra_srcs = extra_srcs or vec()
      make:target(
        vec(dest),
        vec(src):extend(extra_srcs),
        function (_, _, check_target)
          check_target(fs.mkdirp(fs.dirname(dest)))
          check_target(fs.writefile(dest, check_target(fs.readfile(src))))
          return true
        end)
    end

    local function add_templated_target (dest, src, env)
      -- TODO: This is a hack and a half. Excludes should be handled in a
      -- clearer way. In fact, fs.loadfile(make.lua) should probably not be used
      -- directly as config argument to template, but some subset/superset of it
      -- that is passed down explicitly
      if gen.ivals(opts.config.excludes or {}):co():includes(src) then
        return add_copied_target(dest, src, env)
      end
      make:target(
        vec(dest),
        vec(src, opts.config_file),
        function (_, _, check_target)
          check_target(fs.mkdirp(fs.dirname(dest)))
          local t = check_target(tpl.compilefile(src, { env = env }))
          check_target(fs.writefile(dest, check_target(t:render())))
          check_target(t:write_deps(dest, dest .. ".d"))
          return true
        end)
    end

    local function add_templated_target_base64 (dest, data, env, extra_srcs)
      extra_srcs = extra_srcs or vec()
      make:target(
        vec(dest),
        vec(opts.config_file):extend(extra_srcs),
        function (_, _, check_target)
          check_target(fs.mkdirp(fs.dirname(dest)))
          local t = check_target(tpl.compile(basexx.from_base64(data), { env = env }))
          check_target(fs.writefile(dest, check_target(t:render())))
          check_target(t:write_deps(dest, dest .. ".d", { opts.config_file }))
          return true
        end)
    end

    local function get_lua_version ()
      return (_VERSION:match("(%d+.%d+)"))
    end

    local function get_lua_path (prefix)
      local pfx = prefix and fs.join(prefix, "lua_modules") or "lua_modules"
      return gen.pack(
          "share/lua/%ver/?.lua",
          "share/lua/%ver/?/init.lua",
          "lib/lua/%ver/?.lua",
          "lib/lua/%ver/?/init.lua")
        :map(fun.bindr(str.interp, { ver = get_lua_version() }))
        :map(fun.bindl(fs.join, check_init(fs.cwd()), pfx))
        :concat(";")
    end

    local function get_lua_cpath (prefix)
      local pfx = prefix and fs.join(prefix, "lua_modules") or "lua_modules"
      return gen.pack(
          "lib/lua/%ver/?.so",
          "lib/lua/%ver/loadall.so")
        :map(fun.bindr(str.interp, { ver = get_lua_version() }))
        :map(fun.bindl(fs.join, check_init(fs.cwd()), pfx))
        :concat(";")
    end

    local function get_files (dir)
      if not check_init(fs.exists(dir)) then
        return vec()
      end
      return fs.files(dir, { recurse = true })
        :map(check_init)
        :map(fun.nret(1))
        :vec()
    end

    local base_server_libs = get_files("server/lib")
    local base_server_deps = get_files("server/deps")
    local base_server_test_specs = get_files("server/test/spec")
    local base_server_rockspec = str.interp("%s#(name)-server-%s#(version).rockspec", opts.config.env)
    local base_server_makefile = "Makefile"
    local base_server_lib_makefile = "lib/Makefile"
    local base_server_nginx_cfg = "nginx.conf"
    local base_server_nginx_daemon_cfg = "nginx-daemon.conf"
    local base_server_init_test_lua = "init-test.lua"
    local base_server_init_worker_test_lua = "init-worker-test.lua"
    local base_server_luarocks_cfg = "luarocks.lua"
    local base_server_lua_modules = "lua_modules"
    local base_server_lua_modules_ok = "lua_modules.ok"
    local base_server_run_sh = "run.sh"

    local base_client_static = get_files("client/static")

    local base_env = {
      profile = opts.profile,
      skip_coverage = opts.skip_coverage,
      var = function (n)
        assert(compat.istype.string(n))
        return opts.config.env.variable_prefix .. "_" .. n
      end
    }

    local server_env = {
      environment = "main",
      component = "server",
      background = opts.background,
      libs = base_server_libs,
      dist_dir = check_init(fs.absolute(dist_dir())),
      openresty_dir = check_init(fs.absolute(opts.openresty_dir)),
      lua_modules = check_init(fs.absolute(dist_dir(base_server_lua_modules))),
      luarocks_cfg = check_init(fs.absolute(server_dir(base_server_luarocks_cfg))),
    }

    local server_daemon_env = {
      background = true
    }

    local test_server_env = {
      environment = "test",
      component = "server",
      background = opts.background,
      libs = base_server_libs,
      dist_dir = check_init(fs.absolute(test_dist_dir())),
      openresty_dir = check_init(fs.absolute(opts.openresty_dir)),
      luarocks_cfg = check_init(fs.absolute(test_server_dir(base_server_luarocks_cfg))),
      luacov_config = check_init(fs.absolute(test_server_dir("build", "default", "test", "luacov.lua"))),
      lua = env.interpreter()[1],
      lua_path = get_lua_path(test_dist_dir()),
      lua_cpath = get_lua_cpath(test_dist_dir()),
      lua_modules = check_init(fs.absolute(test_dist_dir(base_server_lua_modules))),
    }

    local test_server_daemon_env = {
      background = true
    }

    local client_env = {
      environment = "main",
      component = "client",
    }

    local test_client_env = {
      environment = "test",
      component = "client",
    }

    inherit.pushindex(server_env, _G)
    inherit.pushindex(server_env, base_env)
    inherit.pushindex(server_env, opts.config.env)
    inherit.pushindex(server_daemon_env, server_env)

    inherit.pushindex(test_server_env, _G)
    inherit.pushindex(test_server_env, base_env)
    inherit.pushindex(test_server_env, opts.config.env)
    inherit.pushindex(test_server_daemon_env, test_server_env)

    inherit.pushindex(client_env, _G)
    inherit.pushindex(client_env, base_env)
    inherit.pushindex(client_env, opts.config.env)

    inherit.pushindex(test_client_env, _G)
    inherit.pushindex(test_client_env, base_env)
    inherit.pushindex(test_client_env, opts.config.env)

    opts.config.env.variable_prefix =
      opts.config.env.variable_prefix or
      string.upper((opts.config.env.name:gsub("%W+", "_")))

    add_templated_target_base64(server_dir(base_server_run_sh),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/run.sh")))) %>, server_env) -- luacheck: ignore

    add_templated_target_base64(server_dir(base_server_nginx_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/nginx.conf")))) %>, server_env, -- luacheck: ignore
      vec(server_dir(base_server_lua_modules_ok)))

    add_templated_target_base64(server_dir(base_server_nginx_daemon_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/nginx.conf")))) %>, server_daemon_env, -- luacheck: ignore
      vec(server_dir(base_server_lua_modules_ok)))

    add_templated_target_base64(server_dir(base_server_rockspec),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/template.rockspec")))) %>, server_env) -- luacheck: ignore

    add_templated_target_base64(server_dir(base_server_luarocks_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/luarocks.lua")))) %>, server_env) -- luacheck: ignore

    add_templated_target_base64(server_dir(base_server_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/luarocks.mk")))) %>, server_env) -- luacheck: ignore

    add_templated_target_base64(server_dir(base_server_lib_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/lib.mk")))) %>, server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_run_sh),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/run.sh")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_nginx_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/nginx.conf")))) %>, test_server_env, -- luacheck: ignore
      vec(test_server_dir(base_server_lua_modules_ok),
          test_server_dir(base_server_init_test_lua),
          test_server_dir(base_server_init_worker_test_lua)))

    add_templated_target_base64(test_server_dir(base_server_nginx_daemon_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/nginx.conf")))) %>, test_server_daemon_env, -- luacheck: ignore
      vec(test_server_dir(base_server_lua_modules_ok),
          test_server_dir(base_server_init_test_lua),
          test_server_dir(base_server_init_worker_test_lua)))

    add_templated_target_base64(test_server_dir(base_server_init_test_lua),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/init-test.lua")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_init_worker_test_lua),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/init-worker-test.lua")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_rockspec),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/template.rockspec")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_luarocks_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/luarocks.lua")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/luarocks.mk")))) %>, test_server_env) -- luacheck: ignore

    add_templated_target_base64(test_server_dir(base_server_lib_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/web/lib.mk")))) %>, test_server_env) -- luacheck: ignore

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
      vec(test_dist_dir(base_server_init_test_lua), test_dist_dir(base_server_init_worker_test_lua)))

    add_copied_target(
      test_dist_dir(base_server_nginx_daemon_cfg),
      test_server_dir(base_server_nginx_daemon_cfg))

    gen.pack("profile", "skip_coverage")
      :each(function (flag)
        local fp = work_dir(flag .. ".flag")
        check_init(fs.mkdirp(fs.dirname(fp)))
        local strval = tostring(opts[flag])
        if not check_init(fs.exists(fp)) then
          check_init(fs.writefile(fp, strval))
          return
        end
        local val = check_init(fs.readfile(fp))
        if val ~= strval then
          check_init(fs.writefile(fp, strval))
        end
      end)

    make:add_deps(
      vec(base_server_init_test_lua, base_server_init_worker_test_lua):map(test_server_dir),
      vec("profile.flag", "skip_coverage.flag"):map(work_dir))

    base_server_libs:each(function (fp)
      add_templated_target(server_dir_stripped(fp), fp, server_env)
    end)

    base_server_libs:each(function (fp)
      add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
    end)

    base_server_deps:each(function (fp)
      add_templated_target(server_dir_stripped(fp), fp, server_env)
    end)

    base_server_deps:each(function (fp)
      add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
    end)

    base_server_test_specs:each(function (fp)
      add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
    end)

    base_client_static:each(function (fp)
      add_templated_target(client_dir(fp), fp, client_env)
      add_copied_target(dist_dir_client(fp), client_dir(fp))
    end)

    base_client_static:each(function (fp)
      add_templated_target(test_client_dir(fp), fp, test_client_env)
      add_copied_target(test_dist_dir_client(fp), test_client_dir(fp))
    end)

    make:target(
      vec(server_dir(base_server_lua_modules_ok)),
      vec(server_dir(base_server_luarocks_cfg))
        :extend(vec():extend(base_server_libs, base_server_deps):map(server_dir_stripped)),
      function (_, _, check_target)
        local config_file = check_target(fs.absolute(opts.config_file))
        local config = {
          type = "lib",
          env = {
            name = opts.config.env.name .. "-server",
            version = opts.config.env.version,
            dependencies = opts.config.env.server.dependencies,
          }
        }
        inherit.pushindex(config, opts.config.env)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(server_dir()))
        local project = require("santoku.make.project")
        local ret = tup(err.pwrap(function (chk)
          chk(chk(project.init({
            config_file = config_file,
            luarocks_config = chk(fs.absolute(base_server_luarocks_cfg)),
            config = config,
            single = opts.single,
            profile = opts.profile,
            skip_coverage = opts.skip_coverage,
            skip_tests = true,
          })):install())
        end))
        check_target(fs.cd(cwd))
        check_target(ret())
        local post_make = tbl.get(server_env, "server", "hooks", "post_make") or compat.const(true)
        check_target(post_make(server_env))
        check_target(fs.touch(server_dir(base_server_lua_modules_ok)))
        return true
      end)

    make:target(
      vec(test_server_dir(base_server_lua_modules_ok)),
      vec(test_server_dir(base_server_luarocks_cfg))
        :extend(vec():extend(base_server_libs, base_server_deps):map(test_server_dir_stripped)),
      function (_, _, check_target)
        local config_file = check_target(fs.absolute(opts.config_file))
        local config = {
          type = "lib",
          env = {
            name = opts.config.env.name .. "-server",
            version = opts.config.env.version,
            dependencies = vec()
              :append(compat.unpack(opts.config.env.server.dependencies or {}))
              :append(compat.unpack(tbl.get(opts.config.env.server, "test", "dependencies") or {}))
          }
        }
        inherit.pushindex(config, opts.config.env)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(test_server_dir()))
        local project = require("santoku.make.project")
        local ret = tup(err.pwrap(function (chk)
          chk(chk(project.init({
            config_file = config_file,
            luarocks_config = chk(fs.absolute(base_server_luarocks_cfg)),
            config = config,
            single = opts.single,
            profile = opts.profile,
            skip_coverage = opts.skip_coverage,
            skip_tests = true,
            lua = test_server_env.lua,
            lua_path = test_server_env.lua_path,
            lua_cpath = test_server_env.lua_cpath,
          })):install())
        end))
        check_target(fs.cd(cwd))
        check_target(ret())
        local post_make = tbl.get(test_server_env, "server", "hooks", "post_make") or compat.const(true)
        check_target(post_make(test_server_env))
        check_target(fs.touch(test_server_dir(base_server_lua_modules_ok)))
        return true
      end)

    make:target(
      vec("build"),
      vec(dist_dir(base_server_run_sh),
          dist_dir(base_server_nginx_cfg),
          dist_dir(base_server_nginx_daemon_cfg),
          server_dir(base_server_lua_modules_ok))
        :extend(vec():extend(base_client_static):map(dist_dir_client)),
      true)

    make:target(
      vec("test-build"),
      vec(test_dist_dir(base_server_run_sh),
          test_dist_dir(base_server_nginx_cfg),
          test_dist_dir(base_server_nginx_daemon_cfg),
          test_server_dir(base_server_lua_modules_ok))
        :extend(vec():extend(base_client_static):map(test_dist_dir_client)),
      true)

    make:target(
      vec("start"),
      vec("build"),
      function (_, _, check_target, background)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(dist_dir()))
        local ret = tup(sys.execute(
          { env = { [base_env.var("BACKGROUND")] = (background or opts.background) and "1" or "0" } },
          "sh", "run.sh"))
        check_target(fs.cd(cwd))
        check_target(ret())
        return true
      end)

    make:target(
      vec("test-start"),
      vec("test-build"),
      function (_, _, check_target, background)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(test_dist_dir()))
        local ret = tup(sys.execute(
          { env = { [base_env.var("BACKGROUND")] = (background or opts.background) and "1" or "0" } },
          "sh", "run.sh"))
        check_target(fs.cd(cwd))
        check_target(ret())
        return true
      end)

    make:target(
      vec("test"),
      vec():extend(base_server_test_specs):map(test_server_dir_stripped),
      function (_, _, check_target, iterating)
        check_target(make:make({ "stop", "test-stop" }, check_target))
        check_target(make:make({ "test-start" }, check_target, true))
        -- local cwd = check_target(fs.cwd())
        -- check_target(fs.cd(test_server_dir()))
        -- local ok, e, cd = sys.execute("sh", "test-run.sh")
        local config_file = check_target(fs.absolute(opts.config_file))
        local config = {
          type = "lib",
          env = {
            name = opts.config.env.name .. "-server",
            version = opts.config.env.version,
            dependencies = opts.config.env.server.dependencies
          }
        }
        inherit.pushindex(config, opts.config.env)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(test_server_dir()))
        local project = require("santoku.make.project")
        local lib = nil
        local ret = tup(err.pwrap(function (chk)
          lib = chk(project.init({
            config_file = config_file,
            luarocks_config = chk(fs.absolute(base_server_luarocks_cfg)),
            config = config,
            single = opts.single,
            profile = opts.profile,
            skip_coverage = opts.skip_coverage,
            lua = test_server_env.lua,
            lua_path = test_server_env.lua_path,
            lua_cpath = test_server_env.lua_cpath,
          }))
          chk(lib:test({ skip_check = true }))
        end))
        check_target(fs.cd(cwd))
        if not iterating then
          check_target(make:make({ "test-stop" }, check_target))
        end
        check_target(ret())
        check_target(fs.cd(test_server_dir()))
        local ret = tup(lib:check())
        check_target(fs.cd(cwd))
        check_target(ret())
        return true
      end)

    make:target(
      vec("iterate"),
      vec(),
      function (_, _, check_target)
        local ok = sys.execute("sh", "-c", "type inotifywait >/dev/null 2>/dev/null")
        if not ok then
          check_target(false, ERR.NO_INOTIFY)
        end
        while true do
          local ret = tup(make:make(vec("test"), check_target, true))
          if not ret() then
            print(tup.sel(2, ret()))
          end
          while true do
            local watched_files = fs.files(".")
              :map(check_target)
              :map(fun.nret(1))
              :vec()
              :append("client", "server")
              :filter(fun.compose(check_target, fs.exists))
            local ev = check_target(sys.sh("inotifywait", "-qr", watched_files:unpack()))
              :map(check_target)
              :map(str.split)
              :map(fun.bindr(tbl.get, 2))
              :co():head()
            if not vec("OPEN", "ACCESS"):find(fun.bindl(str.startswith, ev)) then
              break
            end
          end
        end
      end)

    make:target(
      vec("stop"),
      vec(),
      function (_, _, check_target)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        -- TODO: do something better than assuming an error means dist or
        -- server.pid wasn't found and ignoring the kill error (some other error
        -- could have happened that should cause an overall)
        local ok = fs.cd(dist_dir())
        if not ok then
          return true
        end
        local ok, pid = fs.readfile("server.pid")
        if ok then
          sys.execute("kill", pid:match("%d+"))
        end
        check_target(fs.cd(cwd))
        return true
      end)

    make:target(
      vec("test-stop"),
      vec(),
      function (_, _, check_target)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        -- TODO: do something better than assuming an error means dist or
        -- server.pid wasn't found and ignoring the kill error (some other error
        -- could have happened that should cause an overall)
        local ok = fs.cd(test_dist_dir())
        if not ok then
          return true
        end
        local ok, pid = fs.readfile("server.pid")
        if ok then
          sys.execute("kill", pid:match("%d+"))
        end
        check_target(fs.cd(cwd))
        return true
      end)

    local N = { ERR = ERR }

    N.config = opts.config

    N.test = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "test" }, opts), check_target))
      end)
    end

    N.iterate = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "iterate" }, opts), check_target))
      end)
    end

    N.build = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ opts.test and "test-build" or "build" }, opts), check_target))
      end)
    end

    N.start = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ opts.test and "test-start" or "start" }, opts), check_target))
      end)
    end

    N.stop = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "stop", "test-stop" }, opts), check_target))
      end)
    end

    return N

  end)
end

return M
