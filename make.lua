local fs = require("santoku.fs")
local env = require("santoku.env")
local sys = require("santoku.system")
local runner = require("santoku.test.runner")
local str = require("santoku.string")
local fun = require("santoku.fun")
local inherit = require("santoku.inherit")
local err = require("santoku.err")
local gen = require("santoku.gen")
local vec = require("santoku.vector")
local tbl = require("santoku.table")
local tpl = require("santoku.template")

local make = require("santoku.make")()

local build_dir = "build"

err.check(err.pwrap(function (check)

  local config = "config.lua"
  local cfg = check(fs.loadfile(config))()

  local function get_build_files (dir)
    local files = vec()
    if check(fs.exists(dir)) then
      files:extend(fs.files(dir, { recurse = true })
        :map(check)
        :map(fun.nret(1))
        :vec())
    end
    return files:map(function (fp)
      return { src = fp, build = fs.join(build_dir, fp) }
    end)
  end

  -- TODO: use fs.copy
  local function add_copied_target (dest, src)
    make:target(
      vec(dest),
      vec(src),
      function ()
        check(fs.mkdirp(fs.dirname(dest)))
        check(fs.writefile(dest, check(tpl.renderfile(src))))
        return true
      end)
  end

  local function add_templated_target (dest, src)
    make:target(
      vec(dest),
      vec(src, config),
      function (ts, ds)
        check(fs.mkdirp(fs.dirname(ts[1])))
        check(fs.writefile(ts[1], check(tpl.renderfile(ds[1], cfg))))
        return true
      end)
  end

  local bins = get_build_files("bin")
  local libs = get_build_files("lib")
  local test_specs = get_build_files("test/spec")
  local test_res = get_build_files("test/res")

  local build_specs = gen.ivals(test_specs):map(fun.bindr(tbl.get, "build")):vec()
  local build_res = gen.ivals(test_res):map(fun.bindr(tbl.get, "build")):vec()
  local build_test_rockspec = fs.join(build_dir, str.interp("test/%s#(name)-%s#(version).rockspec", cfg.env))
  local build_test_modules = fs.join(build_dir, "test/lua_modules")
  local build_test_modules = fs.join(build_dir, "test/lua_modules")
  local build_test_modules_ok = fs.join(build_dir, "test/lua_modules.ok")
  local build_test_luarocks_config = fs.join(build_dir, "test/luarocks.lua")
  local build_test_luacheck_config = fs.join(build_dir, "test/luacheck.lua")
  local build_test_luacov_config = fs.join(build_dir, "test/luacov.lua")
  local build_test_luacov_stats_file = fs.join(build_dir, "test/luacov.stats.out")
  local build_test_luacov_report_file = fs.join(build_dir, "test/luacov.report.out")

  inherit.pushindex(cfg.env, _G)

  cfg.env.build = {
    dir = build_dir,
    libs = libs,
    bins = bins,
    istest = true,
    test_modules = check(fs.absolute(build_test_modules)),
    test_luacov_stats_file = build_test_luacov_stats_file,
    test_luacov_report_file = build_test_luacov_report_file,
  }

  add_templated_target(build_test_luarocks_config, "make/luarocks.lua")
  add_templated_target(build_test_luacheck_config, "make/luacheck.lua")
  add_templated_target(build_test_luacov_config, "make/luacov.lua")
  add_templated_target(build_test_rockspec, "make/template.rockspec")

  test_specs:each(function (spec)
    add_copied_target(spec.build, spec.src)
  end)

  test_res:each(function (res)
    add_copied_target(res.build, res.src)
  end)

  make:target(
    vec(build_test_modules_ok),
    vec(config,
        build_test_luarocks_config,
        build_test_rockspec),
    function ()
      local cwd = check(fs.cwd())
      -- TODO: simplify with fs.pushd + callback
      check(fs.cd(fs.join(build_dir, "test")))
      local ok, err, cd = sys.execute(
        { env = { LUAROCKS_CONFIG = fs.basename(build_test_luarocks_config) } },
        "luarocks", "make", "--deps-only", fs.basename(build_test_rockspec))
      check(fs.cd(cwd))
      check(ok, err, cd)
      check(fs.touch(build_test_modules_ok))
      return true
    end)

  make:target(
    vec("test"),
    vec()
      :extend(build_specs)
      :extend(build_res)
      :append(
        build_test_modules_ok,
        build_test_luarocks_config,
        build_test_rockspec),
    function ()
      local cwd = check(fs.cwd())
      -- TODO: simplify with fs.pushd + callback
      check(fs.cd(fs.join(build_dir, "test")))
      local ok, err, cd = runner.run({ "spec" }, {
        interp = env.interpreter()[1],
        interp_opts = { env = {
          LUA_PATH = str.interp("%basedir/share/lua/5.1/?.lua;%basedir/share/lua/5.1/?/init.lua;%basedir/lib/lua/5.1/?.lua;%basedir/lib/lua/5.1/?/init.lua;./?.lua;./?/init.lua;/home/user/.luarocks/share/lua/5.1/?.lua;/home/user/.luarocks/share/lua/5.1/?/init.lua;/usr/share/luajit-2.1/?.lua", { basedir = "lua_modules" }),
          LUA_CPATH = str.interp("%basedir/lib/lua/5.1/?.so;%basedir/lib/lua/5.1/loadall.so;./?.so;/home/user/.luarocks/lib/lua/5.1/?.so", { basedir = "lua_modules" }),
        } },
        match = "%.lua$",
        stop = true
      })
      check(fs.cd(cwd))
      check(ok, err, cd)
      return true
    end)

  check(make:make(arg))

end))
