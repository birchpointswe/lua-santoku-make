<%
  str = require("santoku.string")
  squote = str.quote

  basexx = require("basexx")
  to_base64 = basexx.to_base64
%>

local make = require("santoku.make")

local varg = require("santoku.varg")
local tup = varg.tup
local reduce = varg.reduce

local fs = require("santoku.fs")
local cd = fs.cd
local pushd = fs.pushd
local cwd = fs.cwd
local join = fs.join
local mkdirp = fs.mkdirp
local dirname = fs.dirname
local writefile = fs.writefile
local stripextension = fs.stripextension
local readfile = fs.readfile
local rm = fs.rm
local extension = fs.extension
local absolute = fs.absolute
local exists = fs.exists
local touch = fs.touch
local files = fs.files
local lines = fs.lines
local basename = fs.basename

local validate = require("santoku.validate")
local istable = validate.istable
local isstring = validate.isstring

local sys = require("santoku.system")
local execute = sys.execute

local arr = require("santoku.array")
local amap = arr.map
local spread = arr.spread
local aincludes = arr.includes
local extend = arr.extend
local push = arr.push
local concat = arr.concat

local iter = require("santoku.iter")
local pairs = iter.pairs
local find = iter.find
local chain = iter.chain
local ivals = iter.ivals
local map = iter.map
local collect = iter.collect
local filter = iter.filter
local flatten = iter.flatten

local inherit = require("santoku.inherit")
local pushindex = inherit.pushindex

local fun = require("santoku.functional")
local bind = fun.bind

local tbl = require("santoku.table")
local get = tbl.get
local assign = tbl.assign
local insert = table.insert

local tmpl = require("santoku.template")
local renderfile = tmpl.renderfile
local compile = tmpl.compile
local serialize_deps = tmpl.serialize_deps

local bundle = require("santoku.bundle")

local str = require("santoku.string")
local sinterp = str.interp
local ssplits = str.splits
local supper = str.upper
local sformat = str.format
local smatch = str.match
local gsub = str.gsub
local ssub = str.sub

local env = require("santoku.env")
local interpreter = env.interpreter
local var = env.var

local basexx = require("basexx")
local from_base64 = basexx.from_base64

local err = require("santoku.error")
local pcall = err.pcall
local assert = err.assert
local error = err.error

local function create ()
  error("create lib not yet implemented")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build
  local targets = submake.targets

  assert(istable(opts))
  assert(istable(opts.config))

  opts.skip_coverage = opts.profile or opts.skip_coverage or nil

  local function work_dir (...)
    if opts.wasm then
      return join(opts.dir, opts.env .. "-wasm", ...)
    else
      return join(opts.dir, opts.env, ...)
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
    local ext = extension(fp)
    local match_fp = bind(smatch, fp)
    if (opts.exts and not aincludes(opts.config.exts or {}, ext)) or
        find(match_fp, ivals(get(opts.config, "rules", "exclude") or {}))
    then
      return "ignore"
    elseif find(match_fp, ivals(get(opts.config, "rules", "copy") or {}))
    then
      return "copy"
    else
      return "template"
    end
  end

  -- TODO: use fs.copy
  local function add_copied_target (dest, src)
    target({ dest }, { src }, function ()
      mkdirp(dirname(dest))
      writefile(dest, readfile(src))
    end)
  end

  local function add_templated_target (dest, src, env)
    local action = get_action(src, opts.config)
    if action == "copy" then
      return add_copied_target(dest, src, env)
    elseif action == "template" then
      target({ dest }, { src, opts.config_file }, function ()
        mkdirp(dirname(dest))
        local t, ds = renderfile(src, env)
        writefile(dest, t)
        writefile(dest .. ".d", serialize_deps(src, dest, ds))
      end)
    end
  end

  local function add_templated_target_base64 (dest, data, env)
    target({ dest }, { opts.config_file }, function ()
      mkdirp(dirname(dest))
      local t, ds = compile(from_base64(data))(env)
      writefile(dest, t)
      writefile(dest .. ".d", serialize_deps(dest, opts.config_file, ds))
    end)
  end

  local function get_lua_version ()
    return (smatch(_VERSION, "(%d+.%d+)"))
  end

  local function get_require_paths (prefix, ...)
    local pfx = prefix and join(prefix, "lua_modules") or "lua_modules"
    local ver = get_lua_version()
    local cwd = cwd()
    return concat(reduce(function (t, n)
      return push(t, join(cwd, pfx, sformat(n, ver)))
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

  local function get_files (dir)
    if not exists(dir) then
      return {}
    end
    return collect(filter(function (fp)
      return get_action(fp) ~= "ignore"
    end, files(dir, true)))
  end

  local base_bins = get_files("bin")
  local base_libs = get_files("lib")
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
  local base_test_res = get_files("test/res")

  local test_all_base = extend({},
    base_bins, base_libs, base_deps,
    base_test_deps, base_test_res)

  if opts.wasm then
    extend(test_all_base, collect(map(stripextension, ivals(base_test_specs))))
  else
    extend(test_all_base, base_test_specs)
  end

  local test_all = amap(extend({},
    test_all_base, base_rockspec, base_makefile,
    base_luarocks_cfg, base_luacheck_cfg, base_luacov_cfg,
    base_run_sh, base_check_sh), test_dir)

  local test_srcs = amap(extend({},
    base_bins, base_libs, base_deps, base_test_deps), test_dir)

  local test_cfgs = amap(push({},
    base_rockspec, base_makefile, base_luarocks_cfg,
    base_luacheck_cfg, base_luacov_cfg, base_run_sh,
    base_check_sh), test_dir)

  local build_all = amap(push(extend({},
    base_bins, base_libs, base_deps, opts.wasm and { base_luarocks_cfg } or {}),
    base_rockspec, base_makefile), build_dir)

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
    skip_coverage = opts.skip_coverage,
    single = opts.single,
    bins = base_bins,
    libs = base_libs,
    root_dir = cwd(),
    var = function (n)
      assert(isstring(n))
      return concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local test_env = {
    environment = "test",
    lua = opts.lua or interpreter()[1],
    lua_path = opts.lua_path or get_lua_path(test_dir()),
    lua_cpath = opts.lua_cpath or get_lua_cpath(test_dir()),
    lua_modules = absolute(test_dir(base_lua_modules)),
    luarocks_config = absolute(test_dir(base_luarocks_cfg)),
    luacov_stats_file = absolute(test_dir(base_luacov_stats_file)),
    luacov_report_file = absolute(test_dir(base_luacov_report_file))
  }

  if opts.lua_path_extra then
    test_env.lua_path = concat({ test_env.lua_path, ";", opts.lua_path_extra })
  end

  if opts.lua_cpath_extra then
    test_env.lua_cpath = concat({ test_env.lua_cpath, ";", opts.lua_cpath_extra })
  end

  local build_env = {
    environment = "build",
    lua_modules = opts.wasm and absolute(build_dir(base_lua_modules)) or nil,
  }

  pushindex(test_env, _G)
  pushindex(test_env, base_env)
  pushindex(test_env, opts.config.env)

  pushindex(build_env, _G)
  pushindex(build_env, base_env)
  pushindex(build_env, opts.config.env)

  if opts.wasm then

    for dir, all, env in map(spread, ivals({
      { test_dir, test_all, test_env },
      { build_dir, build_all, build_env }
    })) do

      local client_lua_dir = absolute(dir(base_lua_dir))
      local client_lua_ok = client_lua_dir .. ".ok"

      env.client_lua_dir = client_lua_dir

      insert(all, 1, client_lua_ok)

      target({ client_lua_ok }, {}, function ()
        mkdirp(dir())
        return pushd(dir(), function ()

          if not exists("lua-5.1.5.tar.gz") then
            execute({ "wget", "https://www.lua.org/ftp/lua-5.1.5.tar.gz" })
          end

          if exists("lua-5.1.5") then
            execute({ "rm", "-rf", "lua-5.1.5" }) -- TODO: use fs.rm(x, { recurse = true })
          end

          execute({ "tar", "xf", "lua-5.1.5.tar.gz" })
          cd("lua-5.1.5")
          execute({ "emmake", "sh", "-c",
            "make generic CC=\"$CC\" LD=\"$LD\" AR=\"$AR rcu\"" ..
            "  RANLIB=\"$RANLIB\" MYLDFLAGS=\"-sSINGLE_FILE -sEXIT_RUNTIME=1 -lnodefs.js -lnoderawfs.js\"" })
          execute({ "make", "local" })
          cd("bin")
          execute({ "mv", "lua", "lua.js" })
          execute({ "mv", "luac", "luac.js" })
          writefile("lua", "#!/bin/sh\nnode \"$(dirname $0)/lua.js\" \"$@\"\n")
          writefile("luac", "#!/bin/sh\nnode \"$(dirname $0)/luac.js\" \"$@\"\n")
          execute({ "chmod", "+x", "lua" })
          execute({ "chmod", "+x", "luac" })
          touch(client_lua_ok)

        end)
      end)

    end

  end

  opts.config.env.variable_prefix =
    opts.config.env.variable_prefix or
    supper((gsub(opts.config.env.name, "%W+", "_")))

  for fp in flatten(map(ivals, ivals({ base_libs, base_bins, base_deps }))) do
    add_templated_target(build_dir(fp), fp, build_env)
  end

  for fp in flatten(map(ivals, ivals({ base_libs, base_bins, base_deps, base_test_deps }))) do
    add_templated_target(test_dir(fp), fp, test_env)
  end

  if not opts.wasm then

    for fp in ivals(base_test_specs) do
      add_templated_target(test_dir(fp), fp, test_env)
    end

  else

    for fp in ivals(base_test_specs) do
      add_templated_target(test_dir("bundler-pre", fp), fp, test_env)
    end

    for fp in ivals(base_test_specs) do
      target({ test_dir("bundler-post", stripextension(fp)) },
        push(extend({ test_dir("bundler-pre", fp) },
          test_cfgs), test_dir(base_lua_modules_ok)),
        function ()
          bundle(test_dir("bundler-pre", fp), test_dir("bundler-post", dirname(fp)), {
            cc = "emcc",
            mods = extend({},
              opts.skip_coverage and {} or { "luacov", "luacov.hook", "luacov.tick" },
              opts.profile and { "santoku.profile" } or {}),
            ignores = { "debug" },
            env = {
              { base_env.var("WASM"), "1" },
              { base_env.var("PROFILE"), opts.profile and "1" or "" },
              { base_env.var("SANITIZE"), opts.sanitize and "1" or "" },
              { "LUACOV_CONFIG", absolute(test_dir(base_luacov_cfg)) }
            },
            path = get_lua_path(test_dir()),
            cpath = get_lua_cpath(test_dir()),
            flags = {
              opts.sanitize and "-fsanitize=address" or "",
              "-sASSERTIONS", "-sSINGLE_FILE", "-sALLOW_MEMORY_GROWTH",
              "-I" .. join(test_env.client_lua_dir, "include"),
              "-L" .. join(test_env.client_lua_dir, "lib"),
              "-lnodefs.js", "-lnoderawfs.js", "-llua", "-lm",
              get(test_env, "test", "cflags") or "",
              get(test_env, "test", "ldflags") or "",
              get(test_env, "test", "wasm", "cflags") or "",
              get(test_env, "test", "wasm", "ldflags") or "",
              get(test_env, "test", "sanitize", "wasm", "cflags") or "",
              get(test_env, "test", "sanitize", "wasm", "ldflags") or "",
            }
          })
        end)
    end

    for fp in ivals(base_test_specs) do
      add_copied_target(test_dir(stripextension(fp)),
        test_dir("bundler-post", stripextension(fp)), test_env)
    end

  end

  for fp in ivals(base_test_res) do
    add_copied_target(test_dir(fp), fp, test_env)
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
    "skip_coverage", "lua", "lua_path_extra", "lua_cpath_extra"
  }) do
    local fp = work_dir(flag .. ".flag")
    mkdirp(dirname(fp))
    local strval = tostring(opts[flag])
    if not exists(fp) then
      writefile(fp, strval)
    else
      local val = readfile(fp)
      if val ~= strval then
        writefile(fp, strval)
      end
    end
  end

  target(
    amap({ base_run_sh, base_check_sh }, test_dir),
    amap({
      "skip_coverage.flag", "single.flag", "profile.flag", "sanitize.flag",
      "lua.flag", "lua_path_extra.flag", "lua_cpath_extra.flag" }, work_dir))

  target(
    amap(extend({ base_run_sh, base_check_sh }, base_libs), test_dir),
    amap({ "sanitize.flag" }, work_dir))

  target(
    amap({ base_lua_modules_ok }, test_dir),
    push(extend({}, test_srcs, test_cfgs),
      test_dir(base_luarocks_cfg),
      work_dir("sanitize.flag")),
    function ()
      mkdirp(test_dir())
      return pushd(test_dir(), function ()

        -- TODO: It would be nice if santoku ivals returned an empty iterator
        -- for nil instead of erroring. It would allow omitting the {} below
        local vars = collect(map(bind(sformat, "%s=%s"), flatten(map(pairs, ivals({
          get(test_env, "luarocks", "env_vars") or {},
          get(test_env, "test", "luarocks", "env_vars") or {},
          opts.wasm and get(test_env, "test", "wasm", "luarocks", "env_vars") or {},
          not opts.wasm and get(test_env, "test", "native", "luarocks", "env_vars") or {},
        })))))

        execute(extend({
          "luarocks", "make", basename(base_rockspec),
          env = {
            LUAROCKS_CONFIG = opts.luarocks_config or base_luarocks_cfg
          }
        }, vars))

        local post_make = get(test_env, "test", "hooks", "post_make")

        if post_make then
          post_make(test_env)
        end

        touch(base_lua_modules_ok)

      end)
    end)

  target({ "build-deps" }, build_all, true)
  target({ "test-deps" }, test_all, true)

  local install_release_deps = opts.skip_tests
    and { "build-deps" }
    or { "test", "check", "build-deps" }

  target({ "install" }, install_release_deps, function ()
    return pushd(build_dir(), function ()

      local vars = collect(map(bind(sformat, "%s=%s"), flatten(map(pairs, ivals({
        get(build_env, "luarocks", "env_vars") or {},
        get(build_env, "build", "luarocks", "env_vars") or {},
        opts.wasm and get(build_env, "build", "wasm", "luarocks", "env_vars") or {},
        not opts.wasm and get(build_env, "build", "native", "luarocks", "env_vars") or {}
      })))))

      execute(extend({
        "luarocks", "make", base_rockspec,
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
    local release_tarball_contents = push(extend({}, base_bins, base_libs, base_deps), base_makefile)

    if #base_libs > 0 then
      push(release_tarball_contents, base_lib_makefile)
    end

    if #base_bins > 0 then
      push(release_tarball_contents, base_bin_makefile)
    end

    target({ "release" }, install_release_deps, function ()
      return pushd(build_dir(), function ()

        tup(function (ok, ...)
          if not ok then
            error("Commit your changes first", ...)
          end
        end, pcall(execute, { "git", "diff", "--quiet" }))

        local api_key = opts.luarocks_api_key or var("LUAROCKS_API_KEY")

        if exists(release_tarball) then
          rm(release_tarball)
        end

        execute({ "git", "tag", opts.config.env.version })
        execute({ "git", "push", "--tags" })
        execute({ "git", "push" })
        execute({
          "tar", "--dereference", "--transform", sformat("s#^#%s/#", release_tarball_dir),
          "-czvf", release_tarball, spread(release_tarball_contents) })
        execute({ "gh", "release", "create", "--generate-notes",
          opts.config.env.version, release_tarball, base_rockspec })
        execute({ "luarocks", "upload", "--skip-pack", "--api-key", api_key, base_rockspec })

      end)
    end)

  end

  target({ "test" }, { "test-deps" }, function ()
    return pushd(test_dir(), function ()
      execute({ "sh", "run.sh" })
    end)
  end)

  target({ "check" }, { "test-deps" }, function ()
    return pushd(test_dir(), function ()
      execute({ "sh", "check.sh" })
    end)
  end)

  target({ "exec" }, { "test-deps" }, function (_, _, args)
    return pushd(test_dir(), function ()
      execute(arr.copy({
        env = {
          LUA_PATH = test_env.lua_path,
          LUA_CPATH = test_env.lua_cpath,
        }
      }, args))
    end)
  end)

  target({ "iterate" }, {}, function ()

    tup(function (ok, ...)

      if not ok then
        error("inotify not found", ...)
      end

    end, pcall(execute, { "sh", "-c", "type inotifywait >/dev/null 2>/dev/null" }))

    while true do

      tup(function (ok, ...)

        if not ok then
          print(...)
        end

      end, pcall(build, { "test", "check" }, opts.verbosity))

      execute({
        "inotifywait", "-qr",
        "-e", "close_write", "-e", "modify",
        "-e", "move", "-e", "create", "-e", "delete",
        spread(collect(filter(function (fp)
          return exists(fp)
        end, chain(files("."), ivals({ "lib", "bin", "test", "res" })))))
      })

    end

  end)

  for fp in ivals(targets) do
    local dfile = fp .. ".d"
    if exists(dfile) then
      local chunks = map(ssub, map(function (str, s, e)
        return ssplits(str, "%s*:%s*", false, s, e)
      end, lines(dfile)))
      target(chunks(), collect(chunks))
    end
  end

  return {

    config = opts.config,

    test = function (opts)
      opts = opts or {}
      build(assign({ "test" }, opts), opts.verbosity)
      if not opts.skip_check then
        build(assign({ "check" }, opts), opts.verbosity)
      end
    end,

    check = function (opts)
      opts = opts or {}
      build(assign({ "check" }, opts), opts.verbosity)
    end,

    iterate = function (opts)
      opts = opts or {}
      build(assign({ "iterate" }, opts), opts.verbosity)
    end,

    install = function (opts)
      opts = opts or {}
      build(assign({ "install" }, opts), opts.verbosity)
    end,

    release = not opts.wasm and function (opts)
      opts = opts or {}
      build(assign({ "release" }, opts), opts.verbosity)
    end,

    exec = not opts.wasm and function (opts)
      opts = opts or {}
      build(assign({ "exec" }), opts.verbosity, opts)
    end,

  }

end

return {
  init = init,
  create = create
}
