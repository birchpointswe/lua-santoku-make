<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
%>

local bundle = require("santoku.bundle")
local env = require("santoku.env")
local fs = require("santoku.fs")
local fun = require("santoku.functional")
local make = require("santoku.make")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local tmpl = require("santoku.template")
local varg = require("santoku.varg")
local vdt = require("santoku.validate")
local err = require("santoku.error")

local arr = require("santoku.array")
local amap = arr.map
local spread = arr.spread
local aincludes = arr.includes
local extend = arr.extend
local push = arr.push
local concat = arr.concat

local iter = require("santoku.iter")
local ivals = iter.ivals
local pairs = iter.pairs
local find = iter.find
local chain = iter.chain
local map = iter.map
local collect = iter.collect
local filter = iter.filter
local flatten = iter.flatten

local str = require("santoku.string")
local sinterp = str.interp
local ssplits = str.splits
local supper = str.upper
local sformat = str.format
local smatch = str.match
local gsub = str.gsub
local ssub = str.sub
local from_base64 = str.from_base64

local function create ()
  err.error("create lib not yet implemented")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build
  local targets = submake.targets

  err.assert(vdt.istable(opts))
  err.assert(vdt.istable(opts.config))

  opts.skip_check = opts.skip_check or nil
  opts.skip_coverage = opts.profile or opts.skip_coverage or nil

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

  -- TODO: It would be nice if santoku ivals returned an empty iterator for
  -- nil instead of erroring. It would allow omitting the {} below
  local function get_action (fp)
    local ext = fs.extension(fp)
    local match_fp = fun.bind(smatch, fp)
    if (opts.exts and not aincludes(opts.config.exts or {}, ext)) or
        find(match_fp, ivals(tbl.get(opts.config, "rules", "exclude") or {}))
    then
      return "ignore"
    elseif find(match_fp, ivals(tbl.get(opts.config, "rules", "copy") or {}))
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

  local function add_templated_target_base64 (dest, data, env)
    target({ dest }, { opts.config_file }, function ()
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

  local function get_files (dir, check_tpl)
    local tpl = check_tpl and {} or nil
    if not fs.exists(dir) then
      return {}, tpl
    end
    return collect(filter(function (fp)
      if check_tpl and force_template(fp) then
        push(tpl, fp)
        return false
      end
      return get_action(fp) ~= "ignore"
    end, fs.files(dir, true))), tpl
  end

  local base_bins = get_files("bin")
  local base_libs = get_files("lib")
  local base_res, base_res_templated = get_files("res", true)
  local base_deps = get_files("deps")

  local base_rockspec = sinterp("%s#(name)-%s#(version).rockspec", opts.config.env)
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
  local base_lua_dir = "lua-5.1.5"

  local base_test_specs = opts.single and { opts.single } or get_files("test/spec")

  local base_test_deps = get_files("test/deps")
  local base_test_res, base_test_res_templated = get_files("test/res", true)

  local test_all_base_templated = extend({},
    base_bins, base_libs, base_deps,
    base_test_deps, base_res_templated, base_test_res_templated)

  local test_all_base_copied = extend({},
    base_res, base_test_res)

  if opts.wasm then
    extend(test_all_base_templated, collect(map(fs.stripextension, ivals(base_test_specs))))
  else
    extend(test_all_base_templated, base_test_specs)
  end

  local test_all = amap(extend({},
    amap(extend({},
      test_all_base_templated,
      { base_rockspec, base_makefile,
        base_luarocks_cfg, base_luacheck_cfg, base_luacov_cfg,
        base_run_sh, base_check_sh }), remove_tk),
    test_all_base_copied), test_dir)

  local test_srcs = amap(amap(extend({},
    base_bins, base_libs, base_deps, base_test_deps), test_dir), remove_tk)

  local test_cfgs = amap(amap(push({},
    base_rockspec, base_makefile, base_luarocks_cfg,
    base_luacheck_cfg, base_luacov_cfg, base_run_sh,
    base_check_sh), test_dir), remove_tk)

  local build_all = amap(extend({},
    amap(push(extend({},
      base_bins, base_libs, base_deps, opts.wasm and { base_luarocks_cfg } or {},
      base_res_templated),
      base_rockspec, base_makefile), remove_tk),
    base_res), build_dir)

  if #base_libs > 0 then
    push(test_all, test_dir(base_lib_makefile))
    push(test_cfgs, test_dir(base_lib_makefile))
    push(build_all, build_dir(base_lib_makefile))
  end

  if #base_bins > 0 then
    push(test_all, test_dir(base_bin_makefile))
    push(test_cfgs, test_dir(base_bin_makefile))
    push(build_all, build_dir(base_bin_makefile))
  end

  push(test_all, test_dir(base_lua_modules_ok))

  local base_env = {
    wasm = opts.wasm,
    sanitize = opts.sanitize,
    profile = opts.profile,
    skip_check = opts.skip_check,
    skip_coverage = opts.skip_coverage,
    single = opts.single,
    bins = base_bins,
    libs = base_libs,
    root_dir = fs.cwd(),
    work_dir = opts.dir,
    var = function (n)
      err.assert(vdt.isstring(n))
      return concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local test_env = {
    environment = opts.environment or "test",
    lua = opts.lua or env.interpreter()[1],
    lua_path = opts.lua_path or get_lua_path(test_dir()),
    lua_cpath = opts.lua_cpath or get_lua_cpath(test_dir()),
    lua_modules = test_dir(base_lua_modules),
    luarocks_config = test_dir(base_luarocks_cfg),
    luarocks_cfg = test_dir(base_luarocks_cfg),
    luacov_stats_file = test_dir(base_luacov_stats_file),
    luacov_report_file = test_dir(base_luacov_report_file),
    target = "test-deps",
  }

  if opts.lua_path_extra then
    test_env.lua_path = concat({ test_env.lua_path, ";", opts.lua_path_extra })
  end

  if opts.lua_cpath_extra then
    test_env.lua_cpath = concat({ test_env.lua_cpath, ";", opts.lua_cpath_extra })
  end

  local build_env = {
    environment = opts.environment or "build",
    lua_modules = opts.wasm and build_dir(base_lua_modules) or nil,
    target = "build",
  }

  tbl.merge(test_env, opts.config.env, base_env)
  tbl.merge(build_env, opts.config.env, base_env)

  if opts.wasm then

    for dir, all, env in map(spread, ivals({
      { test_dir, test_all, test_env },
      { build_dir, build_all, build_env }
    })) do
      local client_lua_dir = dir(base_lua_dir)
      local client_lua_ok = client_lua_dir .. ".ok"
      env.client_lua_dir = client_lua_dir
      tbl.insert(all, 1, client_lua_ok)
      target({ client_lua_ok }, {}, function ()
        fs.mkdirp(dir())
        return fs.pushd(dir(), function ()
          if not fs.exists("lua-5.1.5.tar.gz") then
            sys.execute({ "wget", "https://www.lua.org/ftp/lua-5.1.5.tar.gz" })
          end
          if fs.exists("lua-5.1.5") then
            sys.execute({ "rm", "-rf", "lua-5.1.5" }) -- TODO: use fs.rm(x, { recurse = true })
          end
          sys.execute({ "tar", "xf", "lua-5.1.5.tar.gz" })
          fs.cd("lua-5.1.5")
          sys.execute({ "emmake", "sh", "-c", arr.concat({
            "make", "generic",
            "CC=\"$CC\"",
            "LD=\"$LD\"",
            "AR=\"$AR rcu\"",
            "RANLIB=\"$RANLIB\"",
            "CFLAGS=\"-flto -Oz\"",
            "MYLDFLAGS=\"-flto -Oz\""
          }, " ") })
          sys.execute({ "make", "local" })
          fs.cd("bin")
          sys.execute({ "mv", "lua", "lua.js" })
          sys.execute({ "mv", "luac", "luac.js" })
          fs.writefile("lua", "#!/bin/sh\nnode \"$(dirname $0)/lua.js\" \"$@\"\n")
          fs.writefile("luac", "#!/bin/sh\nnode \"$(dirname $0)/luac.js\" \"$@\"\n")
          sys.execute({ "chmod", "+x", "lua" })
          sys.execute({ "chmod", "+x", "luac" })
          fs.touch(client_lua_ok)
        end)
      end)
    end

  end

  opts.config.env.variable_prefix =
    opts.config.env.variable_prefix or
    supper((gsub(opts.config.env.name, "%W+", "_")))

  for fp in flatten(map(ivals, ivals({ base_libs, base_bins, base_deps }))) do
    add_file_target(build_dir(remove_tk(fp)), fp, build_env)
  end

  for fp in flatten(map(ivals, ivals({ base_libs, base_bins, base_deps, base_test_deps }))) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
  end

  if not opts.wasm then

    for fp in ivals(base_test_specs) do
      add_file_target(test_dir(remove_tk(fp)), fp, test_env)
    end

  else

    for fp in ivals(base_test_specs) do
      add_file_target(test_dir("bundler-pre", remove_tk(fp)), fp, test_env)
    end

    for fp in ivals(base_test_specs) do
      target({ test_dir("bundler-post", fs.stripextension(fp)) },
        push(extend({ test_dir("bundler-pre", fp) },
          test_cfgs), test_dir(base_lua_modules_ok)),
        function ()
          bundle(test_dir("bundler-pre", fp), test_dir("bundler-post", fs.dirname(fp)), {
            cc = "emcc",
            mods = extend({},
              opts.skip_coverage and {} or { "luacov", "luacov.hook", "luacov.tick" },
              opts.profile and { "santoku.profile" } or {}),
            ignores = { "debug" },
            env = {
              { base_env.var("WASM"), "1" },
              { base_env.var("PROFILE"), opts.profile and "1" or "" },
              { base_env.var("SANITIZE"), opts.sanitize and "1" or "" },
              { "LUACOV_CONFIG", test_dir(base_luacov_cfg) }
            },
            path = get_lua_path(test_dir()),
            cpath = get_lua_cpath(test_dir()),
            flags = extend({
              opts.sanitize and "-fsanitize=address" or "",
              "-sASSERTIONS", "-sSINGLE_FILE", "-sALLOW_MEMORY_GROWTH",
              "-I" .. fs.join(test_env.client_lua_dir, "include"),
              "-L" .. fs.join(test_env.client_lua_dir, "lib"),
              "-lnodefs.js", "-lnoderawfs.js", "-llua", "-lm",
            },
            tbl.get(test_env, "test", "cflags") or {},
            tbl.get(test_env, "test", "ldflags") or {},
            tbl.get(test_env, "test", "wasm", "cflags") or {},
            tbl.get(test_env, "test", "wasm", "ldflags") or {},
            tbl.get(test_env, "test", "sanitize", "wasm", "cflags") or {},
            tbl.get(test_env, "test", "sanitize", "wasm", "ldflags") or {})
          })
        end)
    end

    for fp in ivals(base_test_specs) do
      add_file_target(test_dir(fs.stripextension(remove_tk(fp))),
        test_dir("bundler-post", fs.stripextension(fp)), test_env)
    end

  end

  for fp in ivals(base_res) do
    add_copied_target(build_dir(fp), fp)
  end

  for fp in ivals(base_res_templated) do
    add_file_target(build_dir(remove_tk(fp)), fp, build_env)
  end

  for fp in ivals(base_res) do
    add_copied_target(test_dir(fp), fp)
  end

  for fp in ivals(base_res_templated) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
  end

  for fp in ivals(base_test_res) do
    add_copied_target(test_dir(fp), fp)
  end

  for fp in ivals(base_test_res_templated) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
  end

  add_templated_target_base64(build_dir(base_rockspec),
    <% return squote(to_base64(readfile("res/lib/template.rockspec"))) %>, build_env) -- luacheck: ignore

  add_templated_target_base64(build_dir(base_makefile),
    <% return squote(to_base64(readfile("res/lib/luarocks.mk"))) %>, build_env) -- luacheck: ignore

  add_templated_target_base64(build_dir(base_lib_makefile),
    <% return squote(to_base64(readfile("res/lib/lib.mk"))) %>, build_env) -- luacheck: ignore

  add_templated_target_base64(build_dir(base_bin_makefile),
    <% return squote(to_base64(readfile("res/lib/bin.mk"))) %>, build_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_rockspec),
    <% return squote(to_base64(readfile("res/lib/template.rockspec"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_makefile),
    <% return squote(to_base64(readfile("res/lib/luarocks.mk"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_lib_makefile),
    <% return squote(to_base64(readfile("res/lib/lib.mk"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_bin_makefile),
    <% return squote(to_base64(readfile("res/lib/bin.mk"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_luarocks_cfg),
    <% return squote(to_base64(readfile("res/lib/luarocks.lua"))) %>, test_env) -- luacheck: ignore

  if opts.wasm then
    add_templated_target_base64(build_dir(base_luarocks_cfg),
      <% return squote(to_base64(readfile("res/lib/luarocks.lua"))) %>, build_env) -- luacheck: ignore
  end

  add_templated_target_base64(test_dir(base_luacheck_cfg),
    <% return squote(to_base64(readfile("res/lib/luacheck.lua"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_luacov_cfg),
    <% return squote(to_base64(readfile("res/lib/luacov.lua"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_run_sh),
    <% return squote(to_base64(readfile("res/lib/test-run.sh"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_check_sh),
    <% return squote(to_base64(readfile("res/lib/test-check.sh"))) %>, test_env) -- luacheck: ignore

  for flag in ivals({
    "sanitize", "profile", "single",
    "skip_coverage", "skip_check", "lua", "lua_path_extra", "lua_cpath_extra"
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
    amap({ base_run_sh, base_check_sh }, test_dir),
    amap({
      "skip_coverage.flag", "skip_check.flag", "single.flag", "profile.flag", "sanitize.flag",
      "lua.flag", "lua_path_extra.flag", "lua_cpath_extra.flag" }, work_dir))

  target(
    amap(amap(extend({ base_run_sh, base_check_sh }, base_libs), test_dir), remove_tk),
    amap({ "sanitize.flag" }, work_dir))

  target(
    amap({ base_lua_modules_ok }, test_dir),
    push(extend({}, test_srcs, test_cfgs),
      test_dir(base_luarocks_cfg),
      work_dir("sanitize.flag")),
    function ()
      fs.mkdirp(test_dir())
      return fs.pushd(test_dir(), function ()
        -- TODO: It would be nice if santoku ivals returned an empty iterator
        -- for nil instead of erroring. It would allow omitting the {} below
        local vars = collect(map(fun.bind(sformat, "%s=%s"), flatten(map(pairs, ivals({
          tbl.get(test_env, "luarocks", "env_vars") or {},
          tbl.get(test_env, "test", "luarocks", "env_vars") or {},
          opts.wasm and tbl.get(test_env, "test", "wasm", "luarocks", "env_vars") or {},
          not opts.wasm and tbl.get(test_env, "test", "native", "luarocks", "env_vars") or {},
        })))))
        sys.execute(extend({
          "luarocks", "make", fs.basename(base_rockspec),
          env = {
            LUAROCKS_CONFIG = opts.luarocks_config or base_luarocks_cfg
          }
        }, vars))
        fs.touch(base_lua_modules_ok)
      end)
    end)

  target({ "build-deps" }, build_all, true)
  target({ "test-deps" }, test_all, true)

  local install_release_deps = opts.skip_tests
    and { "build-deps" }
    or { "test", "check", "build-deps" }

  target({ "install" }, install_release_deps, function ()
    fs.mkdirp(build_dir())
    return fs.pushd(build_dir(), function ()
      local vars = collect(map(fun.bind(sformat, "%s=%s"), flatten(map(pairs, ivals({
        tbl.get(build_env, "luarocks", "env_vars") or {},
        tbl.get(build_env, "build", "luarocks", "env_vars") or {},
        opts.wasm and tbl.get(build_env, "build", "wasm", "luarocks", "env_vars") or {},
        not opts.wasm and tbl.get(build_env, "build", "native", "luarocks", "env_vars") or {}
      })))))
      sys.execute(extend({
        "luarocks", "make", base_rockspec,
        env = {
          LUAROCKS_CONFIG = opts.luarocks_config or (opts.wasm and base_luarocks_cfg) or nil
        },
      }, vars))
    end)
  end)

  target({ "install-deps" }, install_release_deps, function ()
    fs.mkdirp(build_dir())
    return fs.pushd(build_dir(), function ()
      local vars = collect(map(fun.bind(sformat, "%s=%s"), flatten(map(pairs, ivals({
        tbl.get(build_env, "luarocks", "env_vars") or {},
        tbl.get(build_env, "build", "luarocks", "env_vars") or {},
        opts.wasm and tbl.get(build_env, "build", "wasm", "luarocks", "env_vars") or {},
        not opts.wasm and tbl.get(build_env, "build", "native", "luarocks", "env_vars") or {}
      })))))
      sys.execute(extend({
        "luarocks", "make", "--deps-only", base_rockspec,
        env = {
          LUAROCKS_CONFIG = opts.luarocks_config or (opts.wasm and base_luarocks_cfg) or nil
        },
      }, vars))
    end)
  end)

  -- NOTE: release not supported in wasm mode
  if not opts.wasm and opts.config.env.public then

    local release_tarball_dir = sinterp("%s#(name)-%s#(version)", opts.config.env)
    local release_tarball = release_tarball_dir .. ".tar.gz"
    local release_tarball_contents = push(amap(extend({}, base_bins, base_libs, base_deps), remove_tk), base_makefile)

    if #base_libs > 0 then
      push(release_tarball_contents, base_lib_makefile)
    end

    if #base_bins > 0 then
      push(release_tarball_contents, base_bin_makefile)
    end

    target({ "release" }, install_release_deps, function ()
      fs.mkdirp(build_dir())
      return fs.pushd(build_dir(), function ()
        varg.tup(function (ok, ...)
          if not ok then
            err.error("Commit your changes first", ...)
          end
        end, err.pcall(sys.execute, { "git", "diff", "--quiet" }))
        local api_key = opts.luarocks_api_key or env.var("LUAROCKS_API_KEY")
        if fs.exists(release_tarball) then
          fs.rm(release_tarball)
        end
        sys.execute({ "git", "tag", opts.config.env.version })
        sys.execute({ "git", "push", "--tags" })
        sys.execute({ "git", "push" })
        sys.execute({
          "tar", "--dereference", "--transform", sformat("s#^#%s/#", release_tarball_dir),
          "-czvf", release_tarball, spread(release_tarball_contents) })
        sys.execute({ "gh", "release", "create", "--generate-notes",
          opts.config.env.version, release_tarball, base_rockspec })
        sys.execute({ "luarocks", "upload", "--skip-pack", "--api-key", api_key, base_rockspec })
      end)
    end)

  end

  target({ "test" }, { "test-deps" }, function ()
    fs.mkdirp(test_dir())
    return fs.pushd(test_dir(), function ()
      sys.execute({ "sh", "run.sh" })
    end)
  end)

  target({ "check" }, { "test-deps" }, function ()
    if not opts.skip_check then
      fs.mkdirp(test_dir())
      return fs.pushd(test_dir(), function ()
        sys.execute({ "sh", "check.sh" })
      end)
    end
  end)

  target({ "exec" }, { "test-deps" }, function (_, _, args)
    fs.mkdirp(test_dir())
    return fs.pushd(test_dir(), function ()
      sys.execute(arr.copy({
        env = {
          LUA_PATH = test_env.lua_path,
          LUA_CPATH = test_env.lua_cpath,
        }
      }, args))
    end)
  end)

  target({ "iterate" }, {}, function ()
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
      end, err.pcall(build, { "test", "check" }, opts.verbosity))
      sys.execute({
        "inotifywait", "-qr",
        "-e", "close_write", "-e", "modify",
        "-e", "move", "-e", "create", "-e", "delete",
        spread(collect(filter(function (fp)
          return fs.exists(fp)
        end, chain(fs.files("."), ivals({ "lib", "bin", "test", "res" })))))
      })
      sys.sleep(250)
    end
  end)

  for fp in ivals(targets) do
    local dfile = fp .. ".d"
    if fs.exists(dfile) then
      local chunks = map(ssub, map(function (line)
        return ssplits(line, "%s*:%s*", false)
      end, fs.lines(dfile)))
      target(chunks(), collect(chunks))
    end
  end

  local configure = tbl.get(opts, "config", "env", "configure")
  if configure then
    configure(submake, build_env)
    configure(submake, test_env)
  end

  return {
    config = opts.config,
    test = function (opts)
      opts = opts or {}
      build(tbl.assign({ "test" }, opts), opts.verbosity)
      if not opts.skip_check then
        build(tbl.assign({ "check" }, opts), opts.verbosity)
      end
    end,
    check = function (opts)
      opts = opts or {}
      build(tbl.assign({ "check" }, opts), opts.verbosity)
    end,
    iterate = function (opts)
      opts = opts or {}
      build(tbl.assign({ "iterate" }, opts), opts.verbosity)
    end,
    install = function (opts)
      opts = opts or {}
      build(tbl.assign({ "install" }, opts), opts.verbosity)
    end,
    install_deps = function (opts)
      opts = opts or {}
      build(tbl.assign({ "install-deps" }, opts), opts.verbosity)
    end,
    release = not opts.wasm and function (opts)
      opts = opts or {}
      build(tbl.assign({ "release" }, opts), opts.verbosity)
    end,
    exec = not opts.wasm and function (opts)
      opts = opts or {}
      build(tbl.assign({ "exec" }), opts.verbosity, opts)
    end,
  }

end

return {
  init = init,
  create = create
}
