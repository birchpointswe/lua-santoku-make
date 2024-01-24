<%
  str = require("santoku.string")
  fs = require("santoku.fs")
  basexx = require("basexx")
%>

local env = require("santoku.env")
local tup = require("santoku.tuple")
local err = require("santoku.err")
local compat = require("santoku.compat")
local fs = require("santoku.fs")
local fun = require("santoku.fun")
local gen = require("santoku.gen")
local inherit = require("santoku.inherit")
local str = require("santoku.string")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local tpl = require("santoku.template")
local vec = require("santoku.vector")
local bundle = require("santoku.bundle")

local basexx = require("basexx")

local M = {}

M.create = function ()
  return false, "create lib unimplemented"
end

M.init = function (opts)

  local make = require("santoku.make")(opts)

  assert(compat.istype.table(opts))
  assert(compat.istype.table(opts.config))

  return err.pwrap(function (check_init)

    opts.wasm = opts.wasm or false
    opts.sanitize = opts.sanitize or false
    opts.profile = opts.profile or false
    opts.single = opts.single or false
    opts.lua = opts.lua or false
    opts.skip_coverage = opts.profile or opts.skip_coverage or false
    opts.iterate = opts.iterate or false

    local function work_dir (...)
      if opts.wasm then
        return fs.join(opts.dir, opts.env .. "-wasm", ...)
      else
        return fs.join(opts.dir, opts.env, ...)
      end
    end

    local function build_dir (...)
      return work_dir("build", ...)
    end

    local function test_dir (...)
      return work_dir("test", ...)
    end

    -- TODO: use fs.copy
    local function add_copied_target (dest, src)
      make:target(
        vec(dest),
        vec(src),
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
      local action = tpl.get_action(src, opts.config)
      if action == "copy" then
        return add_copied_target(dest, src, env)
      elseif action == "template" then
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
    end

    local function add_templated_target_base64 (dest, data, env)
      make:target(
        vec(dest),
        vec(opts.config_file),
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
        :filter(function (fp)
          return tpl.get_action(fp, opts.config) ~= "ignore"
        end)
        :vec()
    end

    local base_bins = get_files("bin")
    local base_libs = get_files("lib")
    local base_deps = get_files("deps")

    local base_rockspec = str.interp("%s#(name)-%s#(version).rockspec", opts.config.env)
    local base_makefile = "Makefile"
    local base_lib_makefile = "lib/Makefile"
    local base_bin_makefile = "bin/Makefile"
    local base_luarocks_cfg = "luarocks.lua"
    local base_lua_modules = "lua_modules"
    local base_lua_modules_ok = "lua_modules.ok"
    local base_luacheck_cfg = "luacheck.lua"
    local base_luacov_cfg = "luacov.lua"
    local base_run_sh = "run.sh"
    local base_check_sh = "check.sh"
    local base_luacov_stats_file = "luacov.stats.out"
    local base_luacov_report_file = "luacov.report.out"

    local base_test_specs = get_files("test/spec")

    if opts.single then
      base_test_specs:filter(function (fp)
        return fp == opts.single
      end)
    end

    local base_test_deps = get_files("test/deps")
    local base_test_res = get_files("test/res")

    local test_all_base = vec()
      :extend(base_bins, base_libs, base_deps, base_test_deps, base_test_res)

    if opts.wasm then
      test_all_base:extend(gen.ivals(base_test_specs):map(fs.stripextension):vec())
    else
      test_all_base:extend(base_test_specs)
    end

    local test_all = vec()
      :extend(test_all_base)
      :append(
        base_rockspec,
        base_makefile,
        base_luarocks_cfg,
        base_luacheck_cfg,
        base_luacov_cfg,
        base_run_sh,
        base_check_sh)
      :map(test_dir)

    local test_srcs = vec()
      :extend(base_bins, base_libs, base_deps, base_test_deps)
      :map(test_dir)

    local test_cfgs = vec()
      :append(base_rockspec, base_makefile)
      :append(base_luarocks_cfg, base_luacheck_cfg, base_luacov_cfg, base_run_sh, base_check_sh)
      :map(test_dir)

    local build_all = vec()
      :extend(base_bins, base_libs, base_deps)
      :append(
        base_rockspec,
        base_makefile)
      :map(build_dir)

    if base_libs.n > 0 then
      test_all:append(test_dir(base_lib_makefile))
      test_cfgs:append(test_dir(base_lib_makefile))
      build_all:append(build_dir(base_lib_makefile))
    end

    if base_bins.n > 0 then
      test_all:append(test_dir(base_bin_makefile))
      test_cfgs:append(test_dir(base_bin_makefile))
      build_all:append(build_dir(base_bin_makefile))
    end

    test_all:append(test_dir(base_lua_modules_ok))

    local base_env = {
      wasm = opts.wasm,
      sanitize = opts.sanitize,
      profile = opts.profile,
      skip_coverage = opts.skip_coverage,
      single = opts.single,
      bins = base_bins,
      libs = base_libs,
      root_dir = check_init(fs.cwd()),
      var = function (n)
        assert(compat.istype.string(n))
        return opts.config.env.variable_prefix .. "_" .. n
      end
    }

    local test_env = {
      environment = "test",
      lua = opts.lua or env.interpreter()[1],
      lua_path = opts.lua_path or get_lua_path(test_dir()),
      lua_cpath = opts.lua_cpath or get_lua_cpath(test_dir()),
      lua_modules = check_init(fs.absolute(test_dir(base_lua_modules))),
      luarocks_config = check_init(fs.absolute(test_dir(base_luarocks_cfg))),
      luacov_stats_file = check_init(fs.absolute(test_dir(base_luacov_stats_file))),
      luacov_report_file = check_init(fs.absolute(test_dir(base_luacov_report_file))),
    }

    if opts.lua_path_extra then
      test_env.lua_path = test_env.lua_path .. ";" .. opts.lua_path_extra
    end

    if opts.lua_cpath_extra then
      test_env.lua_cpath = test_env.lua_cpath .. ";" .. opts.lua_cpath_extra
    end

    local build_env = {
      environment = "build"
    }

    inherit.pushindex(test_env, _G)
    inherit.pushindex(test_env, base_env)
    inherit.pushindex(test_env, opts.config.env)

    inherit.pushindex(build_env, _G)
    inherit.pushindex(build_env, base_env)
    inherit.pushindex(build_env, opts.config.env)

    if opts.wasm then

      local test_client_lua_dir = check_init(fs.absolute(test_dir("lua-5.1.5")))
      local test_client_lua_ok = test_client_lua_dir .. ".ok"

      base_env.client_lua_dir = test_client_lua_dir

      test_all:insert(1, test_client_lua_ok)

      make:target(
        vec(test_client_lua_ok),
        vec(),
        function (_, _, check_target)
          check_target(fs.mkdirp(test_dir()))
          local cwd = check_target(fs.cwd())
          check_target(fs.cd(test_dir()))
          local ok, e, cd = err.pwrap(function (chk)
            if not chk(fs.exists("lua-5.1.5.tar.gz")) then
              chk(sys.execute("wget", "https://www.lua.org/ftp/lua-5.1.5.tar.gz"))
            end
            if chk(fs.exists("lua-5.1.5")) then
              chk(sys.execute("rm", "-rf", "lua-5.1.5")) -- TODO: use fs.rm(x, { recurse = true })
            end
            chk(sys.execute("tar", "xf", "lua-5.1.5.tar.gz"))
            chk(fs.cd("lua-5.1.5"))
            chk(sys.execute("emmake", "sh", "-c",
              "make generic CC=\"$CC\" LD=\"$LD\" AR=\"$AR rcu\"" ..
              "  RANLIB=\"$RANLIB\" MYLDFLAGS=\"-sSINGLE_FILE -sEXIT_RUNTIME=1 -lnodefs.js -lnoderawfs.js\""))
            chk(sys.execute("make", "local"))
            chk(fs.cd("bin"))
            chk(sys.execute("mv", "lua", "lua.js"))
            chk(sys.execute("mv", "luac", "luac.js"))
            chk(fs.writefile("lua", "#!/bin/sh\nnode \"$(dirname $0)/lua.js\" \"$@\"\n"))
            chk(fs.writefile("luac", "#!/bin/sh\nnode \"$(dirname $0)/luac.js\" \"$@\"\n"))
            chk(sys.execute("chmod", "+x", "lua"))
            chk(sys.execute("chmod", "+x", "luac"))
          end)
          check_target(fs.cd(cwd))
          check_target(ok, e, cd)
          check_target(fs.touch(test_client_lua_ok))
          return true
        end)

    end

    opts.config.env.variable_prefix =
      opts.config.env.variable_prefix or
      string.upper((opts.config.env.name:gsub("%W+", "_")))

    gen.pack(base_libs, base_bins, base_deps)
      :map(gen.ivals):flatten():each(function (fp)
        add_templated_target(build_dir(fp), fp, build_env)
      end)

    gen.pack(base_libs, base_bins, base_deps, base_test_deps)
      :map(gen.ivals):flatten():each(function (fp)
        add_templated_target(test_dir(fp), fp, test_env)
      end)

    if not opts.wasm then

      base_test_specs:each(function (fp)
        add_templated_target(test_dir(fp), fp, test_env)
      end)

    else

      base_test_specs:each(function (fp)
        add_templated_target(test_dir("bundler-pre", fp), fp, test_env)
      end)

      base_test_specs:each(function (fp)
        make:target(
          vec(test_dir("bundler-post", fs.stripextension(fp))),
          vec(test_dir("bundler-pre", fp)):extend(test_cfgs):append(test_dir(base_lua_modules_ok)),
          function (_, _, check_target)
            check_target(bundle.bundle(
              test_dir("bundler-pre", fp),
              test_dir("bundler-post", fs.dirname(fp)), {
                cc = "emcc",
                mods = { "luacov", "luacov.hook", "luacov.tick", opts.profile and "santoku.profile" or nil },
                ignores = { "debug" },
                env = {
                  { base_env.var("WASM"), "1" },
                  { base_env.var("PROFILE"), opts.profile and "1" or "" },
                  { base_env.var("SANITIZE"), opts.sanitize and "1" or "" },
                  { "LUACOV_CONFIG", check_target(fs.absolute(test_dir(base_luacov_cfg))) }
                },
                path = get_lua_path(test_dir()),
                cpath = get_lua_cpath(test_dir()),
                flags = {
                  opts.sanitize and "-fsanitize=address" or "",
                  "-sASSERTIONS", "-sSINGLE_FILE", "-sALLOW_MEMORY_GROWTH",
                  "-I" .. fs.join(base_env.client_lua_dir, "include"),
                  "-L" .. fs.join(base_env.client_lua_dir, "lib"),
                  "-lnodefs.js", "-lnoderawfs.js", "-llua", "-lm",
                  tbl.get(test_env, "test", "cflags") or "",
                  tbl.get(test_env, "test", "ldflags") or "",
                  tbl.get(test_env, "test", "wasm", "cflags") or "",
                  tbl.get(test_env, "test", "wasm", "ldflags") or "",
                  tbl.get(test_env, "test", "sanitize", "wasm", "cflags") or "",
                  tbl.get(test_env, "test", "sanitize", "wasm", "ldflags") or "",
                }
              }))
            return true
          end)
        end)

      base_test_specs:each(function (fp)
        add_copied_target(test_dir(fs.stripextension(fp)), test_dir("bundler-post", fs.stripextension(fp)), test_env)
      end)

    end

    gen.pack(base_test_res):map(gen.ivals):flatten():each(function (fp)
      add_copied_target(test_dir(fp), fp, test_env)
    end)

    add_templated_target_base64(build_dir(base_rockspec),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/template.rockspec")))) %>, build_env) -- luacheck: ignore

    add_templated_target_base64(build_dir(base_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/luarocks.mk")))) %>, build_env) -- luacheck: ignore

    add_templated_target_base64(build_dir(base_lib_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/lib.mk")))) %>, build_env) -- luacheck: ignore

    add_templated_target_base64(build_dir(base_bin_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/bin.mk")))) %>, build_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_rockspec),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/template.rockspec")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/luarocks.mk")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_lib_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/lib.mk")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_bin_makefile),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/bin.mk")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_luarocks_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/luarocks.lua")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_luacheck_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/luacheck.lua")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_luacov_cfg),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/luacov.lua")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_run_sh),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/test-run.sh")))) %>, test_env) -- luacheck: ignore

    add_templated_target_base64(test_dir(base_check_sh),
      <% return str.quote(basexx.to_base64(check(fs.readfile("res/lib/test-check.sh")))) %>, test_env) -- luacheck: ignore

    gen.pack("sanitize", "profile", "single", "skip_coverage", "lua", "lua_path_extra", "lua_cpath_extra")
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
      vec(base_run_sh, base_check_sh):map(test_dir),
      vec("skip_coverage.flag", "single.flag", "profile.flag", "sanitize.flag",
          "lua.flag", "lua_path_extra.flag", "lua_cpath_extra.flag")
        :map(work_dir))

    make:add_deps(
      vec(base_lib_makefile):extend(base_libs):map(test_dir),
      vec("sanitize.flag"):map(work_dir))

    make:target(
      vec(base_lua_modules_ok):map(test_dir),
      vec()
        :extend(test_srcs, test_cfgs)
        :append(test_dir(base_luarocks_cfg))
        :append(work_dir("sanitize.flag")),
      function (_, _, check_target)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(test_dir()))
        local ok, e, cd = sys.execute(
          { env = { MAKEFLAGS = "-s", LUAROCKS_CONFIG = opts.luarocks_config or base_luarocks_cfg } },
          "luarocks", "make", fs.basename(base_rockspec),
          gen.chain(
            gen.pairs(tbl.get(test_env, "luarocks", "env_vars") or {}),
            gen.pairs(tbl.get(test_env, "test", "luarocks", "env_vars") or {}),
            gen.pairs(opts.wasm and tbl.get(test_env, "test", "wasm", "luarocks", "env_vars") or {}),
            gen.pairs(not opts.wasm and tbl.get(test_env, "test", "native", "luarocks", "env_vars") or {}))
            :map(function (k, v)
              return str.interp("%1=%2", { k, v })
            end):unpack())
        check_target(fs.cd(cwd))
        check_target(ok, e, cd)
        local post_make = tbl.get(test_env, "test", "hooks", "post_make") or compat.const(true)
        check_target(post_make(test_env))
        check_target(fs.touch(test_dir(base_lua_modules_ok)))
        return true
      end)

    make:target(vec("build-deps"), build_all, true)
    make:target(vec("test-deps"), test_all, true)

    local install_release_deps = opts.skip_tests
      and vec("build-deps")
      or vec("test", "check", "build-deps")

    -- NOTE: install not supported in wasm mode
    if not opts.wasm then

      make:target(vec("install"), install_release_deps, function (_, _, check_target)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(build_dir()))
        local ok, e, cd = sys.execute(
          { env = { MAKEFLAGS = "-s", LUAROCKS_CONFIG = opts.luarocks_config } },
          "luarocks", "make", base_rockspec,
          gen.chain(
            gen.pairs(tbl.get(build_env, "luarocks", "env_vars") or {}),
            gen.pairs(tbl.get(build_env, "build", "luarocks", "env_vars") or {}),
            gen.pairs(opts.wasm and tbl.get(build_env, "build", "wasm", "luarocks", "env_vars") or {}),
            gen.pairs(not opts.wasm and tbl.get(build_env, "build", "native", "luarocks", "env_vars") or {}))
            :map(function (k, v)
              return str.interp("%1=%2", { k, v })
            end):unpack())
        check_target(fs.cd(cwd))
        check_target(ok, e, cd)
        return true
      end)

    end

    -- NOTE: release not supported in wasm mode
    if not opts.wasm and opts.config.env.public then

      local release_tarball_dir = str.interp("%s#(name)-%s#(version)", opts.config.env)
      local release_tarball = release_tarball_dir .. ".tar.gz"
      local release_tarball_contents = vec()
        :extend(base_bins, base_libs, base_deps)
        :append(base_makefile)

      if base_libs.n > 0 then
        release_tarball_contents:append(base_lib_makefile)
      end

      if base_bins.n > 0 then
        release_tarball_contents:append(base_bin_makefile)
      end

      make:target(vec("release"), install_release_deps, function (_, _, check_target)
        local cwd = check_target(fs.cwd())
        -- TODO: simplify with fs.pushd + callback
        check_target(fs.cd(build_dir()))
        local ok, e, cd = err.pwrap(function (chk)
          local ok, err = sys.execute("git", "diff", "--quiet")
          if not ok then
            chk(false, "Commit your changes first", err)
          end
          local api_key = chk:exists(opts.luarocks_api_key or os.getenv("LUAROCKS_API_KEY"),
            "Missing luarocks API key")
          if chk(fs.exists(release_tarball)) then
            chk(fs.rm(release_tarball))
          end
          chk(sys.execute("git", "tag", opts.config.env.version))
          chk(sys.execute("git", "push", "--tags"))
          chk(sys.execute("git", "push"))
          chk(sys.execute("tar",
            "--dereference",
            "--transform", str.interp("s#^#%s#(1)/#", { release_tarball_dir }),
            "-czvf", release_tarball, release_tarball_contents:unpack()))
          chk(sys.execute("gh", "release", "create", "--generate-notes",
            opts.config.env.version, release_tarball, base_rockspec))
          chk(sys.execute("luarocks", "upload", "--skip-pack", "--api-key", api_key, base_rockspec))
        end)
        check_target(fs.cd(cwd))
        check_target(ok, e, cd)
        return true
      end)

    end

    make:target(vec("test"), vec("test-deps"), function (_, _, check_target)
      local cwd = check_target(fs.cwd())
      -- TODO: simplify with fs.pushd + callback
      check_target(fs.cd(test_dir()))
      local ok, e, cd = sys.execute("sh", "run.sh")
      check_target(fs.cd(cwd))
      check_target(ok, e, cd)
      return true
    end)

    make:target(vec("check"), vec("test-deps"), function (_, _, check_target)
      local cwd = check_target(fs.cwd())
      -- TODO: simplify with fs.pushd + callback
      check_target(fs.cd(test_dir()))
      local ok, e, cd = sys.execute("sh", "check.sh")
      check_target(fs.cd(cwd))
      check_target(ok, e, cd)
      return true
    end)

    make:target(vec("iterate"), vec(), function (_, _, check_target)
      local ok = sys.execute("sh", "-c", "type inotifywait >/dev/null 2>/dev/null")
      if not ok then
        check_target(false, "inotifywait not found")
      end
      while true do
        local ret = tup(make:make(vec("test", "check"), check_target))
        if not ret() then
          print(tup.sel(2, ret()))
        end
        while true do
          local watched_files = fs.files(".")
            :map(check_target)
            :map(fun.nret(1))
            :vec()
            :append("lib", "bin", "test", "res")
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

    gen.keys(make.targets):each(function (fp)
      local dfile = fp .. ".d"
      if check_init(fs.exists(dfile)) then
        check_init(fs.lines(dfile)):each(function (line)
          local chunks = str.split(line, ":")
          local target = chunks[1]
          local deps = gen.ivals(chunks):co():slice(2):map(str.split):flatten():filter(function (fp)
            return not str.isempty(fp)
          end):vec()
          make:add_deps({ target }, deps)
        end)
      end
    end)

    local N = {}

    N.config = opts.config

    N.test = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "test" }, opts), check_target))
        if not opts.skip_check then
          check_target(make:make(tbl.assign({ "check" }, opts), check_target))
        end
      end)
    end

    N.check = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "check" }, opts), check_target))
      end)
    end

    N.iterate = function (_, opts)
      opts = opts or {}
      return err.pwrap(function (check_target)
        check_target(make:make(tbl.assign({ "iterate" }, opts), check_target))
      end)
    end

    -- NOTE: install and release not supported in wasm mode
    if not opts.wasm then

      N.install = function (_, opts)
        opts = opts or {}
        return err.pwrap(function (check_target)
          check_target(make:make(tbl.assign({ "install" }, opts), check_target))
        end)
      end

      N.release = function (_, opts)
        opts = opts or {}
        return err.pwrap(function (check_target)
          check_target(make:make(tbl.assign({ "release" }, opts), check_target))
        end)
      end

    end

    return N

  end)
end

return M
