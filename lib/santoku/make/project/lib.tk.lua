<%
  str = require("santoku.string")
  squote = str.quote
  to_base64 = str.to_base64
  fs = require("santoku.fs")
  readfile = fs.readfile
%>

local bundle = require("santoku.bundle")
local env = require("santoku.env")
local fs = require("santoku.fs")
local make = require("santoku.make")
local sys = require("santoku.system")
local tbl = require("santoku.table")
local tmpl = require("santoku.template")
local varg = require("santoku.varg")
local vdt = require("santoku.validate")
local err = require("santoku.error")
local fun = require("santoku.functional")
local common = require("santoku.make.common")
local wasm = require("santoku.make.wasm")

local arr = require("santoku.array")
local amap = arr.map
local spread = arr.spread
local extend = arr.extend
local push = arr.push
local concat = arr.concat

local iter = require("santoku.iter")
local ivals = iter.ivals
local pairs = iter.pairs
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

-- Embedded templates for lib init
local init_templates = {
  make_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/make.lua"))) %>), -- luacheck: ignore
  bin_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/bin.lua"))) %>), -- luacheck: ignore
  lib_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/lib.lua"))) %>), -- luacheck: ignore
  test_spec_lua = from_base64(<% return squote(to_base64(readfile("res/init/lib/test-spec.lua"))) %>), -- luacheck: ignore
  gitignore = from_base64(<% return squote(to_base64(readfile("res/init/lib/gitignore"))) %>), -- luacheck: ignore
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

  -- Evaluate templates
  local files = {
    ["make.lua"] = tmpl.render(init_templates.make_lua, template_env),
    [fs.join("bin", name .. ".lua")] = tmpl.render(init_templates.bin_lua, template_env),
    [fs.join("lib", name .. ".lua")] = tmpl.render(init_templates.lib_lua, template_env),
    [fs.join("test/spec", name .. ".lua")] = tmpl.render(init_templates.test_spec_lua, template_env),
    [".gitignore"] = init_templates.gitignore,
  }

  -- Create directories and write files
  for fpath, content in pairs(files) do
    local full_path = fs.join(dir, fpath)
    fs.mkdirp(fs.dirname(full_path))
    fs.writefile(full_path, content)
  end

  -- Initialize git if requested
  if opts.git ~= false then
    sys.execute({ "git", "init", dir })
  end

  io.stdout:write("Created library project: " .. name .. "\n")
  io.stdout:write("\nNext steps:\n")
  io.stdout:write("  cd " .. dir .. "\n")
  io.stdout:write("  toku lib test        # Run tests\n")
  io.stdout:write("  toku lib install     # Install locally\n")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build
  local targets = submake.targets

  err.assert(vdt.istable(opts))
  err.assert(vdt.istable(opts.config))

  opts.skip_check = opts.skip_check or nil

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

  local function remove_tk(fp)
    return common.remove_tk(fp, opts.config)
  end

  local function add_copied_target(dest, src, extra_srcs)
    return common.add_copied_target(target, dest, src, extra_srcs)
  end

  local function add_file_target(dest, src, env, extra_srcs)
    return common.add_file_target(target, dest, src, env, opts.config, opts.config_file, extra_srcs)
  end

  local function add_templated_target_base64(dest, data, env, extra_srcs)
    return common.add_templated_target_base64(target, dest, data, env, opts.config_file, extra_srcs)
  end

  local function get_lua_path(prefix)
    return common.get_lua_path(prefix)
  end

  local function get_lua_cpath(prefix)
    return common.get_lua_cpath(prefix)
  end

  local function get_files(dir, check_tpl)
    return common.get_files(dir, opts.config, check_tpl, false)
  end

  local base_bins = get_files("bin")
  local base_libs = get_files("lib")
  local base_res, base_res_templated = get_files("res", true)
  local base_deps = get_files("deps")

  local base_rockspec = sinterp("%s#(name)-%s#(version).rockspec", opts.config.env)
  local base_makefile = "Makefile"
  local base_license = "LICENSE"
  local base_lib_makefile = "lib/Makefile"
  local base_bin_makefile = "bin/Makefile"
  local base_luarocks_cfg = "luarocks.lua"
  local base_lua_modules = "lua_modules"
  local base_lua_modules_ok = "lua_modules.ok"
  local base_luacheck_cfg = "luacheck.lua"
  local base_run_sh = "run.sh"
  local base_check_sh = "check.sh"

  local base_test_specs = opts.single and { opts.single } or get_files("test/spec")

  -- Filter out .wasm.lua test specs for native builds
  if not opts.wasm then
    base_test_specs = collect(filter(function (fp)
      return not smatch(fp, "%.wasm%.lua$")
    end, ivals(base_test_specs)))
  end

  -- Helper to strip .wasm from filenames (for WASM builds)
  local function remove_wasm(fp)
    return gsub(fp, "%.wasm%.", ".")
  end

  local base_test_deps = get_files("test/deps")
  local base_test_res, base_test_res_templated = get_files("test/res", true)

  local test_all_base_templated = extend({},
    base_bins, base_libs, base_deps,
    base_test_deps, base_res_templated, base_test_res_templated)

  local test_all_base_copied = extend({},
    base_res, base_test_res)

  if opts.wasm then
    -- Add JS files (bundler uses SINGLE_FILE so no separate .wasm)
    extend(test_all_base_templated, collect(map(fun.compose(fs.stripextension, remove_wasm), ivals(base_test_specs))))
  else
    extend(test_all_base_templated, base_test_specs)
  end

  local test_all = amap(extend({},
    amap(extend({},
      test_all_base_templated,
      { base_rockspec, base_makefile,
        base_luarocks_cfg, base_luacheck_cfg,
        base_run_sh, base_check_sh }), remove_tk),
    test_all_base_copied), test_dir)

  local test_srcs = amap(amap(extend({},
    base_bins, base_libs, base_deps, base_test_deps), test_dir), remove_tk)

  local test_cfgs = amap(amap(push({},
    base_rockspec, base_makefile, base_luarocks_cfg,
    base_luacheck_cfg, base_run_sh,
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
    skip_check = opts.skip_check,
    single = opts.single and remove_tk(opts.single) or nil,
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
    build_dir = test_dir(),
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
    build_dir = build_dir(),
    target = "build",
  }

  tbl.merge(test_env, opts.config.env, base_env)
  tbl.merge(build_env, opts.config.env, base_env)

  if opts.wasm then
    for dir_fn, all, env in map(spread, ivals({
      { test_dir, test_all, test_env },
      { build_dir, build_all, build_env }
    })) do
      local lua_dir, lua_ok = wasm.setup_lua(target, dir_fn())
      env.client_lua_dir = lua_dir
      tbl.insert(all, 1, lua_ok)
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
      target({ test_dir("bundler-post", fs.stripextension(remove_wasm(fp))) },
        push(extend({ test_dir("bundler-pre", fp) },
          test_cfgs), test_dir(base_lua_modules_ok)),
        function ()
          local extra_cflags = extend({},
            tbl.get(test_env, "test", "cflags") or {},
            tbl.get(test_env, "test", "wasm", "cflags") or {})
          local extra_ldflags = extend({},
            tbl.get(test_env, "test", "ldflags") or {},
            tbl.get(test_env, "test", "wasm", "ldflags") or {})
          bundle(test_dir("bundler-pre", fp), test_dir("bundler-post", fs.dirname(fp)), {
            cc = "emcc",
            close = false,
            ignores = { "debug" },
            env = {
              { base_env.var("WASM"), "1" },
            },
            path = get_lua_path(test_dir()),
            cpath = get_lua_cpath(test_dir()),
            flags = wasm.get_bundle_flags(test_env.client_lua_dir, "test", extra_cflags, extra_ldflags)
          })
        end)
    end

    for fp in ivals(base_test_specs) do
      -- Copy JS file (bundler uses SINGLE_FILE so no separate .wasm)
      add_file_target(test_dir(fs.stripextension(remove_wasm(remove_tk(fp)))),
        test_dir("bundler-post", fs.stripextension(remove_wasm(fp))), test_env)
    end

  end

  if fs.exists(base_license) then
    add_copied_target(build_dir(base_license), base_license)
    push(build_all, build_dir(base_license))
  end

  for fp in ivals(base_res) do
    add_file_target(build_dir(remove_tk(fp)), fp, build_env)
  end

  for fp in ivals(base_res_templated) do
    add_file_target(build_dir(remove_tk(fp)), fp, build_env)
  end

  for fp in ivals(base_res) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
  end

  for fp in ivals(base_res_templated) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
  end

  for fp in ivals(base_test_res) do
    add_file_target(test_dir(remove_tk(fp)), fp, test_env)
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

  add_templated_target_base64(test_dir(base_run_sh),
    <% return squote(to_base64(readfile("res/lib/test-run.sh"))) %>, test_env) -- luacheck: ignore

  add_templated_target_base64(test_dir(base_check_sh),
    <% return squote(to_base64(readfile("res/lib/test-check.sh"))) %>, test_env) -- luacheck: ignore

  for flag in ivals({
    "single", "skip_check", "lua",
    "lua_path_extra", "lua_cpath_extra"
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
      "skip_check.flag", "single.flag",
      "lua.flag", "lua_path_extra.flag", "lua_cpath_extra.flag" },
      work_dir))

  target(
    amap({ base_lua_modules_ok }, test_dir),
    push(extend({}, test_srcs, test_cfgs),
      test_dir(base_luarocks_cfg)),
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
        local lcfg = opts.luarocks_config or base_luarocks_cfg
        lcfg = lcfg and fs.absolute(lcfg) or nil
        sys.execute(extend({
          "luarocks", "make", fs.basename(base_rockspec),
          env = {
            LUAROCKS_CONFIG = lcfg
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
      local lcfg = opts.luarocks_config or (opts.wasm and base_luarocks_cfg) or nil
      lcfg = lcfg and fs.absolute(lcfg) or nil
      sys.execute(extend({
        "luarocks", "make", base_rockspec,
        env = {
          LUAROCKS_CONFIG = lcfg
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
      local lcfg = opts.luarocks_config or (opts.wasm and base_luarocks_cfg) or nil
      lcfg = lcfg and fs.absolute(lcfg) or nil
      sys.execute(extend({
        "luarocks", "make", "--deps-only", base_rockspec,
        env = {
          LUAROCKS_CONFIG = lcfg
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

    if fs.exists(base_license) then
      push(release_tarball_contents, base_license)
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
    local config_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
    while true do
      err.pcall(function ()
        -- Check if config file changed - if so, need to restart
        if config_mtime then
          local new_mtime = fs.exists(opts.config_file) and require("santoku.make.posix").time(opts.config_file) or nil
          if new_mtime and new_mtime > config_mtime then
            print("\n[iterate] " .. opts.config_file .. " changed - please restart iterate\n")
            config_mtime = new_mtime
          end
        end
        varg.tup(function (ok, ...)
          if not ok then
            print(...)
          end
        end, err.pcall(build, { "test", "check" }, opts.verbosity))
      end)
      -- Collect directories from .d files
      local dfile_dirs = {}
      err.pcall(function ()
        for dfile in fs.files(work_dir(), true) do
          if str.find(dfile, "%.d$") then
            local data = fs.readfile(dfile)
            local file_deps = tmpl.deserialize_deps(data)
            for fp in iter.keys(file_deps) do
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
          end, chain(fs.files("."), ivals({ "lib", "bin", "test", "res" }), iter.keys(dfile_dirs)))))
        })
      end)
      sys.sleep(.25)
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
    configure(submake, { root = build_env })
    configure(submake, { root = test_env })
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
    install = function (install_opts)
      install_opts = install_opts or {}
      if install_opts.bundled then
        -- Bundled install: compile bin/*.lua to standalone executables
        build(tbl.assign({ "install-deps" }, install_opts), install_opts.verbosity)

        local bin_dir = "bin"
        if not fs.exists(bin_dir) then
          err.error("No bin/ directory found for bundled install")
        end

        local prefix = install_opts.prefix or env.var("PREFIX", fs.join(env.var("HOME", "/tmp"), ".local"))
        local bin_prefix = fs.join(prefix, "bin")
        fs.mkdirp(bin_prefix)

        local bundle_dir = build_dir("bundled")
        fs.mkdirp(bundle_dir)

        -- Determine compiler and flags
        local cc = install_opts.bundle_cc
        local bundle_flags = {}
        local bundle_mods = {}
        local bundle_ignores = { "debug" }

        if install_opts.bundle_flags then
          for flag in str.splits(install_opts.bundle_flags, "%s+") do
            push(bundle_flags, flag)
          end
        end

        if install_opts.bundle_mods then
          for mod in str.splits(install_opts.bundle_mods, ",") do
            push(bundle_mods, str.match(mod, "^%s*(.-)%s*$"))
          end
        end

        if install_opts.bundle_ignores then
          for mod in str.splits(install_opts.bundle_ignores, ",") do
            push(bundle_ignores, str.match(mod, "^%s*(.-)%s*$"))
          end
        end

        if install_opts.wasm then
          cc = cc or "emcc"
          -- For WASM, use wasm module flags if not specified
          if #bundle_flags == 0 then
            local lua_dir = build_dir("lua-5.1.5")
            bundle_flags = wasm.get_bundle_flags(lua_dir, "build", {}, {})
          end
        else
          cc = cc or env.var("CC", "cc")
        end

        -- Bundle each executable in bin/
        for fp in fs.files(bin_dir) do
          if str.match(fp, "%.lua$") then
            local basename = fs.stripextensions(fs.basename(fp))
            bundle(fp, bundle_dir, {
              cc = cc,
              mods = bundle_mods,
              ignores = bundle_ignores,
              path = get_lua_path(build_dir()),
              cpath = get_lua_cpath(build_dir()),
              flags = bundle_flags,
              outprefix = basename,
            })

            -- Copy to prefix
            if install_opts.wasm then
              local js_file = fs.join(bundle_dir, basename .. ".js")
              local dest_js = fs.join(bin_prefix, basename .. ".js")
              local dest_wrapper = fs.join(bin_prefix, basename)
              fs.writefile(dest_js, fs.readfile(js_file))
              wasm.create_node_wrapper(dest_wrapper, dest_js)
            else
              local exe_file = fs.join(bundle_dir, basename)
              local dest_exe = fs.join(bin_prefix, basename)
              fs.writefile(dest_exe, fs.readfile(exe_file))
              sys.execute({ "chmod", "+x", dest_exe })
            end
          end
        end
      else
        -- Regular luarocks install
        build(tbl.assign({ "install" }, install_opts), install_opts.verbosity)
      end
    end,
    install_deps = function (opts)
      opts = opts or {}
      build(tbl.assign({ "install-deps" }, opts), opts.verbosity)
    end,
    release = not opts.wasm and opts.config.env.public and function (opts)
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
