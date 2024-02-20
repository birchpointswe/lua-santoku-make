<%
  str = require("santoku.string")
  squote = str.quote

  basexx = require("basexx")
  to_base64 = basexx.to_base64
%>

local make = require("santoku.make")
local bundle = require("santoku.bundle")

local varg = require("santoku.varg")
local tup = varg.tup
local vmap = varg.map
local reduce = varg.reduce

local fs = require("santoku.fs")
local pushd = fs.pushd
local stripexts = fs.stripextensions
local stripparts = fs.stripparts
local cwd = fs.cwd
local join = fs.join
local mkdirp = fs.mkdirp
local dirname = fs.dirname
local writefile = fs.writefile
local readfile = fs.readfile
local extension = fs.extension
local absolute = fs.absolute
local exists = fs.exists
local touch = fs.touch
local files = fs.files

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

local it = require("santoku.iter")
local find = it.find
local chain = it.chain
local ivals = it.ivals
local collect = it.collect
local filter = it.filter
local map = it.map

local inherit = require("santoku.inherit")
local pushindex = inherit.pushindex

local fun = require("santoku.functional")
local bind = fun.bind

local tbl = require("santoku.table")
local get = tbl.get
local assign = tbl.assign

local tmpl = require("santoku.template")
local renderfile = tmpl.renderfile
local compile = tmpl.compile
local serialize_deps = tmpl.serialize_deps

local str = require("santoku.string")
local stripprefix = str.stripprefix
local supper = string.upper
local sformat = string.format
local smatch = string.match
local gsub = string.gsub

local env = require("santoku.env")
local interpreter = env.interpreter

local basexx = require("basexx")
local from_base64 = basexx.from_base64

local err = require("santoku.error")
local pcall = err.pcall
local assert = err.assert
local error = err.error

local function create ()
  error("create web not yet implemented")
end

local function init (opts)

  local submake = make(opts)
  local target = submake.target
  local build = submake.build

  assert(istable(opts))
  assert(istable(opts.config))

  opts.single = opts.single and opts.single:gsub("^[^/]+/", "") or nil
  opts.skip_coverage = opts.profile or opts.skip_coverage or nil
  opts.openresty_dir = opts.openresty_dir or opts.config.openresty_dir or env.var("OPENRESTY_DIR")

  local function work_dir (...)
    return join(opts.dir, opts.env, ...)
  end

  local function dist_dir (...)
    return work_dir("main", "dist", ...)
  end

  local function server_dir (...)
    return work_dir("main", "server", ...)
  end

  local function server_dir_stripped (...)
    return server_dir(vmap(function (fp)
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
    return test_server_dir(vmap(function (fp)
      return stripprefix(fp, "server/")
    end, ...))
  end

  local function client_dir (...)
    return work_dir("main", "client", ...)
  end

  local function client_dir_stripped (...)
    return client_dir(vmap(function (fp)
      return stripprefix(fp, "client/")
    end, ...))
  end

  local function test_client_dir (...)
    return work_dir("test", "client", ...)
  end

  local function test_client_dir_stripped (...)
    return test_client_dir(vmap(function (fp)
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
    return dist_dir("public", vmap(function (fp)
      return stripparts(fp, 2)
    end, ...))
  end

  local function test_dist_dir_client_stripped (...)
    return test_dist_dir("public", vmap(function (fp)
      return stripparts(fp, 2)
    end, ...))
  end

  -- TODO: It would be nice if santoku ivals returned an empty iterator for
  -- nil instead of erroring. It would allow omitting the {} below
  local function get_action (fp)
    local ext = extension(fp)
    local match_fp = bind(smatch, fp)
    if (opts.exts and not aincludes(opts.exts, ext)) or
        find(match_fp, ivals(get(opts, "rules", "exclude") or {}))
    then
      return "ignore"
    elseif find(match_fp, ivals(get(opts, "rules", "copy") or {}))
    then
      return "copy"
    else
      return "template"
    end
  end

  -- TODO: use fs.copy
  local function add_copied_target (dest, src, extra_srcs)
    extra_srcs = extra_srcs or {}
    target({ dest }, extend({ src }, extra_srcs), function ()
      mkdirp(dirname(dest))
      writefile(dest, readfile(src))
    end)
  end

  local function add_copied_target_base64 (dest, data)
    target({ dest }, {}, function ()
      mkdirp(dirname(dest))
      writefile(dest, from_base64(data))
    end)
  end

  local function add_templated_target (dest, src, env)
    local action = get_action(src, opts.config)
    if action == "copy" then
      return add_copied_target(dest, src)
    elseif action == "template" then
      target({ dest }, { src, opts.config_file }, function ()
        mkdirp(dirname(dest))
        local t, ds = renderfile(src, env)
        writefile(dest, t)
        writefile(dest .. ".d", serialize_deps(src, dest, ds))
      end)
    end
  end

  local function add_templated_target_base64 (dest, data, env, extra_srcs)
    extra_srcs = extra_srcs or {}
    target({ dest }, extend({ opts.config_file }, extra_srcs), function ()
      mkdirp(dirname(dest))
      local t, ds = compile(from_base64(data))(env)
      writefile(dest, t)
      writefile(dest .. ".d", serialize_deps(dest, opts.config_file, ds))
    end)
  end

  local function get_lua_version ()
    return (smatch(_VERSION, "(%d+.%d+)"))
  end

  local function get_require_paths (prefix, wd, ...)
    wd = wd or cwd()
    local pfx = prefix and join(prefix, "lua_modules") or "lua_modules"
    local ver = get_lua_version()
    return concat(reduce(function (t, n)
      return push(t, join(wd, pfx, sformat(n, ver)))
    end, {}, ...), ";")
  end

  local function get_lua_path (prefix, wd)
    return get_require_paths(prefix, wd,
      "share/lua/%s/?.lua",
      "share/lua/%s/?/init.lua",
      "lib/lua/%s/?.lua",
      "lib/lua/%s/?/init.lua")
  end

  local function get_lua_cpath (prefix, wd)
    return get_require_paths(prefix, wd,
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

  local base_server_libs = get_files("server/lib")
  local base_server_deps = get_files("server/deps")
  local base_server_test_specs = get_files("server/test/spec")
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
  local base_client_res = get_files("client/res")
  local base_client_res_templated = get_files("client/res/templated")
  local base_client_lua_modules_ok = "lua_modules.ok"
  local base_client_wrap_events_js = "wrap_events.js"
  local base_client_spa_index_lua = "spa_index.lua"
  local base_client_spa_index_html = "spa_index.html"

  local base_client_spa = fs.exists("client/spa") and collect(fs.dirs("client/spa")) or {}

  local base_client_pages = collect(map(function (fp)
    return stripparts(stripexts(fp) .. ".js", 2)
  end, ivals(base_client_bins)))

  extend(base_client_pages, it.collect(it.map(function (d)
    return stripparts(d, 2) .. ".js"
  end, it.ivals(base_client_spa))))

  local base_client_public = extend({},
    amap(extend({}, base_client_assets), function (fp)
      return fs.stripparts(fp, 2)
    end),
    amap(extend({}, base_client_static), function (fp)
      return fs.stripparts(fp, 2)
    end),
    base_client_pages)

  local base_env = {
    root_dir = cwd(),
    profile = opts.profile,
    skip_coverage = opts.skip_coverage,
    var = function (n)
      assert(isstring(n))
      return concat({ opts.config.env.variable_prefix, "_", n })
    end
  }

  local server_env = {
    environment = "main",
    component = "server",
    background = opts.background,
    libs = base_server_libs,
    dist_dir = absolute(dist_dir()),
    openresty_dir = absolute(opts.openresty_dir),
    lua_modules = absolute(dist_dir(base_server_lua_modules)),
    luarocks_cfg = absolute(server_dir(base_server_luarocks_cfg)),
  }

  local server_daemon_env = {
    background = true
  }

  local test_server_env = {
    environment = "test",
    component = "server",
    background = opts.background,
    libs = base_server_libs,
    dist_dir = absolute(test_dist_dir()),
    openresty_dir = absolute(opts.openresty_dir),
    luarocks_cfg = absolute(test_server_dir(base_server_luarocks_cfg)),
    luacov_config = absolute(test_server_dir("build", "default", "test", "luacov.lua")),
    lua = interpreter()[1],
    lua_path = get_lua_path(test_dist_dir()),
    lua_cpath = get_lua_cpath(test_dist_dir()),
    lua_modules = absolute(test_dist_dir(base_server_lua_modules)),
  }

  local test_server_daemon_env = {
    background = true
  }

  local client_env = {
    environment = "main",
    component = "client",
    dist_dir = absolute(dist_dir()),
    public_files = base_client_public,
  }

  local test_client_env = {
    environment = "test",
    component = "client",
    dist_dir = absolute(test_dist_dir()),
    public_files = base_client_public,
  }

  pushindex(server_env, _G)
  tbl.merge(server_env, base_env, opts.config.env.server)

  pushindex(server_daemon_env, _G)
  tbl.merge(server_daemon_env, server_env)

  pushindex(test_server_env, _G)
  tbl.merge(test_server_env, base_env, opts.config.env.server)

  pushindex(test_server_daemon_env, _G)
  tbl.merge(test_server_daemon_env, test_server_env)

  pushindex(client_env, _G)
  tbl.merge(client_env, base_env, opts.config.env.client)

  pushindex(test_client_env, _G)
  tbl.merge(test_client_env, base_env, opts.config.env.client)

  opts.config.env.variable_prefix =
    opts.config.env.variable_prefix or
    supper((gsub(opts.config.env.name, "%W+", "_")))

  add_templated_target_base64(server_dir(base_server_run_sh),
    <% return squote(to_base64(readfile("res/web/run.sh"))) %>, server_env) -- luacheck: ignore

  add_templated_target_base64(test_server_dir(base_server_run_sh),
    <% return squote(to_base64(readfile("res/web/run.sh"))) %>, test_server_env) -- luacheck: ignore

  add_templated_target_base64(server_dir(base_server_nginx_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.conf"))) %>, server_env, -- luacheck: ignore
    { server_dir(base_server_lua_modules_ok) })

  add_templated_target_base64(test_server_dir(base_server_nginx_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.conf"))) %>, test_server_env, -- luacheck: ignore
    { test_server_dir(base_server_lua_modules_ok),
      test_server_dir(base_server_init_test_lua),
      test_server_dir(base_server_init_worker_test_lua) })

  add_templated_target_base64(server_dir(base_server_nginx_daemon_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.conf"))) %>, server_daemon_env, -- luacheck: ignore
    { server_dir(base_server_lua_modules_ok) })

  add_templated_target_base64(test_server_dir(base_server_nginx_daemon_cfg),
    <% return squote(to_base64(readfile("res/web/nginx.conf"))) %>, test_server_daemon_env, -- luacheck: ignore
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
    "profile", "skip_coverage"
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
    amap({ base_server_init_test_lua, base_server_init_worker_test_lua }, test_server_dir),
    amap({ "profile.flag", "skip_coverage.flag" }, work_dir))

  for fp in ivals(base_server_libs) do
    add_templated_target(server_dir_stripped(fp), fp, server_env)
  end

  for fp in ivals(base_server_libs) do
    add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
  end

  for fp in ivals(base_server_deps) do
    add_templated_target(server_dir_stripped(fp), fp, server_env)
  end

  for fp in ivals(base_server_deps) do
    add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
  end

  for fp in ivals(base_server_test_specs) do
    add_templated_target(test_server_dir_stripped(fp), fp, test_server_env)
  end

  for ddir, ddir_stripped, cdir, cdir_stripped, env in map(spread, ivals({
    { dist_dir_client, dist_dir_client_stripped, client_dir, client_dir_stripped, client_env },
    { test_dist_dir_client, test_dist_dir_client_stripped, test_client_dir, test_client_dir_stripped, test_client_env }
  })) do

    add_templated_target_base64(fs.join(cwd(), cdir(base_client_wrap_events_js)),
      <% return squote(to_base64(readfile("res/web/wrap_events.js"))) %>, env) -- luacheck: ignore

    for fp in ivals(base_client_assets) do
      add_copied_target(ddir_stripped(fp), fp)
    end

    for fp in ivals(base_client_static) do
      add_templated_target(cdir(fp), fp, env)
      add_copied_target(ddir_stripped(fp), cdir(fp))
    end

    for fp in ivals(base_client_deps) do
      add_copied_target(cdir_stripped(fp), fp)
    end

    for fp in ivals(base_client_libs) do
      add_copied_target(cdir_stripped(fp), fp)
    end

    for fp in ivals(base_client_bins) do
      add_copied_target(cdir_stripped(fp), fp)
    end

    for fp in ivals(base_client_res) do
      add_copied_target(cdir_stripped(fp), fp)
    end

    for fp in ivals(base_client_res_templated) do
      add_templated_target(cdir_stripped("build", "default-wasm", "build", fp), fp, env)
    end

    if fs.exists("client/spa") then
      add_copied_target_base64(fs.join(cwd(), cdir(base_client_spa_index_lua)), "PCUKICBmcyA9IHJlcXVpcmUoInNhbnRva3UuZnMiKQogIGl0ID0gcmVxdWlyZSgic2FudG9rdS5pdGVyIikKICBhcnIgPSByZXF1aXJlKCJzYW50b2t1LmFycmF5IikKICBzdHIgPSByZXF1aXJlKCJzYW50b2t1LnN0cmluZyIpCiU+Cgo8JSBwdXNoKGFwcC50cmFjZSkgJT4KcmVxdWlyZSgic2FudG9rdS53ZWIudHJhY2UuaW5kZXgiKSgiPCUgcmV0dXJuIGFwcC50cmFjZV91cmwgJT4iLCB7IG5hbWUgPSAibWFpbiIgfSwgZnVuY3Rpb24gKCkKPCUgcG9wKCkgJT4KCiAgbG9jYWwgZXJyID0gcmVxdWlyZSgic2FudG9rdS5lcnJvciIpCiAgbG9jYWwgZXJyb3IgPSBlcnIuZXJyb3IKCiAgbG9jYWwganMgPSByZXF1aXJlKCJzYW50b2t1LndlYi5qcyIpCiAgbG9jYWwgc3RyID0gcmVxdWlyZSgic2FudG9rdS5zdHJpbmciKQogIGxvY2FsIGl0ID0gcmVxdWlyZSgic2FudG9rdS5pdGVyIikKICBsb2NhbCBhcnIgPSByZXF1aXJlKCJzYW50b2t1LmFycmF5IikKICBsb2NhbCB1dGlsID0gcmVxdWlyZSgic2FudG9rdS53ZWIudXRpbCIpCiAgbG9jYWwgd3JwYyA9IHJlcXVpcmUoInNhbnRva3Uud2ViLndvcmtlci5ycGMuY2xpZW50IikKCiAgbG9jYWwgc2NyaXB0cyA9IHsKICAgIDwlCiAgICAgIGxvY2FsIHZpZXdkaXIgPSBmcy5qb2luKCJjbGllbnQvc3BhIiwgc3BhX25hbWUpIC4uICIvIgogICAgICBpZiBmcy5leGlzdHModmlld2RpcikgdGhlbgogICAgICAgIHJldHVybiBhcnIuY29uY2F0KGl0LmNvbGxlY3QoaXQubWFwKGZ1bmN0aW9uIChmcCkKICAgICAgICAgIGZwID0gc3RyLnN0cmlwcHJlZml4KGZwLCB2aWV3ZGlyKQogICAgICAgICAgZnAgPSBmcy5zdHJpcGV4dGVuc2lvbihmcCkKICAgICAgICAgIGZwID0gZnA6Z3N1YigiLysiLCAiLiIpCiAgICAgICAgICByZXR1cm4gYXJyLmNvbmNhdCh7ICJbIiwgc3RyLnF1b3RlKGZwKSwgIl0gPSByZXF1aXJlKFwiIiwgYXBwLm5hbWUsICIuIiwgZnAsICJcIikiIH0pCiAgICAgICAgZW5kLCBpdC5maWx0ZXIoZnVuY3Rpb24gKGZwKQogICAgICAgICAgcmV0dXJuIHN0ci5lbmRzd2l0aChmcCwgIi5odG1sIikKICAgICAgICBlbmQsIGZzLmZpbGVzKHZpZXdkaXIpKSkpLCAiLFxuIikKICAgICAgZW5kCiAgICAlPgogIH0KCiAgbG9jYWwgd2luZG93ID0ganMud2luZG93CiAgbG9jYWwgZG9jdW1lbnQgPSB3aW5kb3cuZG9jdW1lbnQKICBsb2NhbCBoaXN0b3J5ID0gd2luZG93Lmhpc3RvcnkKICBsb2NhbCBBcnJheSA9IGpzLkFycmF5CiAgbG9jYWwgTXV0YXRpb25PYnNlcnZlciA9IGpzLk11dGF0aW9uT2JzZXJ2ZXIKCiAgbG9jYWwgZV9oZWFkID0gZG9jdW1lbnQuaGVhZAogIGxvY2FsIGVfYm9keSA9IGRvY3VtZW50LmJvZHkKICBsb2NhbCB0X3JpcHBsZSA9IGVfaGVhZDpxdWVyeVNlbGVjdG9yKCJ0ZW1wbGF0ZS5yaXBwbGUiKQoKICBsb2NhbCBzdGFjayA9IHt9CiAgbG9jYWwgdXBkYXRlX3dvcmtlciA9IGZhbHNlCgogIGxvY2FsIE0gPSB7fQoKICBNLnNldHVwX3JpcHBsZSA9IGZ1bmN0aW9uIChlbCkKCiAgICBlbDphZGRFdmVudExpc3RlbmVyKCJtb3VzZWRvd24iLCBmdW5jdGlvbiAoXywgZXYpCgogICAgICBpZiBlbC5kaXNhYmxlZCB0aGVuCiAgICAgICAgcmV0dXJuCiAgICAgIGVuZAoKICAgICAgZXY6c3RvcFByb3BhZ2F0aW9uKCkKICAgICAgZXY6cHJldmVudERlZmF1bHQoKQoKICAgICAgbG9jYWwgZV9yaXBwbGUgPSB1dGlsLmNsb25lKHRfcmlwcGxlKQoKICAgICAgZV9yaXBwbGU6YWRkRXZlbnRMaXN0ZW5lcigiYW5pbWF0aW9uZW5kIiwgZnVuY3Rpb24gKCkKICAgICAgICBlX3JpcHBsZTpyZW1vdmUoKQogICAgICBlbmQpCgogICAgICBsb2NhbCBlX3dhdmUgPSBlX3JpcHBsZTpxdWVyeVNlbGVjdG9yKCIucmlwcGxlLXdhdmUiKQogICAgICBsb2NhbCBkaWEgPSBtYXRoLm1pbihlbC5vZmZzZXRIZWlnaHQsIGVsLm9mZnNldFdpZHRoLCAxMDApCgogICAgICBlX3dhdmUuc3R5bGUud2lkdGggPSBkaWEgLi4gInB4IgogICAgICBlX3dhdmUuc3R5bGUuaGVpZ2h0ID0gZGlhIC4uICJweCIKICAgICAgZV93YXZlLnN0eWxlLmxlZnQgPSAoZXYub2Zmc2V0WCAtIGRpYSAvIDIpIC4uICJweCIKICAgICAgZV93YXZlLnN0eWxlLnRvcCA9IChldi5vZmZzZXRZIC0gZGlhIC8gMikgLi4gInB4IgoKICAgICAgZWw6YXBwZW5kKGVfcmlwcGxlKQoKICAgIGVuZCkKCiAgZW5kCgogIC0tIFRPRE86IHRoZXJlIG11c3QgYmUgYSBiZXR0ZXIgd2F5IHRvIGRvIHRoaXMKICBNLnNldHVwX29ic2VydmVyID0gZnVuY3Rpb24gKHZpZXcpCgogICAgbG9jYWwgb2xkX2NsYXNzZXMgPSBpdC5yZWR1Y2UoZnVuY3Rpb24gKGEsIG4pCiAgICAgIGFbbl0gPSB0cnVlCiAgICAgIHJldHVybiBhCiAgICBlbmQsIHt9LCBpdC5tYXAoc3RyLnN1Yiwgc3RyLm1hdGNoKHZpZXcuZWwuY2xhc3NOYW1lLCAiW14lc10rIikpKQoKICAgIHZpZXcub2JzZXJ2ZXIgPSBNdXRhdGlvbk9ic2VydmVyOm5ldyhmdW5jdGlvbiAoXywgbXV0YXRpb25zKQoKICAgICAgcmV0dXJuIG11dGF0aW9uczpmb3JFYWNoKGZ1bmN0aW9uIChfLCBtdSkKCiAgICAgICAgbG9jYWwgcmVjcyA9IHZpZXcub2JzZXJ2ZXI6dGFrZVJlY29yZHMoKQoKICAgICAgICByZWNzOnB1c2gobXUpCgogICAgICAgIGlmIG5vdCByZWNzOmZpbmQoZnVuY3Rpb24gKF8sIG11KQogICAgICAgICAgcmV0dXJuIG11WyJ0eXBlIl0gPT0gImF0dHJpYnV0ZXMiIGFuZCBtdS5hdHRyaWJ1dGVOYW1lID09ICJjbGFzcyIKICAgICAgICBlbmQpIHRoZW4KICAgICAgICAgIHJldHVybgogICAgICAgIGVuZAoKICAgICAgICBsb2NhbCBmYWJzID0gZmFsc2UKICAgICAgICBsb2NhbCBzbmFja3MgPSBmYWxzZQoKICAgICAgICB2aWV3LmVsLmNsYXNzTGlzdDpmb3JFYWNoKGZ1bmN0aW9uIChfLCBjKQogICAgICAgICAgaWYgbm90IG9sZF9jbGFzc2VzW2NdIHRoZW4KICAgICAgICAgICAgaWYgdmlldy5mYWJfb2JzZXJ2ZWRfY2xhc3Nlc1tjXSB0aGVuCiAgICAgICAgICAgICAgZmFicyA9IHRydWUKICAgICAgICAgICAgZW5kCiAgICAgICAgICAgIGlmIHZpZXcuc25hY2tfb2JzZXJ2ZWRfY2xhc3Nlc1tjXSB0aGVuCiAgICAgICAgICAgICAgc25hY2tzID0gdHJ1ZQogICAgICAgICAgICBlbmQKICAgICAgICAgIGVuZAogICAgICAgIGVuZCkKCiAgICAgICAgZm9yIGMgaW4gaXQua2V5cyhvbGRfY2xhc3NlcykgZG8KICAgICAgICAgIGlmIG5vdCB2aWV3LmVsLmNsYXNzTGlzdDpjb250YWlucyhjKSB0aGVuCiAgICAgICAgICAgIGlmIHZpZXcuZmFiX29ic2VydmVkX2NsYXNzZXNbY10gdGhlbgogICAgICAgICAgICAgIGZhYnMgPSB0cnVlCiAgICAgICAgICAgIGVuZAogICAgICAgICAgICBpZiB2aWV3LnNuYWNrX29ic2VydmVkX2NsYXNzZXNbY10gdGhlbgogICAgICAgICAgICAgIHNuYWNrcyA9IHRydWUKICAgICAgICAgICAgZW5kCiAgICAgICAgICBlbmQKICAgICAgICBlbmQKCiAgICAgICAgb2xkX2NsYXNzZXMgPSBpdC5yZWR1Y2UoZnVuY3Rpb24gKGEsIG4pCiAgICAgICAgICBhW25dID0gdHJ1ZQogICAgICAgICAgcmV0dXJuIGEKICAgICAgICBlbmQsIHt9LCBpdC5tYXAoc3RyLnN1Yiwgc3RyLm1hdGNoKHZpZXcuZWwuY2xhc3NOYW1lIG9yICIiLCAiW14lc10rIikpKQoKICAgICAgICBpZiBmYWJzIHRoZW4KICAgICAgICAgIE0uc3R5bGVfZmFicyh2aWV3LCB0cnVlKQogICAgICAgIGVuZAoKICAgICAgICBpZiBzbmFja3MgdGhlbgogICAgICAgICAgTS5zdHlsZV9zbmFja3ModmlldywgdHJ1ZSkKICAgICAgICBlbmQKCiAgICAgIGVuZCkKCiAgICBlbmQpCgogICAgdmlldy5vYnNlcnZlcjpvYnNlcnZlKHZpZXcuZWwsIHsKICAgICAgYXR0cmlidXRlcyA9IHRydWUsCiAgICAgIGF0dHJpYnV0ZUZpbHRlciA9IHsgImNsYXNzIiB9CiAgICB9KQoKICBlbmQKCiAgTS5zZXR1cF9mYWJzID0gZnVuY3Rpb24gKG5leHRfdmlldywgbGFzdF92aWV3KQoKICAgIG5leHRfdmlldy5lX2ZhYnMgPSBuZXh0X3ZpZXcuZWw6cXVlcnlTZWxlY3RvckFsbCgiLnBhZ2UgPiAuZmFiIikKCiAgICBuZXh0X3ZpZXcuZV9mYWJzX3NoYXJlZCA9IHt9CiAgICBuZXh0X3ZpZXcuZV9mYWJzX3RvcCA9IHt9CiAgICBuZXh0X3ZpZXcuZV9mYWJzX2JvdHRvbSA9IHt9CiAgICBuZXh0X3ZpZXcuZmFiX29ic2VydmVkX2NsYXNzZXMgPSB7fQoKICAgIGZvciBpID0gMCwgbmV4dF92aWV3LmVfZmFicy5sZW5ndGggLSAxIGRvCgogICAgICBsb2NhbCBlbCA9IG5leHRfdmlldy5lX2ZhYnM6aXRlbShpKQoKICAgICAgZm9yIGMgaW4gaXQubWFwKHN0ci5zdWIsIHN0ci5tYXRjaChlbC5kYXRhc2V0LmhpZGUgb3IgIiIsICJbXiVzXSsiKSkgZG8KICAgICAgICBuZXh0X3ZpZXcuZmFiX29ic2VydmVkX2NsYXNzZXNbY10gPSB0cnVlCiAgICAgIGVuZAoKICAgICAgZm9yIGMgaW4gaXQubWFwKHN0ci5zdWIsIHN0ci5tYXRjaChlbC5kYXRhc2V0LnNob3cgb3IgIiIsICJbXiVzXSsiKSkgZG8KICAgICAgICBuZXh0X3ZpZXcuZmFiX29ic2VydmVkX2NsYXNzZXNbY10gPSB0cnVlCiAgICAgIGVuZAoKICAgICAgaWYgZWwuY2xhc3NMaXN0OmNvbnRhaW5zKCJtaW5tYXgiKSB0aGVuCiAgICAgICAgbmV4dF92aWV3LmVfbWlubWF4ID0gZWwKICAgICAgZW5kCgogICAgICBpZiBub3QgZWwuY2xhc3NMaXN0OmNvbnRhaW5zKCJzbWFsbCIpIGFuZAogICAgICAgIGxhc3RfdmlldyBhbmQgbGFzdF92aWV3LmVsOnF1ZXJ5U2VsZWN0b3JBbGwoIi5wYWdlID4gLmZhYjpub3QoLnNtYWxsKSIpCiAgICAgIHRoZW4KICAgICAgICBhcnIucHVzaChuZXh0X3ZpZXcuZV9mYWJzX3NoYXJlZCwgZWwpCiAgICAgIGVsc2VpZiBlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInRvcCIpIHRoZW4KICAgICAgICBhcnIucHVzaChuZXh0X3ZpZXcuZV9mYWJzX3RvcCwgZWwpCiAgICAgIGVsc2UKICAgICAgICBhcnIucHVzaChuZXh0X3ZpZXcuZV9mYWJzX2JvdHRvbSwgZWwpCiAgICAgIGVuZAoKICAgIGVuZAoKICAgIGFyci5yZXZlcnNlKG5leHRfdmlldy5lX2ZhYnNfYm90dG9tKQoKICBlbmQKCiAgTS5zZXR1cF9zbmFja3MgPSBmdW5jdGlvbiAobmV4dF92aWV3KQoKICAgIG5leHRfdmlldy5lX3NuYWNrcyA9IG5leHRfdmlldy5lbDpxdWVyeVNlbGVjdG9yQWxsKCIucGFnZSA+IC5zbmFjayIpCiAgICBuZXh0X3ZpZXcuc25hY2tfb2JzZXJ2ZWRfY2xhc3NlcyA9IHt9CgogICAgZm9yIGkgPSAwLCBuZXh0X3ZpZXcuZV9zbmFja3MubGVuZ3RoIC0gMSBkbwoKICAgICAgbG9jYWwgZWwgPSBuZXh0X3ZpZXcuZV9zbmFja3M6aXRlbShpKQoKICAgICAgZm9yIGMgaW4gaXQubWFwKHN0ci5zdWIsIHN0ci5tYXRjaChlbC5kYXRhc2V0LmhpZGUgb3IgIiIsICJbXiVzXSsiKSkgZG8KICAgICAgICBuZXh0X3ZpZXcuc25hY2tfb2JzZXJ2ZWRfY2xhc3Nlc1tjXSA9IHRydWUKICAgICAgZW5kCgogICAgICBmb3IgYyBpbiBpdC5tYXAoc3RyLnN1Yiwgc3RyLm1hdGNoKGVsLmRhdGFzZXQuc2hvdyBvciAiIiwgIlteJXNdKyIpKSBkbwogICAgICAgIG5leHRfdmlldy5zbmFja19vYnNlcnZlZF9jbGFzc2VzW2NdID0gdHJ1ZQogICAgICBlbmQKCiAgICBlbmQKCiAgZW5kCgogIC0tIFRPRE86IEN1cnJlbnRseSB0aGlzIGZpZ3VyZXMgb3V0IGhvdyBtYW55CiAgLS0gYnV0dG9ucyBhcmUgb24gZWl0aGVyIHNpZGUgb2YgdGhlIHRpdGxlLAogIC0tIGFuZCBzZXRzIHRoZSB0aXRsZSB3aWR0aCBzdWNoIHRoYXQgaXQKICAtLSBkb2Vzbid0IG92ZXJsYXAgdGhlIHNpZGUgd2l0aCB0aGUgbW9zdAogIC0tIGJ1dHRvbnMuIFRoZSBwcm9ibGVtIGlzIHRoYXQgaWYgb25lIHNpZGUKICAtLSBoYXMgYSBidXR0b24gYW5kIHRoZSBvdGhlciBkb2VzbnQsIGFuZCB0aGUKICAtLSB0aXRsZSBpcyBsb25nIGVub3VnaCB0byBvdmVybGFwLCBpdAogIC0tIGNvbmZ1c2luZ2x5IGdldHMgY3V0IG9mZiBvbiB0aGUgc2lkZQogIC0tIHdpdGhvdXQgYnV0dG9ucywgd2hlbiBpZGVhbGx5IGl0IHNob3VsZAogIC0tIG9ubHkgYmUgZ2V0dGluZyBjdXQgb2ZmIGJ5IHRoZSBidXR0b25zLiBXZQogIC0tIG5lZWQgc29tZSBzb3J0IG9mIGFkYXB0aXZlIGNlbnRlcmluZyBhcyB0aGUKICAtLSB1c2VyIHR5cGVzIGludG8gdGhlIHRpdGxlIGlucHV0IG9yIGJhc2VkIG9uCiAgLS0gdGhlIGFjdHVhbCBkaXNwbGF5ZWQgbGVuZ3RoLgogIE0uc2V0dXBfaGVhZGVyX3RpdGxlX3dpZHRoID0gZnVuY3Rpb24gKHZpZXcpCgogICAgaWYgbm90IHZpZXcuZV9oZWFkZXIgdGhlbgogICAgICByZXR1cm4KICAgIGVuZAoKICAgIGxvY2FsIGVfdGl0bGUgPSB2aWV3LmVfaGVhZGVyOnF1ZXJ5U2VsZWN0b3IoIi5oZWFkZXIgPiAudGl0bGUiKQoKICAgIGlmIG5vdCBlX3RpdGxlIHRoZW4KICAgICAgcmV0dXJuCiAgICBlbmQKCiAgICBsb2NhbCBvZmZzZXRfbGVmdCA9IDAKICAgIGxvY2FsIG9mZnNldF9yaWdodCA9IDAKCiAgICBsb2NhbCBsZWZ0aW5nID0gdHJ1ZQoKICAgIEFycmF5OmZyb20odmlldy5lX2hlYWRlci5jaGlsZHJlbik6Zm9yRWFjaChmdW5jdGlvbiAoXywgZWwpCgogICAgICBpZiBlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInRpdGxlIikgdGhlbgogICAgICAgIHJldHVybgogICAgICBlbmQKCiAgICAgIGlmIGxlZnRpbmcgYW5kIGVsLmNsYXNzTGlzdDpjb250YWlucygicmlnaHQiKSB0aGVuCiAgICAgICAgbGVmdGluZyA9IGZhbHNlCiAgICAgIGVuZAoKICAgICAgaWYgbGVmdGluZyB0aGVuCiAgICAgICAgb2Zmc2V0X2xlZnQgPSBvZmZzZXRfbGVmdCArIDwlIHJldHVybiBhcHAuaGVhZGVyX2hlaWdodCAlPgogICAgICBlbHNlCiAgICAgICAgb2Zmc2V0X3JpZ2h0ID0gb2Zmc2V0X3JpZ2h0ICsgPCUgcmV0dXJuIGFwcC5oZWFkZXJfaGVpZ2h0ICU+CiAgICAgIGVuZAoKICAgIGVuZCkKCiAgICBsb2NhbCBzaHJpbmsgPSBtYXRoLm1heChvZmZzZXRfbGVmdCwgb2Zmc2V0X3JpZ2h0KSAqIDIKICAgIGxvY2FsIHdpZHRoID0gImNhbGMoMTAwdncgLSAiIC4uIHNocmluayAuLiAicHgpIgoKICAgIGVfdGl0bGUuc3R5bGUud2lkdGggPSB3aWR0aAoKICBlbmQKCiAgTS5zdHlsZV9tYXhpbWl6ZWQgPSBmdW5jdGlvbiAodmlldywgYW5pbWF0ZSkKCiAgICBpZiB2aWV3Lm1heGltaXplZCA9PSBuaWwgdGhlbgogICAgICB2aWV3Lm1heGltaXplZCA9IGZhbHNlCiAgICBlbmQKCiAgICB2aWV3Lm1heGltaXplZCA9IG5vdCB2aWV3Lm1heGltaXplZAoKICAgIGlmIHZpZXcubWF4aW1pemVkIHRoZW4KICAgICAgdmlldy5lbC5jbGFzc0xpc3Q6YWRkKCJtYXhpbWl6ZWQiKQogICAgICB2aWV3LmhlYWRlcl9vZmZzZXQgPSB2aWV3LmhlYWRlcl9vZmZzZXQgLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4KICAgICAgdmlldy5tYWluX29mZnNldCA9IHZpZXcubWFpbl9vZmZzZXQgLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4KICAgICAgdmlldy5mYWJzX3RvcF9vZmZzZXQgPSAodmlldy5mYWJzX3RvcF9vZmZzZXQgb3IgMCkgLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4KICAgICAgdmlldy5zbmFja19vZmZzZXQgPSB2aWV3LnNuYWNrX29mZnNldCArIDwlIHJldHVybiBhcHAuaGVhZGVyX2hlaWdodCAlPgogICAgICB2aWV3LnNuYWNrX29wYWNpdHkgPSAwCiAgICBlbHNlCiAgICAgIHZpZXcuZWwuY2xhc3NMaXN0OnJlbW92ZSgibWF4aW1pemVkIikKICAgICAgdmlldy5oZWFkZXJfb2Zmc2V0ID0gdmlldy5oZWFkZXJfb2Zmc2V0ICsgPCUgcmV0dXJuIGFwcC5oZWFkZXJfaGVpZ2h0ICU+CiAgICAgIHZpZXcubWFpbl9vZmZzZXQgPSB2aWV3Lm1haW5fb2Zmc2V0ICsgPCUgcmV0dXJuIGFwcC5oZWFkZXJfaGVpZ2h0ICU+CiAgICAgIHZpZXcuZmFic190b3Bfb2Zmc2V0ID0gKHZpZXcuZmFic190b3Bfb2Zmc2V0IG9yIDApICsgPCUgcmV0dXJuIGFwcC5oZWFkZXJfaGVpZ2h0ICU+CiAgICAgIHZpZXcuc25hY2tfb2Zmc2V0ID0gdmlldy5zbmFja19vZmZzZXQgLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4KICAgICAgdmlldy5zbmFja19vcGFjaXR5ID0gMQogICAgZW5kCgogICAgTS5zdHlsZV9oZWFkZXIodmlldywgYW5pbWF0ZSkKICAgIE0uc3R5bGVfbWFpbih2aWV3LCBhbmltYXRlKQogICAgTS5zdHlsZV9mYWJzKHZpZXcsIGFuaW1hdGUpCiAgICBNLnN0eWxlX3NuYWNrcyh2aWV3LCBhbmltYXRlKQoKICBlbmQKCiAgTS5zZXR1cF9tYXhpbWl6ZSA9IGZ1bmN0aW9uIChuZXh0X3ZpZXcpCgogICAgaWYgbm90IG5leHRfdmlldy5lX21pbm1heCB0aGVuCiAgICAgIHJldHVybgogICAgZW5kCgogICAgaWYgbmV4dF92aWV3LmVfaGVhZGVyIHRoZW4KICAgICAgbmV4dF92aWV3LmVfaGVhZGVyLmNsYXNzTGlzdDphZGQoIm5vaGlkZSIpCiAgICBlbmQKCiAgICBuZXh0X3ZpZXcuZV9taW5tYXg6YWRkRXZlbnRMaXN0ZW5lcigiY2xpY2siLCBmdW5jdGlvbiAoKQogICAgICBNLnN0eWxlX21heGltaXplZChuZXh0X3ZpZXcsIHRydWUpCiAgICBlbmQpCgogIGVuZAoKICBNLnNldHVwX3JpcHBsZXMgPSBmdW5jdGlvbiAoZWwpCgogICAgZWw6cXVlcnlTZWxlY3RvckFsbCgiLmJ1dHRvbjpub3QoLm5vcmlwcGxlKSIpCiAgICAgIDpmb3JFYWNoKGZ1bmN0aW9uIChfLCBlbCkKICAgICAgICBNLnNldHVwX3JpcHBsZShlbCkKICAgICAgZW5kKQoKICAgIGVsOnF1ZXJ5U2VsZWN0b3JBbGwoIi5yaXBwbGUiKQogICAgICA6Zm9yRWFjaChmdW5jdGlvbiAoXywgZWwpCiAgICAgICAgaWYgZWwgfj0gdF9yaXBwbGUgdGhlbgogICAgICAgICAgTS5zZXR1cF9yaXBwbGUoZWwpCiAgICAgICAgZW5kCiAgICAgIGVuZCkKCiAgZW5kCgogIE0uZ2V0X2Jhc2VfbWFpbl9vZmZzZXQgPSBmdW5jdGlvbiAodmlldykKICAgIHJldHVybiAodXBkYXRlX3dvcmtlciBhbmQgPCUgcmV0dXJuIGFwcC5iYW5uZXJfaGVpZ2h0ICU+IG9yIDApICsKICAgICAgICAgICAodmlldy5tYXhpbWl6ZWQgYW5kICgtIDwlIHJldHVybiBhcHAuaGVhZGVyX2hlaWdodCAlPikgb3IgMCkKICBlbmQKCiAgTS5nZXRfYmFzZV9oZWFkZXJfb2Zmc2V0ID0gZnVuY3Rpb24gKHZpZXcpCiAgICByZXR1cm4gKHVwZGF0ZV93b3JrZXIgYW5kIDwlIHJldHVybiBhcHAuYmFubmVyX2hlaWdodCAlPiBvciAwKSArCiAgICAgICAgICAgKHZpZXcubWF4aW1pemVkIGFuZCAoLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4pIG9yIDApCiAgZW5kCgogIE0uZ2V0X2Jhc2VfZmFic190b3Bfb2Zmc2V0ID0gZnVuY3Rpb24gKHZpZXcpCiAgICByZXR1cm4gKHVwZGF0ZV93b3JrZXIgYW5kIDwlIHJldHVybiBhcHAuYmFubmVyX2hlaWdodCAlPiBvciAwKSArCiAgICAgICAgICAgKHZpZXcubWF4aW1pemVkIGFuZCAoLSA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4pIG9yIDApCiAgZW5kCgogIE0uZ2V0X2Jhc2Vfc25hY2tfb2Zmc2V0ID0gZnVuY3Rpb24gKHZpZXcpCiAgICByZXR1cm4gKHZpZXcubWF4aW1pemVkIGFuZCA8JSByZXR1cm4gYXBwLmhlYWRlcl9oZWlnaHQgJT4gb3IgMCkKICBlbmQKCiAgTS5zaG91bGRfc2hvdyA9IGZ1bmN0aW9uICh2aWV3LCBlbCkKCiAgICBsb2NhbCBoaWRlcyA9IGl0LmNvbGxlY3QoaXQubWFwKHN0ci5zdWIsIHN0ci5tYXRjaChlbC5kYXRhc2V0LmhpZGUgb3IgIiIsICJbXiVzXSsiKSkpCgogICAgZm9yIGggaW4gaXQuaXZhbHMoaGlkZXMpIGRvCiAgICAgIGlmIHZpZXcuZWwuY2xhc3NMaXN0OmNvbnRhaW5zKGgpIHRoZW4KICAgICAgICByZXR1cm4gZmFsc2UKICAgICAgZW5kCiAgICBlbmQKCiAgICBsb2NhbCBzaG93cyA9IGl0LmNvbGxlY3QoaXQubWFwKHN0ci5zdWIsIHN0ci5tYXRjaChlbC5kYXRhc2V0LnNob3cgb3IgIiIsICJbXiVzXSsiKSkpCgogICAgaWYgI3Nob3dzID09IDAgdGhlbgogICAgICByZXR1cm4gdHJ1ZQogICAgZW5kCgogICAgZm9yIHMgaW4gaXQuaXZhbHMoc2hvd3MpIGRvCiAgICAgIGlmIHZpZXcuZWwuY2xhc3NMaXN0OmNvbnRhaW5zKHMpIHRoZW4KICAgICAgICByZXR1cm4gdHJ1ZQogICAgICBlbmQKICAgIGVuZAoKICAgIHJldHVybiBmYWxzZQoKICBlbmQKCiAgTS5zdHlsZV9oZWFkZXIgPSBmdW5jdGlvbiAodmlldywgYW5pbWF0ZSkKCiAgICBpZiBub3Qgdmlldy5lX2hlYWRlciB0aGVuCiAgICAgIHJldHVybgogICAgZW5kCgogICAgaWYgYW5pbWF0ZSB0aGVuCiAgICAgIHZpZXcuZV9oZWFkZXIuY2xhc3NMaXN0OmFkZCgiYW5pbWF0ZWQiKQogICAgICBpZiB2aWV3LmhlYWRlcl9hbmltYXRpb24gdGhlbgogICAgICAgIHdpbmRvdzpjbGVhclRpbWVvdXQodmlldy5oZWFkZXJfYW5pbWF0aW9uKQogICAgICAgIHZpZXcuaGVhZGVyX2FuaW1hdGlvbiA9IG5pbAogICAgICBlbmQKICAgICAgdmlldy5oZWFkZXJfYW5pbWF0aW9uID0gTS5hZnRlcl90cmFuc2l0aW9uKGZ1bmN0aW9uICgpCiAgICAgICAgdmlldy5lX2hlYWRlci5jbGFzc0xpc3Q6cmVtb3ZlKCJhbmltYXRlZCIpCiAgICAgICAgdmlldy5oZWFkZXJfYW5pbWF0aW9uID0gbmlsCiAgICAgIGVuZCkKICAgIGVuZAoKICAgIGlmIHZpZXcubGFzdF9zY3JvbGx5IHRoZW4KICAgICAgbG9jYWwgZGlmZiA9IHZpZXcubGFzdF9zY3JvbGx5IC0gdmlldy5jdXJyX3Njcm9sbHkKICAgICAgdmlldy5oZWFkZXJfb2Zmc2V0ID0gdmlldy5oZWFkZXJfb2Zmc2V0ICsgZGlmZgogICAgICBpZiBkaWZmID4gMCB0aGVuCiAgICAgICAgaWYgdmlldy5oZWFkZXJfb2Zmc2V0ID4gdmlldy5oZWFkZXJfbWF4IHRoZW4KICAgICAgICAgIHZpZXcuaGVhZGVyX29mZnNldCA9IHZpZXcuaGVhZGVyX21heAogICAgICAgIGVuZAogICAgICAgIHZpZXcuZV9oZWFkZXIuc3R5bGVbImJveC1zaGFkb3ciXSA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzIgJT4iCiAgICAgIGVsc2UKICAgICAgICBpZiB2aWV3LmhlYWRlcl9vZmZzZXQgPCB2aWV3LmhlYWRlcl9taW4gdGhlbgogICAgICAgICAgdmlldy5oZWFkZXJfb2Zmc2V0ID0gdmlldy5oZWFkZXJfbWluCiAgICAgICAgICBpZiBub3QgdXBkYXRlX3dvcmtlciB0aGVuCiAgICAgICAgICAgIHZpZXcuZV9oZWFkZXIuc3R5bGVbImJveC1zaGFkb3ciXSA9ICJub25lIgogICAgICAgICAgZW5kCiAgICAgICAgZW5kCiAgICAgIGVuZAogICAgZW5kCgogICAgdmlldy5lX2hlYWRlci5zdHlsZS50cmFuc2Zvcm0gPSAidHJhbnNsYXRlWSgiIC4uIHZpZXcuaGVhZGVyX29mZnNldCAuLiAicHgpIgogICAgdmlldy5lX2hlYWRlci5zdHlsZS5vcGFjaXR5ID0gdmlldy5oZWFkZXJfb3BhY2l0eQogICAgdmlldy5lX2hlYWRlci5zdHlsZVsiei1pbmRleCJdID0gdmlldy5oZWFkZXJfaW5kZXgKICAgIHZpZXcuZV9oZWFkZXIuc3R5bGVbImJveC1zaGFkb3ciXSA9IHZpZXcuaGVhZGVyX3NoYWRvdwoKICBlbmQKCiAgTS5zdHlsZV9tYWluID0gZnVuY3Rpb24gKHZpZXcsIGFuaW1hdGUpCgogICAgaWYgbm90IHZpZXcuZV9tYWluIHRoZW4KICAgICAgcmV0dXJuCiAgICBlbmQKCiAgICBpZiBhbmltYXRlIHRoZW4KICAgICAgdmlldy5lX21haW4uY2xhc3NMaXN0OmFkZCgiYW5pbWF0ZWQiKQogICAgICBpZiB2aWV3Lm1haW5fYW5pbWF0aW9uIHRoZW4KICAgICAgICB3aW5kb3c6Y2xlYXJUaW1lb3V0KHZpZXcubWFpbl9hbmltYXRpb24pCiAgICAgICAgdmlldy5tYWluX2FuaW1hdGlvbiA9IG5pbAogICAgICBlbmQKICAgICAgdmlldy5tYWluX2FuaW1hdGlvbiA9IE0uYWZ0ZXJfdHJhbnNpdGlvbihmdW5jdGlvbiAoKQogICAgICAgIHZpZXcuZV9tYWluLmNsYXNzTGlzdDpyZW1vdmUoImFuaW1hdGVkIikKICAgICAgICB2aWV3Lm1haW5fYW5pbWF0aW9uID0gbmlsCiAgICAgIGVuZCkKICAgIGVuZAoKICAgIHZpZXcuZV9tYWluLnN0eWxlLnRyYW5zZm9ybSA9ICJ0cmFuc2xhdGVZKCIgLi4gdmlldy5tYWluX29mZnNldCAuLiAicHgpIgogICAgdmlldy5lX21haW4uc3R5bGUub3BhY2l0eSA9IHZpZXcubWFpbl9vcGFjaXR5CiAgICB2aWV3LmVfbWFpbi5zdHlsZVsiei1pbmRleCJdID0gdmlldy5tYWluX2luZGV4CgogIGVuZAoKICBNLnN0eWxlX2ZhYnMgPSBmdW5jdGlvbiAodmlldywgYW5pbWF0ZSkKCiAgICBpZiB2aWV3LmVfZmFicy5sZW5ndGggPD0gMCB0aGVuCiAgICAgIHJldHVybgogICAgZW5kCgogICAgaWYgYW5pbWF0ZSB0aGVuCiAgICAgIHZpZXcuZV9mYWJzOmZvckVhY2goZnVuY3Rpb24gKF8sIGVfZmFiKQogICAgICAgIGVfZmFiLmNsYXNzTGlzdDphZGQoImFuaW1hdGVkIikKICAgICAgZW5kKQogICAgICBpZiB2aWV3LmZhYnNfYW5pbWF0aW9uIHRoZW4KICAgICAgICB3aW5kb3c6Y2xlYXJUaW1lb3V0KHZpZXcuZmFic19hbmltYXRpb24pCiAgICAgICAgdmlldy5mYWJzX2FuaW1hdGlvbiA9IG5pbAogICAgICBlbmQKICAgICAgdmlldy5mYWJzX2FuaW1hdGlvbiA9IE0uYWZ0ZXJfdHJhbnNpdGlvbihmdW5jdGlvbiAoKQogICAgICAgIHZpZXcuZV9mYWJzOmZvckVhY2goZnVuY3Rpb24gKF8sIGVfZmFiKQogICAgICAgICAgZV9mYWIuY2xhc3NMaXN0OnJlbW92ZSgiYW5pbWF0ZWQiKQogICAgICAgIGVuZCkKICAgICAgICB2aWV3LmZhYnNfYW5pbWF0aW9uID0gbmlsCiAgICAgIGVuZCkKICAgIGVuZAoKICAgIGxvY2FsIGJvdHRvbV9vZmZzZXRfdG90YWwgPSAwCiAgICBsb2NhbCB0b3Bfb2Zmc2V0X3RvdGFsID0gMAoKICAgIGFyci5lYWNoKHZpZXcuZV9mYWJzX3NoYXJlZCwgZnVuY3Rpb24gKGVsKQoKICAgICAgZWwuc3R5bGVbInotaW5kZXgiXSA9IHZpZXcuZmFiX3NoYXJlZF9pbmRleAoKICAgICAgaWYgbm90IE0uc2hvdWxkX3Nob3codmlldywgZWwpIHRoZW4KICAgICAgICBlbC5zdHlsZS5vcGFjaXR5ID0gMAogICAgICAgIGVsLnN0eWxlWyJib3gtc2hhZG93Il0gPSB2aWV3LmZhYl9zaGFyZWRfc2hhZG93CiAgICAgICAgZWwuc3R5bGVbInBvaW50ZXItZXZlbnRzIl0gPSAibm9uZSIKICAgICAgICBlbC5zdHlsZS50cmFuc2Zvcm0gPQogICAgICAgICAgInNjYWxlKDAuNzUpICIgLi4KICAgICAgICAgICJ0cmFuc2xhdGVZKCIgLi4gdmlldy5mYWJfc2hhcmVkX29mZnNldCAuLiAicHgpIgogICAgICAgIHJldHVybgogICAgICBlbmQKCiAgICAgIGxvY2FsIGVfc3ZnID0gZWw6cXVlcnlTZWxlY3Rvcigic3ZnIikKCiAgICAgIGVsLnN0eWxlWyJ6LWluZGV4Il0gPSB2aWV3LmZhYl9zaGFyZWRfaW5kZXgKICAgICAgZWwuc3R5bGUub3BhY2l0eSA9IHZpZXcuZmFiX3NoYXJlZF9vcGFjaXR5CiAgICAgIGVsLnN0eWxlWyJwb2ludGVyLWV2ZW50cyJdID0gImFsbCIKICAgICAgZWwuc3R5bGVbImJveC1zaGFkb3ciXSA9IHZpZXcuZmFiX3NoYXJlZF9zaGFkb3cKCiAgICAgIGVsLnN0eWxlLnRyYW5zZm9ybSA9CiAgICAgICAgInNjYWxlKCIgLi4gdmlldy5mYWJfc2hhcmVkX3NjYWxlIC4uICIpICIgLi4KICAgICAgICAgICJ0cmFuc2xhdGVZKCIgLi4gdmlldy5mYWJfc2hhcmVkX29mZnNldCAuLiAicHgpIgoKICAgICAgZV9zdmcuc3R5bGUudHJhbnNmb3JtID0KICAgICAgICAidHJhbnNsYXRlWSgiIC4uIHZpZXcuZmFiX3NoYXJlZF9zdmdfb2Zmc2V0IC4uICJweCkiCgogICAgICBpZiBlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInRvcCIpIHRoZW4KICAgICAgICB0b3Bfb2Zmc2V0X3RvdGFsID0gdG9wX29mZnNldF90b3RhbCArCiAgICAgICAgICAoZWwuY2xhc3NMaXN0OmNvbnRhaW5zKCJzbWFsbCIpIGFuZAogICAgICAgICAgICA8JSByZXR1cm4gYXBwLmZhYl93aWR0aF9zbWFsbCAlPiBvcgogICAgICAgICAgICA8JSByZXR1cm4gYXBwLmZhYl93aWR0aF9sYXJnZSAlPikKICAgICAgZWxzZQogICAgICAgIGJvdHRvbV9vZmZzZXRfdG90YWwgPSBib3R0b21fb2Zmc2V0X3RvdGFsICsKICAgICAgICAgIChlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInNtYWxsIikgYW5kCiAgICAgICAgICAgIDwlIHJldHVybiBhcHAuZmFiX3dpZHRoX3NtYWxsICU+IG9yCiAgICAgICAgICAgIDwlIHJldHVybiBhcHAuZmFiX3dpZHRoX2xhcmdlICU+KQogICAgICBlbmQKCiAgICBlbmQpCgogICAgYXJyLmVhY2godmlldy5lX2ZhYnNfYm90dG9tLCBmdW5jdGlvbiAoZWwpCgogICAgICBlbC5zdHlsZVsiei1pbmRleCJdID0gdmlldy5mYWJzX2JvdHRvbV9pbmRleAoKICAgICAgaWYgbm90IE0uc2hvdWxkX3Nob3codmlldywgZWwpIHRoZW4KICAgICAgICBlbC5zdHlsZS5vcGFjaXR5ID0gMAogICAgICAgIGVsLnN0eWxlWyJwb2ludGVyLWV2ZW50cyJdID0gIm5vbmUiCiAgICAgICAgZWwuc3R5bGUudHJhbnNmb3JtID0KICAgICAgICAgICJzY2FsZSgwLjc1KSAiIC4uCiAgICAgICAgICAidHJhbnNsYXRlWSgiIC4uICh2aWV3LmZhYnNfYm90dG9tX29mZnNldCAtIGJvdHRvbV9vZmZzZXRfdG90YWwpIC4uICJweCkiCiAgICAgICAgcmV0dXJuCiAgICAgIGVuZAoKICAgICAgZWwuc3R5bGVbInBvaW50ZXItZXZlbnRzIl0gPSAiYWxsIgogICAgICBlbC5zdHlsZS5vcGFjaXR5ID0gdmlldy5mYWJzX2JvdHRvbV9vcGFjaXR5CiAgICAgIGVsLnN0eWxlLnRyYW5zZm9ybSA9CiAgICAgICAgInNjYWxlKCIgLi4gdmlldy5mYWJzX2JvdHRvbV9zY2FsZSAuLiAiKSAiIC4uCiAgICAgICAgInRyYW5zbGF0ZVkoIiAuLiAodmlldy5mYWJzX2JvdHRvbV9vZmZzZXQgLSBib3R0b21fb2Zmc2V0X3RvdGFsKSAuLiAicHgpIgoKICAgICAgYm90dG9tX29mZnNldF90b3RhbCA9IGJvdHRvbV9vZmZzZXRfdG90YWwgKwogICAgICAgIChlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInNtYWxsIikgYW5kCiAgICAgICAgICA8JSByZXR1cm4gYXBwLmZhYl93aWR0aF9zbWFsbCAlPiBvcgogICAgICAgICAgPCUgcmV0dXJuIGFwcC5mYWJfd2lkdGhfbGFyZ2UgJT4pICsgMTYKCiAgICBlbmQpCgogICAgYXJyLmVhY2godmlldy5lX2ZhYnNfdG9wLCBmdW5jdGlvbiAoZWwpCgogICAgICBlbC5zdHlsZVsiei1pbmRleCJdID0gdmlldy5mYWJzX3RvcF9pbmRleAoKICAgICAgaWYgbm90IE0uc2hvdWxkX3Nob3codmlldywgZWwpIHRoZW4KICAgICAgICBlbC5zdHlsZS5vcGFjaXR5ID0gMAogICAgICAgIGVsLnN0eWxlWyJwb2ludGVyLWV2ZW50cyJdID0gIm5vbmUiCiAgICAgICAgZWwuc3R5bGUudHJhbnNmb3JtID0KICAgICAgICAgICJzY2FsZSgwLjc1KSAiIC4uCiAgICAgICAgICAidHJhbnNsYXRlWSgiIC4uICh2aWV3LmZhYnNfdG9wX29mZnNldCAtIHRvcF9vZmZzZXRfdG90YWwpIC4uICJweCkiCiAgICAgICAgcmV0dXJuCiAgICAgIGVuZAoKICAgICAgZWwuc3R5bGVbInBvaW50ZXItZXZlbnRzIl0gPSAiYWxsIgogICAgICBlbC5zdHlsZS5vcGFjaXR5ID0gdmlldy5mYWJzX3RvcF9vcGFjaXR5CiAgICAgIGVsLnN0eWxlLnRyYW5zZm9ybSA9CiAgICAgICAgInNjYWxlKCIgLi4gdmlldy5mYWJzX3RvcF9zY2FsZSAuLiAiKSAiIC4uCiAgICAgICAgInRyYW5zbGF0ZVkoIiAuLiAodmlldy5mYWJzX3RvcF9vZmZzZXQgKyB0b3Bfb2Zmc2V0X3RvdGFsKSAuLiAicHgpIgoKICAgICAgdG9wX29mZnNldF90b3RhbCA9IHRvcF9vZmZzZXRfdG90YWwgKwogICAgICAgIChlbC5jbGFzc0xpc3Q6Y29udGFpbnMoInNtYWxsIikgYW5kCiAgICAgICAgICA8JSByZXR1cm4gYXBwLmZhYl93aWR0aF9zbWFsbCAlPiBvcgogICAgICAgICAgPCUgcmV0dXJuIGFwcC5mYWJfd2lkdGhfbGFyZ2UgJT4pICsgMTYKCiAgICBlbmQpCgogIGVuZAoKICBNLnN0eWxlX3NuYWNrcyA9IGZ1bmN0aW9uICh2aWV3LCBhbmltYXRlKQoKICAgIGlmIHZpZXcuZV9zbmFja3MubGVuZ3RoIDw9IDAgdGhlbgogICAgICByZXR1cm4KICAgIGVuZAoKICAgIGlmIGFuaW1hdGUgdGhlbgogICAgICB2aWV3LmVfc25hY2tzOmZvckVhY2goZnVuY3Rpb24gKF8sIGVfc25hY2spCiAgICAgICAgZV9zbmFjay5jbGFzc0xpc3Q6YWRkKCJhbmltYXRlZCIpCiAgICAgIGVuZCkKICAgICAgaWYgdmlldy5zbmFja19hbmltYXRpb24gdGhlbgogICAgICAgIHdpbmRvdzpjbGVhclRpbWVvdXQodmlldy5zbmFja19hbmltYXRpb24pCiAgICAgICAgdmlldy5zbmFja19hbmltYXRpb24gPSBuaWwKICAgICAgZW5kCiAgICAgIHZpZXcuc25hY2tfYW5pbWF0aW9uID0gTS5hZnRlcl90cmFuc2l0aW9uKGZ1bmN0aW9uICgpCiAgICAgICAgdmlldy5lX3NuYWNrczpmb3JFYWNoKGZ1bmN0aW9uIChfLCBlX3NuYWNrKQogICAgICAgICAgZV9zbmFjay5jbGFzc0xpc3Q6cmVtb3ZlKCJhbmltYXRlZCIpCiAgICAgICAgZW5kKQogICAgICAgIHZpZXcuc25hY2tfYW5pbWF0aW9uID0gbmlsCiAgICAgIGVuZCkKICAgIGVuZAoKICAgIGxvY2FsIGJvdHRvbV9vZmZzZXRfdG90YWwgPSAwCgogICAgdmlldy5lX3NuYWNrczpmb3JFYWNoKGZ1bmN0aW9uIChfLCBlX3NuYWNrKQogICAgICBlX3NuYWNrLnN0eWxlWyJ6LWluZGV4Il0gPSB2aWV3LnNuYWNrX2luZGV4CiAgICAgIGlmIG5vdCBNLnNob3VsZF9zaG93KHZpZXcsIGVfc25hY2spIHRoZW4KICAgICAgICBlX3NuYWNrLnN0eWxlLm9wYWNpdHkgPSAwCiAgICAgICAgZV9zbmFjay5zdHlsZVsicG9pbnRlci1ldmVudHMiXSA9ICJub25lIgogICAgICAgIGVfc25hY2suc3R5bGUudHJhbnNmb3JtID0KICAgICAgICAgICJ0cmFuc2xhdGVZKCIgLi4gKHZpZXcuc25hY2tfb2Zmc2V0IC0gYm90dG9tX29mZnNldF90b3RhbCkgLi4gInB4KSIKICAgICAgZWxzZQogICAgICAgIGVfc25hY2suc3R5bGUub3BhY2l0eSA9IHZpZXcuc25hY2tfb3BhY2l0eQogICAgICAgIGVfc25hY2suc3R5bGVbInBvaW50ZXItZXZlbnRzIl0gPSAodmlldy5zbmFja19vcGFjaXR5IG9yIDApID09IDAgYW5kICJub25lIiBvciAiYWxsIgogICAgICAgIGVfc25hY2suc3R5bGUudHJhbnNmb3JtID0KICAgICAgICAgICJ0cmFuc2xhdGVZKCIgLi4gKHZpZXcuc25hY2tfb2Zmc2V0IC0gYm90dG9tX29mZnNldF90b3RhbCkgLi4gInB4KSIKICAgICAgICBib3R0b21fb2Zmc2V0X3RvdGFsID0gYm90dG9tX29mZnNldF90b3RhbCArCiAgICAgICAgICAgIDwlIHJldHVybiBhcHAuc25hY2tfaGVpZ2h0ICU+ICsgMTYKICAgICAgZW5kCiAgICBlbmQpCgogIGVuZAoKICBNLnN0eWxlX2hlYWRlcl90cmFuc2l0aW9uID0gZnVuY3Rpb24gKG5leHRfdmlldywgdHJhbnNpdGlvbiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCgogICAgbmV4dF92aWV3LmhlYWRlcl9taW4gPSAtIDwlIHJldHVybiBhcHAuaGVhZGVyX2hlaWdodCAlPiArIE0uZ2V0X2Jhc2VfaGVhZGVyX29mZnNldChuZXh0X3ZpZXcpCiAgICBuZXh0X3ZpZXcuaGVhZGVyX21heCA9IE0uZ2V0X2Jhc2VfaGVhZGVyX29mZnNldChuZXh0X3ZpZXcpCgogICAgaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIHRoZW4KCiAgICAgIG5leHRfdmlldy5oZWFkZXJfb2Zmc2V0ID0gTS5nZXRfYmFzZV9oZWFkZXJfb2Zmc2V0KG5leHRfdmlldykKICAgICAgbmV4dF92aWV3LmhlYWRlcl9vcGFjaXR5ID0gMQogICAgICBuZXh0X3ZpZXcuaGVhZGVyX2luZGV4ID0gOTkKICAgICAgbmV4dF92aWV3LmhlYWRlcl9zaGFkb3cgPSAiPCUgcmV0dXJuIGFwcC5zaGFkb3cyICU+IgogICAgICBNLnN0eWxlX2hlYWRlcihuZXh0X3ZpZXcpCgogICAgZWxzZWlmIG5vdCBsYXN0X3ZpZXcgYW5kIHRyYW5zaXRpb24gPT0gImV4aXQiIHRoZW4KCiAgICAgIGVycm9yKCJpbnZhbGlkIHN0YXRlOiBoZWFkZXIgZXhpdCB0cmFuc2l0aW9uIHdpdGggbm8gbGFzdCB2aWV3IikKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIGFuZCBkaXJlY3Rpb24gPT0gImZvcndhcmQiIHRoZW4KCiAgICAgIG5leHRfdmlldy5oZWFkZXJfb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+ICsgTS5nZXRfYmFzZV9oZWFkZXJfb2Zmc2V0KG5leHRfdmlldykKICAgICAgbmV4dF92aWV3LmhlYWRlcl9vcGFjaXR5ID0gMAogICAgICBuZXh0X3ZpZXcuaGVhZGVyX2luZGV4ID0gOTkKICAgICAgbmV4dF92aWV3LmhlYWRlcl9zaGFkb3cgPSAiPCUgcmV0dXJuIGFwcC5zaGFkb3cyICU+IgogICAgICBNLnN0eWxlX2hlYWRlcihuZXh0X3ZpZXcpCgogICAgICBNLmFmdGVyX2ZyYW1lKGZ1bmN0aW9uICgpCiAgICAgICAgbmV4dF92aWV3LmhlYWRlcl9vZmZzZXQgPSBuZXh0X3ZpZXcuaGVhZGVyX29mZnNldCAtIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgogICAgICAgIG5leHRfdmlldy5oZWFkZXJfb3BhY2l0eSA9IDEKICAgICAgICBNLnN0eWxlX2hlYWRlcihuZXh0X3ZpZXcsIHRydWUpCiAgICAgIGVuZCkKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZXhpdCIgYW5kIGRpcmVjdGlvbiA9PSAiZm9yd2FyZCIgdGhlbgoKICAgICAgbGFzdF92aWV3LmhlYWRlcl9vZmZzZXQgPSBNLmdldF9iYXNlX2hlYWRlcl9vZmZzZXQobGFzdF92aWV3KSAtIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiAvIDIKICAgICAgbGFzdF92aWV3LmhlYWRlcl9vcGFjaXR5ID0gMQogICAgICBsYXN0X3ZpZXcuaGVhZGVyX2luZGV4ID0gOTcKICAgICAgbGFzdF92aWV3LmhlYWRlcl9zaGFkb3cgPSAiPCUgcmV0dXJuIGFwcC5zaGFkb3cyICU+IgogICAgICBNLnN0eWxlX2hlYWRlcihsYXN0X3ZpZXcsIHRydWUpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImVudGVyIiBhbmQgZGlyZWN0aW9uID09ICJiYWNrd2FyZCIgdGhlbgoKICAgICAgbmV4dF92aWV3LmhlYWRlcl9vZmZzZXQgPSBNLmdldF9iYXNlX2hlYWRlcl9vZmZzZXQobmV4dF92aWV3KSAtIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiAvIDIKICAgICAgbmV4dF92aWV3LmhlYWRlcl9vcGFjaXR5ID0gMQogICAgICBuZXh0X3ZpZXcuaGVhZGVyX2luZGV4ID0gOTcKICAgICAgbmV4dF92aWV3LmhlYWRlcl9zaGFkb3cgPSAiPCUgcmV0dXJuIGFwcC5zaGFkb3cyICU+IgogICAgICBNLnN0eWxlX2hlYWRlcihuZXh0X3ZpZXcpCgogICAgICBNLmFmdGVyX2ZyYW1lKGZ1bmN0aW9uICgpCiAgICAgICAgbmV4dF92aWV3LmhlYWRlcl9vZmZzZXQgPSBNLmdldF9iYXNlX2hlYWRlcl9vZmZzZXQobmV4dF92aWV3KQogICAgICAgIE0uc3R5bGVfaGVhZGVyKG5leHRfdmlldywgdHJ1ZSkKICAgICAgZW5kKQoKICAgIGVsc2VpZiB0cmFuc2l0aW9uID09ICJleGl0IiBhbmQgZGlyZWN0aW9uID09ICJiYWNrd2FyZCIgdGhlbgoKICAgICAgbGFzdF92aWV3LmhlYWRlcl9vZmZzZXQgPSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gKyBNLmdldF9iYXNlX2hlYWRlcl9vZmZzZXQobGFzdF92aWV3KQogICAgICBsYXN0X3ZpZXcuaGVhZGVyX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5oZWFkZXJfaW5kZXggPSA5OQogICAgICBsYXN0X3ZpZXcuaGVhZGVyX3NoYWRvdyA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzIgJT4iCiAgICAgIE0uc3R5bGVfaGVhZGVyKGxhc3RfdmlldywgdHJ1ZSkKCiAgICBlbHNlCgogICAgICBlcnJvcigiaW52YWxpZCBzdGF0ZTogaGVhZGVyIHRyYW5zaXRpb24iKQoKICAgIGVuZAoKICBlbmQKCiAgTS5zdHlsZV9tYWluX3RyYW5zaXRpb24gPSBmdW5jdGlvbiAobmV4dF92aWV3LCB0cmFuc2l0aW9uLCBkaXJlY3Rpb24sIGxhc3RfdmlldykKCiAgICBpZiBub3QgbGFzdF92aWV3IGFuZCB0cmFuc2l0aW9uID09ICJlbnRlciIgdGhlbgoKICAgICAgbmV4dF92aWV3Lm1haW5fb2Zmc2V0ID0gTS5nZXRfYmFzZV9tYWluX29mZnNldChuZXh0X3ZpZXcpCiAgICAgIG5leHRfdmlldy5tYWluX29wYWNpdHkgPSAxCiAgICAgIG5leHRfdmlldy5tYWluX2luZGV4ID0gOTYKICAgICAgTS5zdHlsZV9tYWluKG5leHRfdmlldykKCiAgICBlbHNlaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZXhpdCIgdGhlbgoKICAgICAgZXJyb3IoImludmFsaWQgc3RhdGU6IG1haW4gZXhpdCB0cmFuc2l0aW9uIHdpdGggbm8gbGFzdCB2aWV3IikKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIGFuZCBkaXJlY3Rpb24gPT0gImZvcndhcmQiIHRoZW4KCiAgICAgIG5leHRfdmlldy5tYWluX29mZnNldCA9IE0uZ2V0X2Jhc2VfbWFpbl9vZmZzZXQobmV4dF92aWV3KSArIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgogICAgICBuZXh0X3ZpZXcubWFpbl9vcGFjaXR5ID0gMAogICAgICBuZXh0X3ZpZXcubWFpbl9pbmRleCA9IDk4CiAgICAgIE0uc3R5bGVfbWFpbihuZXh0X3ZpZXcpCgogICAgICBNLmFmdGVyX2ZyYW1lKGZ1bmN0aW9uICgpCiAgICAgICAgbmV4dF92aWV3Lm1haW5fb2Zmc2V0ID0gbmV4dF92aWV3Lm1haW5fb2Zmc2V0IC0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+CiAgICAgICAgbmV4dF92aWV3Lm1haW5fb3BhY2l0eSA9IDEKICAgICAgICBNLnN0eWxlX21haW4obmV4dF92aWV3LCB0cnVlKQogICAgICBlbmQpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImV4aXQiIGFuZCBkaXJlY3Rpb24gPT0gImZvcndhcmQiIHRoZW4KCiAgICAgIGxhc3Rfdmlldy5tYWluX29mZnNldCA9IE0uZ2V0X2Jhc2VfbWFpbl9vZmZzZXQobGFzdF92aWV3KSAtIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiAvIDIKICAgICAgbGFzdF92aWV3Lm1haW5fb3BhY2l0eSA9IDEKICAgICAgbGFzdF92aWV3Lm1haW5faW5kZXggPSA5NgogICAgICBNLnN0eWxlX21haW4obGFzdF92aWV3LCB0cnVlKQoKICAgIGVsc2VpZiB0cmFuc2l0aW9uID09ICJlbnRlciIgYW5kIGRpcmVjdGlvbiA9PSAiYmFja3dhcmQiIHRoZW4KCiAgICAgIG5leHRfdmlldy5tYWluX29mZnNldCA9IE0uZ2V0X2Jhc2VfbWFpbl9vZmZzZXQobmV4dF92aWV3KSAgLSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gLyAyCiAgICAgIG5leHRfdmlldy5tYWluX29wYWNpdHkgPSAxCiAgICAgIG5leHRfdmlldy5tYWluX2luZGV4ID0gOTYKICAgICAgTS5zdHlsZV9tYWluKG5leHRfdmlldykKCiAgICAgIE0uYWZ0ZXJfZnJhbWUoZnVuY3Rpb24gKCkKICAgICAgICBuZXh0X3ZpZXcubWFpbl9vZmZzZXQgPSBNLmdldF9iYXNlX21haW5fb2Zmc2V0KG5leHRfdmlldykKICAgICAgICBNLnN0eWxlX21haW4obmV4dF92aWV3LCB0cnVlKQogICAgICBlbmQpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImV4aXQiIGFuZCBkaXJlY3Rpb24gPT0gImJhY2t3YXJkIiB0aGVuCgogICAgICBsYXN0X3ZpZXcubWFpbl9vZmZzZXQgPSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gKyBNLmdldF9iYXNlX21haW5fb2Zmc2V0KGxhc3RfdmlldykKICAgICAgbGFzdF92aWV3Lm1haW5fb3BhY2l0eSA9IDAKICAgICAgbGFzdF92aWV3Lm1haW5faW5kZXggPSA5OAogICAgICBNLnN0eWxlX21haW4obGFzdF92aWV3LCB0cnVlKQoKICAgIGVsc2UKCiAgICAgIGVycm9yKCJpbnZhbGlkIHN0YXRlOiBtYWluIHRyYW5zaXRpb24iKQoKICAgIGVuZAoKICBlbmQKCiAgTS5zdHlsZV9mYWJzX3RyYW5zaXRpb24gPSBmdW5jdGlvbiAobmV4dF92aWV3LCB0cmFuc2l0aW9uLCBkaXJlY3Rpb24sIGxhc3RfdmlldykKCiAgICBsb2NhbCBpc19zaGFyZWQgPSBsYXN0X3ZpZXcgYW5kIG5leHRfdmlldy5lX2ZhYnMubGVuZ3RoID4gMCBhbmQgbGFzdF92aWV3LmVfZmFicy5sZW5ndGggPiAwCgogICAgaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIHRoZW4KCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX2luZGV4ID0gOTkKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc2NhbGUgPSAxCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29wYWNpdHkgPSAxCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX3NoYWRvdyA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzMgJT4iCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29mZnNldCA9IDAKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc3ZnX29mZnNldCA9IDAKCiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9pbmRleCA9IDk4CiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9zY2FsZSA9IDEKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAxCiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9vZmZzZXQgPSAwCgogICAgICBuZXh0X3ZpZXcuZmFic190b3BfaW5kZXggPSA5OAogICAgICBuZXh0X3ZpZXcuZmFic190b3Bfc2NhbGUgPSAxCiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9vcGFjaXR5ID0gMQogICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb2Zmc2V0ID0gTS5nZXRfYmFzZV9mYWJzX3RvcF9vZmZzZXQobmV4dF92aWV3KQoKICAgICAgTS5zdHlsZV9mYWJzKG5leHRfdmlldykKCiAgICBlbHNlaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZXhpdCIgdGhlbgoKICAgICAgZXJyb3IoImludmFsaWQgc3RhdGU6IGZhYnMgZXhpdCB0cmFuc2l0aW9uIHdpdGggbm8gbGFzdCB2aWV3IikKCiAgICBlbHNlaWYgaXNfc2hhcmVkIGFuZCB0cmFuc2l0aW9uID09ICJlbnRlciIgYW5kIGRpcmVjdGlvbiA9PSAiZm9yd2FyZCIgdGhlbgoKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfaW5kZXggPSA5OQogICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zY2FsZSA9IDEKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc2hhZG93ID0gIjwlIHJldHVybiBhcHAuc2hhZG93MyAlPiIKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb2Zmc2V0ID0gMAogICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zdmdfb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC5mYWJfc2hhcmVkX3N2Z190cmFuc2l0aW9uX2hlaWdodCAlPgoKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX2luZGV4ID0gOTgKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMC43NQogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgoKICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX2luZGV4ID0gOTgKICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX3NjYWxlID0gMC43NQogICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiArIE0uZ2V0X2Jhc2VfZmFic190b3Bfb2Zmc2V0KG5leHRfdmlldykKCiAgICAgIE0uc3R5bGVfZmFicyhuZXh0X3ZpZXcpCgogICAgICBNLmFmdGVyX2ZyYW1lKGZ1bmN0aW9uICgpCiAgICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc3ZnX29mZnNldCA9IDAKICAgICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9vcGFjaXR5ID0gMQogICAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9zY2FsZSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb2Zmc2V0ID0gMAogICAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9zY2FsZSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb3BhY2l0eSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb2Zmc2V0ID0gTS5nZXRfYmFzZV9mYWJzX3RvcF9vZmZzZXQobmV4dF92aWV3KQogICAgICAgIE0uc3R5bGVfZmFicyhuZXh0X3ZpZXcsIHRydWUpCiAgICAgIGVuZCkKCiAgICBlbHNlaWYgaXNfc2hhcmVkIGFuZCB0cmFuc2l0aW9uID09ICJleGl0IiBhbmQgZGlyZWN0aW9uID09ICJmb3J3YXJkIiB0aGVuCgogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9pbmRleCA9IDk5CiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX3NjYWxlID0gMQogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9vcGFjaXR5ID0gMQogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9zaGFkb3cgPSAiPCUgcmV0dXJuIGFwcC5zaGFkb3czX3RyYW5zcGFyZW50ICU+IgogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9vZmZzZXQgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX3N2Z19vZmZzZXQgPSAtIDwlIHJldHVybiBhcHAuZmFiX3NoYXJlZF9zdmdfdHJhbnNpdGlvbl9oZWlnaHQgJT4KCiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9pbmRleCA9IDk2CiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9zY2FsZSA9IDEKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9vZmZzZXQgPSAwCgogICAgICBsYXN0X3ZpZXcuZmFic190b3BfaW5kZXggPSA5NgogICAgICBsYXN0X3ZpZXcuZmFic190b3Bfc2NhbGUgPSAxCiAgICAgIGxhc3Rfdmlldy5mYWJzX3RvcF9vcGFjaXR5ID0gMAogICAgICBsYXN0X3ZpZXcuZmFic190b3Bfb2Zmc2V0ID0gTS5nZXRfYmFzZV9mYWJzX3RvcF9vZmZzZXQobGFzdF92aWV3KQoKICAgICAgTS5zdHlsZV9mYWJzKGxhc3RfdmlldywgdHJ1ZSkKCiAgICBlbHNlaWYgaXNfc2hhcmVkIGFuZCB0cmFuc2l0aW9uID09ICJlbnRlciIgYW5kIGRpcmVjdGlvbiA9PSAiYmFja3dhcmQiIHRoZW4KCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX2luZGV4ID0gOTkKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc2NhbGUgPSAxCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29wYWNpdHkgPSAwCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX3NoYWRvdyA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzMgJT4iCiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29mZnNldCA9IDAKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc3ZnX29mZnNldCA9IC0gPCUgcmV0dXJuIGFwcC5mYWJfc2hhcmVkX3N2Z190cmFuc2l0aW9uX2hlaWdodCAlPgoKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX2luZGV4ID0gOTYKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMC43NQogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDAKCiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9pbmRleCA9IDk2CiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9zY2FsZSA9IDAuNzUKICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX29wYWNpdHkgPSAwCiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9vZmZzZXQgPSBNLmdldF9iYXNlX2ZhYnNfdG9wX29mZnNldChuZXh0X3ZpZXcpCgogICAgICBNLnN0eWxlX2ZhYnMobmV4dF92aWV3KQoKICAgICAgTS5hZnRlcl9mcmFtZShmdW5jdGlvbiAoKQogICAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX3N2Z19vZmZzZXQgPSAwCiAgICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb3BhY2l0eSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fc2NhbGUgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX3NjYWxlID0gMQogICAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9vcGFjaXR5ID0gMQogICAgICAgIE0uc3R5bGVfZmFicyhuZXh0X3ZpZXcsIHRydWUpCiAgICAgIGVuZCkKCiAgICBlbHNlaWYgaXNfc2hhcmVkIGFuZCB0cmFuc2l0aW9uID09ICJleGl0IiBhbmQgZGlyZWN0aW9uID09ICJiYWNrd2FyZCIgdGhlbgoKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfaW5kZXggPSA5OQogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9zY2FsZSA9IDEKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfb3BhY2l0eSA9IDEKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfc2hhZG93ID0gIjwlIHJldHVybiBhcHAuc2hhZG93M190cmFuc3BhcmVudCAlPiIKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfb2Zmc2V0ID0gMAogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9zdmdfb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC5mYWJfc2hhcmVkX3N2Z190cmFuc2l0aW9uX2hlaWdodCAlPgoKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX2luZGV4ID0gOTgKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMC43NQogICAgICBsYXN0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDAKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgoKICAgICAgbGFzdF92aWV3LmZhYnNfdG9wX2luZGV4ID0gMTAwCiAgICAgIGxhc3Rfdmlldy5mYWJzX3RvcF9zY2FsZSA9IDAuNzUKICAgICAgbGFzdF92aWV3LmZhYnNfdG9wX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJzX3RvcF9vZmZzZXQgPSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gKyBNLmdldF9iYXNlX2ZhYnNfdG9wX29mZnNldChsYXN0X3ZpZXcpCgogICAgICBNLnN0eWxlX2ZhYnMobGFzdF92aWV3LCB0cnVlKQoKICAgIGVsc2VpZiB0cmFuc2l0aW9uID09ICJlbnRlciIgYW5kIGRpcmVjdGlvbiA9PSAiZm9yd2FyZCIgdGhlbgoKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfaW5kZXggPSA5OAogICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zY2FsZSA9IDAuNzUKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc2hhZG93ID0gIjwlIHJldHVybiBhcHAuc2hhZG93MyAlPiIKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+CiAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX3N2Z19vZmZzZXQgPSAwCgogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21faW5kZXggPSA5OAogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fc2NhbGUgPSAwLjc1CiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9vcGFjaXR5ID0gMAogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+CgogICAgICBuZXh0X3ZpZXcuZmFic190b3BfaW5kZXggPSA5OAogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fc2NhbGUgPSAwLjc1CiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9vcGFjaXR5ID0gMAogICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb2Zmc2V0ID0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+ICsgTS5nZXRfYmFzZV9mYWJzX3RvcF9vZmZzZXQobmV4dF92aWV3KQoKICAgICAgTS5zdHlsZV9mYWJzKG5leHRfdmlldykKCiAgICAgIE0uYWZ0ZXJfZnJhbWUoZnVuY3Rpb24gKCkKICAgICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zY2FsZSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9vcGFjaXR5ID0gMQogICAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29mZnNldCA9IDAKICAgICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fc2NhbGUgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDAKICAgICAgICBuZXh0X3ZpZXcuZmFic190b3Bfc2NhbGUgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX29wYWNpdHkgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfdG9wX29mZnNldCA9IE0uZ2V0X2Jhc2VfZmFic190b3Bfb2Zmc2V0KG5leHRfdmlldykKICAgICAgICBNLnN0eWxlX2ZhYnMobmV4dF92aWV3LCB0cnVlKQogICAgICBlbmQpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImVudGVyIiBhbmQgZGlyZWN0aW9uID09ICJiYWNrd2FyZCIgdGhlbgoKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfaW5kZXggPSA5NgogICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zY2FsZSA9IDAuNzUKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfc2hhZG93ID0gIjwlIHJldHVybiBhcHAuc2hhZG93MyAlPiIKICAgICAgbmV4dF92aWV3LmZhYl9zaGFyZWRfb2Zmc2V0ID0gMAogICAgICBuZXh0X3ZpZXcuZmFiX3NoYXJlZF9zdmdfb2Zmc2V0ID0gMAoKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX2luZGV4ID0gOTYKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMC43NQogICAgICBuZXh0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDAKCiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9pbmRleCA9IDk2CiAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9zY2FsZSA9IDAuNzUKICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAwCiAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9vZmZzZXQgPSBNLmdldF9iYXNlX2ZhYnNfdG9wX29mZnNldChuZXh0X3ZpZXcpCgogICAgICBNLnN0eWxlX2ZhYnMobmV4dF92aWV3KQoKICAgICAgTS5hZnRlcl9mcmFtZShmdW5jdGlvbiAoKQogICAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX3NjYWxlID0gMQogICAgICAgIG5leHRfdmlldy5mYWJfc2hhcmVkX29wYWNpdHkgPSAxCiAgICAgICAgbmV4dF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMQogICAgICAgIG5leHRfdmlldy5mYWJzX2JvdHRvbV9vcGFjaXR5ID0gMQogICAgICAgIG5leHRfdmlldy5mYWJzX3RvcF9zY2FsZSA9IDEKICAgICAgICBuZXh0X3ZpZXcuZmFic190b3Bfb3BhY2l0eSA9IDEKICAgICAgICBNLnN0eWxlX2ZhYnMobmV4dF92aWV3LCB0cnVlKQogICAgICBlbmQpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImV4aXQiIGFuZCBkaXJlY3Rpb24gPT0gImZvcndhcmQiIHRoZW4KCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX2luZGV4ID0gOTYKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfc2NhbGUgPSAxCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX3NoYWRvdyA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzMgJT4iCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX29mZnNldCA9IDAKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfc3ZnX29mZnNldCA9IDAKCiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9pbmRleCA9IDk2CiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9zY2FsZSA9IDEKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJzX2JvdHRvbV9vZmZzZXQgPSAwCgogICAgICBsYXN0X3ZpZXcuZmFic190b3BfaW5kZXggPSA5NgogICAgICBsYXN0X3ZpZXcuZmFic190b3Bfc2NhbGUgPSAxCiAgICAgIGxhc3Rfdmlldy5mYWJzX3RvcF9vcGFjaXR5ID0gMAogICAgICBsYXN0X3ZpZXcuZmFic190b3Bfb2Zmc2V0ID0gTS5nZXRfYmFzZV9mYWJzX3RvcF9vZmZzZXQobGFzdF92aWV3KQoKICAgICAgTS5zdHlsZV9mYWJzKGxhc3RfdmlldywgdHJ1ZSkKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZXhpdCIgYW5kIGRpcmVjdGlvbiA9PSAiYmFja3dhcmQiIHRoZW4KCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX2luZGV4ID0gOTYKICAgICAgbGFzdF92aWV3LmZhYl9zaGFyZWRfc2NhbGUgPSAwLjc1CiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX3NoYWRvdyA9ICI8JSByZXR1cm4gYXBwLnNoYWRvdzMgJT4iCiAgICAgIGxhc3Rfdmlldy5mYWJfc2hhcmVkX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgogICAgICBsYXN0X3ZpZXcuZmFiX3NoYXJlZF9zdmdfb2Zmc2V0ID0gMAoKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX2luZGV4ID0gOTYKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX3NjYWxlID0gMC43NQogICAgICBsYXN0X3ZpZXcuZmFic19ib3R0b21fb3BhY2l0eSA9IDAKICAgICAgbGFzdF92aWV3LmZhYnNfYm90dG9tX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgoKICAgICAgbGFzdF92aWV3LmZhYnNfdG9wX2luZGV4ID0gOTYKICAgICAgbGFzdF92aWV3LmZhYnNfdG9wX3NjYWxlID0gMC43NQogICAgICBsYXN0X3ZpZXcuZmFic190b3Bfb3BhY2l0eSA9IDAKICAgICAgbGFzdF92aWV3LmZhYnNfdG9wX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiArIE0uZ2V0X2Jhc2VfZmFic190b3Bfb2Zmc2V0KGxhc3RfdmlldykKCiAgICAgIE0uc3R5bGVfZmFicyhsYXN0X3ZpZXcsIHRydWUpCgogICAgZWxzZQoKICAgICAgZXJyb3IoImludmFsaWQgc3RhdGU6IGZhYnMgdHJhbnNpdGlvbiIpCgogICAgZW5kCgogIGVuZAoKICBNLnN0eWxlX3NuYWNrc190cmFuc2l0aW9uID0gZnVuY3Rpb24gKG5leHRfdmlldywgdHJhbnNpdGlvbiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCgogICAgaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIHRoZW4KCiAgICAgIG5leHRfdmlldy5zbmFja19vZmZzZXQgPSBNLmdldF9iYXNlX3NuYWNrX29mZnNldChuZXh0X3ZpZXcpCiAgICAgIG5leHRfdmlldy5zbmFja19vcGFjaXR5ID0gbmV4dF92aWV3Lm1heGltaXplZCBhbmQgMCBvciAxCiAgICAgIG5leHRfdmlldy5zbmFja19pbmRleCA9IDk2CiAgICAgIE0uc3R5bGVfc25hY2tzKG5leHRfdmlldykKCiAgICBlbHNlaWYgbm90IGxhc3RfdmlldyBhbmQgdHJhbnNpdGlvbiA9PSAiZXhpdCIgdGhlbgoKICAgICAgZXJyb3IoImludmFsaWQgc3RhdGU6IHNuYWNrIGV4aXQgdHJhbnNpdGlvbiB3aXRoIG5vIGxhc3QgdmlldyIpCgogICAgZWxzZWlmIHRyYW5zaXRpb24gPT0gImVudGVyIiBhbmQgZGlyZWN0aW9uID09ICJmb3J3YXJkIiB0aGVuCgogICAgICBuZXh0X3ZpZXcuc25hY2tfb2Zmc2V0ID0gTS5nZXRfYmFzZV9zbmFja19vZmZzZXQobmV4dF92aWV3KSArIDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPgogICAgICBuZXh0X3ZpZXcuc25hY2tfb3BhY2l0eSA9IDAKICAgICAgbmV4dF92aWV3LnNuYWNrX2luZGV4ID0gOTgKICAgICAgTS5zdHlsZV9zbmFja3MobmV4dF92aWV3KQoKICAgICAgTS5hZnRlcl9mcmFtZShmdW5jdGlvbiAoKQogICAgICAgIG5leHRfdmlldy5zbmFja19vZmZzZXQgPSBuZXh0X3ZpZXcuc25hY2tfb2Zmc2V0IC0gPCUgcmV0dXJuIGFwcC50cmFuc2l0aW9uX2ZvcndhcmRfaGVpZ2h0ICU+CiAgICAgICAgbmV4dF92aWV3LnNuYWNrX29wYWNpdHkgPSBuZXh0X3ZpZXcubWF4aW1pemVkIGFuZCAwIG9yIDEKICAgICAgICBNLnN0eWxlX3NuYWNrcyhuZXh0X3ZpZXcsIHRydWUpCiAgICAgIGVuZCkKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZXhpdCIgYW5kIGRpcmVjdGlvbiA9PSAiZm9yd2FyZCIgdGhlbgoKICAgICAgbGFzdF92aWV3LnNuYWNrX29mZnNldCA9IE0uZ2V0X2Jhc2Vfc25hY2tfb2Zmc2V0KGxhc3RfdmlldykgLSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gLyAyCiAgICAgIGxhc3Rfdmlldy5zbmFja19vcGFjaXR5ID0gbmV4dF92aWV3Lm1heGltaXplZCBhbmQgMCBvciAxCiAgICAgIGxhc3Rfdmlldy5zbmFja19pbmRleCA9IDk2CiAgICAgIE0uc3R5bGVfc25hY2tzKGxhc3RfdmlldywgdHJ1ZSkKCiAgICBlbHNlaWYgdHJhbnNpdGlvbiA9PSAiZW50ZXIiIGFuZCBkaXJlY3Rpb24gPT0gImJhY2t3YXJkIiB0aGVuCgogICAgICBuZXh0X3ZpZXcuc25hY2tfb2Zmc2V0ID0gTS5nZXRfYmFzZV9zbmFja19vZmZzZXQobmV4dF92aWV3KSAgLSA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fZm9yd2FyZF9oZWlnaHQgJT4gLyAyCiAgICAgIG5leHRfdmlldy5zbmFja19vcGFjaXR5ID0gbmV4dF92aWV3Lm1heGltaXplZCBhbmQgMCBvciAxCiAgICAgIG5leHRfdmlldy5zbmFja19pbmRleCA9IDk2CiAgICAgIE0uc3R5bGVfc25hY2tzKG5leHRfdmlldykKCiAgICAgIE0uYWZ0ZXJfZnJhbWUoZnVuY3Rpb24gKCkKICAgICAgICBuZXh0X3ZpZXcuc25hY2tfb2Zmc2V0ID0gTS5nZXRfYmFzZV9zbmFja19vZmZzZXQobmV4dF92aWV3KQogICAgICAgIE0uc3R5bGVfc25hY2tzKG5leHRfdmlldywgdHJ1ZSkKICAgICAgZW5kKQoKICAgIGVsc2VpZiB0cmFuc2l0aW9uID09ICJleGl0IiBhbmQgZGlyZWN0aW9uID09ICJiYWNrd2FyZCIgdGhlbgoKICAgICAgbGFzdF92aWV3LnNuYWNrX29mZnNldCA9IDwlIHJldHVybiBhcHAudHJhbnNpdGlvbl9mb3J3YXJkX2hlaWdodCAlPiArIE0uZ2V0X2Jhc2Vfc25hY2tfb2Zmc2V0KGxhc3RfdmlldykKICAgICAgbGFzdF92aWV3LnNuYWNrX29wYWNpdHkgPSAwCiAgICAgIGxhc3Rfdmlldy5zbmFja19pbmRleCA9IDk4CiAgICAgIE0uc3R5bGVfc25hY2tzKGxhc3RfdmlldywgdHJ1ZSkKCiAgICBlbHNlCgogICAgICBlcnJvcigiaW52YWxpZCBzdGF0ZTogbWFpbiB0cmFuc2l0aW9uIikKCiAgICBlbmQKCiAgZW5kCgogIE0uc2Nyb2xsX2xpc3RlbmVyID0gZnVuY3Rpb24gKHZpZXcpCgogICAgbG9jYWwgdGlja2luZyA9IGZhbHNlCgogICAgcmV0dXJuIGZ1bmN0aW9uICgpCiAgICAgIHZpZXcuY3Vycl9zY3JvbGx5ID0gd2luZG93LnNjcm9sbFkKICAgICAgaWYgbm90IHRpY2tpbmcgdGhlbgogICAgICAgIHdpbmRvdzpyZXF1ZXN0QW5pbWF0aW9uRnJhbWUoZnVuY3Rpb24gKCkKICAgICAgICAgIE0uc3R5bGVfaGVhZGVyKHZpZXcpCiAgICAgICAgICB2aWV3Lmxhc3Rfc2Nyb2xseSA9IHZpZXcuY3Vycl9zY3JvbGx5CiAgICAgICAgICB0aWNraW5nID0gZmFsc2UKICAgICAgICBlbmQpCiAgICAgICAgdGlja2luZyA9IHRydWUKICAgICAgZW5kCiAgICBlbmQKCiAgZW5kCgogIE0uYWZ0ZXJfdHJhbnNpdGlvbiA9IGZ1bmN0aW9uIChmbikKICAgIHJldHVybiB3aW5kb3c6c2V0VGltZW91dChmdW5jdGlvbiAoKQogICAgICB3aW5kb3c6cmVxdWVzdEFuaW1hdGlvbkZyYW1lKGZuKQogICAgZW5kLCA8JSByZXR1cm4gYXBwLnRyYW5zaXRpb25fdGltZV9tcyAlPikKICBlbmQKCiAgTS5hZnRlcl9mcmFtZSA9IGZ1bmN0aW9uIChmbikKICAgIHJldHVybiB3aW5kb3c6cmVxdWVzdEFuaW1hdGlvbkZyYW1lKGZ1bmN0aW9uICgpCiAgICAgIHdpbmRvdzpyZXF1ZXN0QW5pbWF0aW9uRnJhbWUoZm4pCiAgICBlbmQpCiAgZW5kCgogIE0ucG9zdF9leGl0ID0gZnVuY3Rpb24gKGxhc3RfdmlldywgdG9fY2xhc3MpCgogICAgbGFzdF92aWV3LmVsLmNsYXNzTGlzdDpyZW1vdmUoImV4aXQiLCAiZm9yd2FyZCIsICJiYWNrd2FyZCIsIHRvX2NsYXNzKQoKICAgIGxhc3Rfdmlldy5lbDpyZW1vdmUoKQoKICAgIGlmIGxhc3Rfdmlldy5zY3JpcHQucG9zdF9yZW1vdmUgdGhlbgogICAgICBsYXN0X3ZpZXcuc2NyaXB0LnBvc3RfcmVtb3ZlKGxhc3RfdmlldykKICAgIGVuZAoKICBlbmQKCiAgTS5wb3N0X2VudGVyID0gZnVuY3Rpb24gKG5leHRfdmlldywgZnJvbV9jbGFzcykKCiAgICBuZXh0X3ZpZXcuZWwuY2xhc3NMaXN0OnJlbW92ZSgiZW50ZXIiLCAiZm9yd2FyZCIsICJiYWNrd2FyZCIsIGZyb21fY2xhc3MpCgogICAgZV9ib2R5LmNsYXNzTGlzdDpyZW1vdmUoInRyYW5zaXRpb24iKQoKICAgIGlmIG5leHRfdmlldy5zY3JpcHQucG9zdF9hcHBlbmQgdGhlbgogICAgICBuZXh0X3ZpZXcuc2NyaXB0LnBvc3RfYXBwZW5kKG5leHRfdmlldykKICAgIGVuZAoKICAgIGxvY2FsIGVfYmFjayA9IG5leHRfdmlldy5lbDpxdWVyeVNlbGVjdG9yKCIucGFnZSA+IC5oZWFkZXIgPiAuYmFjayIpCgogICAgaWYgZV9iYWNrIHRoZW4KICAgICAgZV9iYWNrOmFkZEV2ZW50TGlzdGVuZXIoImNsaWNrIiwgZnVuY3Rpb24gKCkKICAgICAgICBNLmJhY2t3YXJkKCkKICAgICAgZW5kKQogICAgZW5kCgogICAgaWYgbmV4dF92aWV3LmVfaGVhZGVyIGFuZCBub3QgbmV4dF92aWV3LmVfaGVhZGVyLmNsYXNzTGlzdDpjb250YWlucygibm9oaWRlIikgdGhlbgogICAgICBuZXh0X3ZpZXcuY3Vycl9zY3JvbGx5ID0gbmlsCiAgICAgIG5leHRfdmlldy5sYXN0X3Njcm9sbHkgPSBuaWwKICAgICAgbmV4dF92aWV3LnNjcm9sbF9saXN0ZW5lciA9IE0uc2Nyb2xsX2xpc3RlbmVyKG5leHRfdmlldykKICAgICAgd2luZG93OmFkZEV2ZW50TGlzdGVuZXIoInNjcm9sbCIsIG5leHRfdmlldy5zY3JvbGxfbGlzdGVuZXIpCiAgICBlbmQKCiAgICBNLnNldHVwX3JpcHBsZXMobmV4dF92aWV3LmVsKQoKICBlbmQKCiAgTS5lbnRlciA9IGZ1bmN0aW9uIChuZXh0X3ZpZXcsIGRpcmVjdGlvbiwgbGFzdF92aWV3KQoKICAgIG5leHRfdmlldy5lbCA9IHV0aWwuY2xvbmUobmV4dF92aWV3LnRlbXBsYXRlKQogICAgbmV4dF92aWV3LmVfaGVhZGVyID0gbmV4dF92aWV3LmVsOnF1ZXJ5U2VsZWN0b3IoIi5wYWdlID4gLmhlYWRlciIpCiAgICBuZXh0X3ZpZXcuZV9tYWluID0gbmV4dF92aWV3LmVsOnF1ZXJ5U2VsZWN0b3IoIi5wYWdlID4gLm1haW4iKQogICAgbmV4dF92aWV3LmVfc25hY2tzID0gbmV4dF92aWV3LmVsOnF1ZXJ5U2VsZWN0b3IoIi5wYWdlID4gLnNuYWNrcyIpCgogICAgTS5zZXR1cF9vYnNlcnZlcihuZXh0X3ZpZXcpCiAgICBNLnNldHVwX2ZhYnMobmV4dF92aWV3LCBsYXN0X3ZpZXcpCiAgICBNLnNldHVwX3NuYWNrcyhuZXh0X3ZpZXcpCiAgICBNLnNldHVwX2hlYWRlcl90aXRsZV93aWR0aChuZXh0X3ZpZXcpCiAgICBNLnN0eWxlX2hlYWRlcl90cmFuc2l0aW9uKG5leHRfdmlldywgImVudGVyIiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCiAgICBNLnN0eWxlX21haW5fdHJhbnNpdGlvbihuZXh0X3ZpZXcsICJlbnRlciIsIGRpcmVjdGlvbiwgbGFzdF92aWV3KQogICAgTS5zdHlsZV9mYWJzX3RyYW5zaXRpb24obmV4dF92aWV3LCAiZW50ZXIiLCBkaXJlY3Rpb24sIGxhc3RfdmlldykKICAgIE0uc3R5bGVfc25hY2tzX3RyYW5zaXRpb24obmV4dF92aWV3LCAiZW50ZXIiLCBkaXJlY3Rpb24sIGxhc3RfdmlldykKICAgIE0uc2V0dXBfbWF4aW1pemUobmV4dF92aWV3KQoKICAgIGlmIG5leHRfdmlldy5zY3JpcHQucHJlX2FwcGVuZCB0aGVuCiAgICAgIG5leHRfdmlldy5zY3JpcHQucHJlX2FwcGVuZChuZXh0X3ZpZXcpCiAgICBlbmQKCiAgICBsb2NhbCBmcm9tX2NsYXNzID0gImZyb20tIiAuLiAobGFzdF92aWV3IGFuZCBsYXN0X3ZpZXcubmFtZSBvciAibm9uZSIpCgogICAgTS5hZnRlcl90cmFuc2l0aW9uKGZ1bmN0aW9uICgpCiAgICAgIHJldHVybiBNLnBvc3RfZW50ZXIobmV4dF92aWV3LCBmcm9tX2NsYXNzKQogICAgZW5kKQoKICAgIGVfYm9keS5jbGFzc0xpc3Q6YWRkKCJ0cmFuc2l0aW9uIikKCiAgICBuZXh0X3ZpZXcuZWwuY2xhc3NMaXN0OmFkZCgiZW50ZXIiLCBkaXJlY3Rpb24sIGZyb21fY2xhc3MpCgogICAgZV9ib2R5OmFwcGVuZChuZXh0X3ZpZXcuZWwpCgogIGVuZAoKICBNLmV4aXQgPSBmdW5jdGlvbiAobGFzdF92aWV3LCBkaXJlY3Rpb24sIG5leHRfdmlldykKCiAgICBpZiBsYXN0X3ZpZXcuc2NyaXB0LnByZV9yZW1vdmUgdGhlbgogICAgICBsYXN0X3ZpZXcuc2NyaXB0LnByZV9yZW1vdmUobGFzdF92aWV3KQogICAgZW5kCgogICAgTS5zdHlsZV9oZWFkZXJfdHJhbnNpdGlvbihuZXh0X3ZpZXcsICJleGl0IiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCiAgICBNLnN0eWxlX21haW5fdHJhbnNpdGlvbihuZXh0X3ZpZXcsICJleGl0IiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCiAgICBNLnN0eWxlX2ZhYnNfdHJhbnNpdGlvbihuZXh0X3ZpZXcsICJleGl0IiwgZGlyZWN0aW9uLCBsYXN0X3ZpZXcpCiAgICBNLnN0eWxlX3NuYWNrc190cmFuc2l0aW9uKG5leHRfdmlldywgImV4aXQiLCBkaXJlY3Rpb24sIGxhc3RfdmlldykKCiAgICBsb2NhbCB0b19jbGFzcyA9ICJ0by0iIC4uIChuZXh0X3ZpZXcgYW5kIG5leHRfdmlldy5uYW1lIG9yICJub25lIikKCiAgICBpZiBsYXN0X3ZpZXcuc2Nyb2xsX2xpc3RlbmVyIHRoZW4KICAgICAgd2luZG93OnJlbW92ZUV2ZW50TGlzdGVuZXIoInNjcm9sbCIsIGxhc3Rfdmlldy5zY3JvbGxfbGlzdGVuZXIpCiAgICAgIGxhc3Rfdmlldy5zY3JvbGxfbGlzdGVuZXIgPSBuaWwKICAgIGVuZAoKICAgIE0uYWZ0ZXJfdHJhbnNpdGlvbihmdW5jdGlvbiAoKQogICAgICByZXR1cm4gTS5wb3N0X2V4aXQobGFzdF92aWV3LCB0b19jbGFzcykKICAgIGVuZCkKCiAgICBsYXN0X3ZpZXcuZWwuY2xhc3NMaXN0OmFkZCgiZXhpdCIsIGRpcmVjdGlvbiwgdG9fY2xhc3MpCgogIGVuZAoKICBNLmluaXRfdmlldyA9IGZ1bmN0aW9uIChuYW1lLCB0ZW1wbGF0ZSwgc2NyaXB0LCBvcHRzKQoKICAgIHJldHVybiB7CgogICAgICBmb3J3YXJkID0gTS5mb3J3YXJkLAogICAgICBiYWNrd2FyZCA9IE0uYmFja3dhcmQsCiAgICAgIHJlcGxhY2UgPSBNLnJlcGxhY2UsCgogICAgICB0ZW1wbGF0ZSA9IHRlbXBsYXRlLAogICAgICBzY3JpcHQgPSBzY3JpcHQsCiAgICAgIG5hbWUgPSBuYW1lLAogICAgICBzdGF0ZSA9IG9wdHMuc3RhdGUgb3Ige30KCiAgICB9CgogIGVuZAoKICBNLmZvcndhcmQgPSBmdW5jdGlvbiAobmFtZSwgb3B0cykKCiAgICBvcHRzID0gb3B0cyBvciB7fQoKICAgIGxvY2FsIHRlbXBsYXRlID0gZV9oZWFkOnF1ZXJ5U2VsZWN0b3IoInRlbXBsYXRlW2RhdGEtdmlldz1cIiIgLi4gbmFtZSAuLiAiXCJdIikKICAgIGxvY2FsIHNjcmlwdCA9IHNjcmlwdHNbbmFtZV0KCiAgICBpZiBub3QgdGVtcGxhdGUgdGhlbgogICAgICByZXR1cm4gZmFsc2UsICJubyB0ZW1wbGF0ZSBmb3VuZCIKICAgIGVuZAoKICAgIGxvY2FsIGxhc3RfdmlldyA9IHN0YWNrWyNzdGFja10KICAgIGxvY2FsIG5leHRfdmlldyA9IE0uaW5pdF92aWV3KG5hbWUsIHRlbXBsYXRlLCBzY3JpcHQsIG9wdHMpCgogICAgTS5lbnRlcihuZXh0X3ZpZXcsICJmb3J3YXJkIiwgbGFzdF92aWV3KQoKICAgIGlmIGxhc3RfdmlldyB0aGVuCiAgICAgIE0uZXhpdChsYXN0X3ZpZXcsICJmb3J3YXJkIiwgbmV4dF92aWV3KQogICAgZW5kCgogICAgYXJyLnB1c2goc3RhY2ssIG5leHRfdmlldykKCiAgZW5kCgogIE0ucmVwbGFjZSA9IGZ1bmN0aW9uIChuYW1lLCBvcHRzKQoKICAgIG9wdHMgPSBvcHRzIG9yIHt9CiAgICBvcHRzLm4gPSBvcHRzLm4gb3IgMQoKICAgIGxvY2FsIGxhc3RfbiA9ICNzdGFjawoKICAgIE0uZm9yd2FyZChuYW1lLCBvcHRzKQoKICAgIGFyci5yZW1vdmUoc3RhY2ssIGxhc3RfbiAtIG9wdHMubiArIDEsIGxhc3RfbikKCiAgZW5kCgogIE0uYmFja3dhcmQgPSBmdW5jdGlvbiAob3B0cykKCiAgICBvcHRzID0gb3B0cyBvciB7fQogICAgb3B0cy5uID0gb3B0cy5uIG9yIDEKCiAgICBsb2NhbCBsYXN0X3ZpZXcgPSBzdGFja1sjc3RhY2tdCiAgICBsb2NhbCBuZXh0X3ZpZXcgPSBzdGFja1sjc3RhY2sgLSBvcHRzLm5dCgogICAgaWYgbm90IG5leHRfdmlldyB0aGVuCgogICAgICBNLnJlcGxhY2UoImhvbWUiLCBvcHRzKQoKICAgIGVsc2UKCiAgICAgIGlmIG9wdHMuc3RhdGUgdGhlbgogICAgICAgIG5leHRfdmlldy5zdGF0ZSA9IG9wdHMuc3RhdGUKICAgICAgZW5kCgogICAgICBNLmVudGVyKG5leHRfdmlldywgImJhY2t3YXJkIiwgbGFzdF92aWV3KQogICAgICBNLmV4aXQobGFzdF92aWV3LCAiYmFja3dhcmQiLCBuZXh0X3ZpZXcpCgogICAgICBhcnIucmVtb3ZlKHN0YWNrLCAjc3RhY2sgLSBvcHRzLm4gKyAxLCAjc3RhY2spCgogICAgZW5kCgogIGVuZAoKICB3aW5kb3c6YWRkRXZlbnRMaXN0ZW5lcigicG9wc3RhdGUiLCBmdW5jdGlvbiAoKQogICAgaGlzdG9yeTpnbygpCiAgZW5kKQoKICBNLnNldHVwX3JpcHBsZXMoZV9ib2R5KQoKICA8JSBwdXNoKGFwcC5zZXJ2aWNlX3dvcmtlcikgJT4KCiAgICBsb2NhbCBuYXZpZ2F0b3IgPSB3aW5kb3cubmF2aWdhdG9yCiAgICBsb2NhbCBzZXJ2aWNlV29ya2VyID0gbmF2aWdhdG9yLnNlcnZpY2VXb3JrZXIKCiAgICBsb2NhbCBlX3JlbG9hZCA9IGRvY3VtZW50OnF1ZXJ5U2VsZWN0b3IoImJvZHkgPiAud2Fybi11cGRhdGUtd29ya2VyIikKCiAgICBlX3JlbG9hZDphZGRFdmVudExpc3RlbmVyKCJjbGljayIsIGZ1bmN0aW9uICgpCiAgICAgIHdpbmRvdy5sb2NhdGlvbiA9IHdpbmRvdy5sb2NhdGlvbgogICAgZW5kKQoKICAgIE0uc3R5bGVfdXBkYXRlX3dvcmtlciA9IGZ1bmN0aW9uICgpCgogICAgICBpZiBub3QgdXBkYXRlX3dvcmtlciB0aGVuCgogICAgICAgIHVwZGF0ZV93b3JrZXIgPSB0cnVlCiAgICAgICAgbG9jYWwgYWN0aXZlID0gc3RhY2tbI3N0YWNrXQoKICAgICAgICBhY3RpdmUuaGVhZGVyX29mZnNldCA9IGFjdGl2ZS5oZWFkZXJfb2Zmc2V0ICsgPCUgcmV0dXJuIGFwcC5iYW5uZXJfaGVpZ2h0ICU+CiAgICAgICAgYWN0aXZlLm1haW5fb2Zmc2V0ID0gYWN0aXZlLm1haW5fb2Zmc2V0ICsgPCUgcmV0dXJuIGFwcC5iYW5uZXJfaGVpZ2h0ICU+CiAgICAgICAgYWN0aXZlLmZhYnNfdG9wX29mZnNldCA9IGFjdGl2ZS5mYWJzX3RvcF9vZmZzZXQgKyA8JSByZXR1cm4gYXBwLmJhbm5lcl9oZWlnaHQgJT4KICAgICAgICBhY3RpdmUuaGVhZGVyX21pbiA9IC0gPCUgcmV0dXJuIGFwcC5oZWFkZXJfaGVpZ2h0ICU+ICsgTS5nZXRfYmFzZV9oZWFkZXJfb2Zmc2V0KGFjdGl2ZSkKICAgICAgICBhY3RpdmUuaGVhZGVyX21heCA9IE0uZ2V0X2Jhc2VfaGVhZGVyX29mZnNldChhY3RpdmUpCgogICAgICAgIE0uc3R5bGVfaGVhZGVyKGFjdGl2ZSwgdHJ1ZSkKICAgICAgICBNLnN0eWxlX21haW4oYWN0aXZlLCB0cnVlKQogICAgICAgIE0uc3R5bGVfZmFicyhhY3RpdmUsIHRydWUpCgogICAgICBlbmQKCiAgICAgIGVfYm9keS5jbGFzc0xpc3Q6YWRkKCJ1cGRhdGUtd29ya2VyIikKCiAgICBlbmQKCiAgICBNLnBvbGxfd29ya2VyX3VwZGF0ZSA9IGZ1bmN0aW9uIChyZWcpCgogICAgICBsb2NhbCBwb2xsaW5nID0gZmFsc2UKICAgICAgbG9jYWwgaW5zdGFsbGluZyA9IGZhbHNlCgogICAgICB3aW5kb3c6c2V0SW50ZXJ2YWwoZnVuY3Rpb24gKCkKCiAgICAgICAgaWYgcG9sbGluZyB0aGVuCiAgICAgICAgICByZXR1cm4KICAgICAgICBlbmQKCiAgICAgICAgcG9sbGluZyA9IHRydWUKCiAgICAgICAgcmVnOnVwZGF0ZSgpOmF3YWl0KGZ1bmN0aW9uIChfLCBvaywgcmVnKQoKICAgICAgICAgIHBvbGxpbmcgPSBmYWxzZQoKICAgICAgICAgIGlmIG5vdCBvayB0aGVuCiAgICAgICAgICAgIHByaW50KCJTZXJ2aWNlIHdvcmtlciB1cGRhdGUgZXJyb3IiLCByZWcgYW5kIHJlZy5tZXNzYWdlIG9yIHJlZykKICAgICAgICAgIGVsc2VpZiByZWcuaW5zdGFsbGluZyB0aGVuCiAgICAgICAgICAgIGluc3RhbGxpbmcgPSB0cnVlCiAgICAgICAgICAgIHByaW50KCJVcGRhdGVkIHNlcnZpY2Ugd29ya2VyIGluc3RhbGxpbmciKQogICAgICAgICAgZWxzZWlmIHJlZy53YWl0aW5nIHRoZW4KICAgICAgICAgICAgcHJpbnQoIlVwZGF0ZWQgc2VydmljZSB3b3JrZXIgaW5zdGFsbGVkIikKICAgICAgICAgIGVsc2VpZiByZWcuYWN0aXZlIHRoZW4KICAgICAgICAgICAgaWYgaW5zdGFsbGluZyB0aGVuCiAgICAgICAgICAgICAgaW5zdGFsbGluZyA9IGZhbHNlCiAgICAgICAgICAgICAgTS5zdHlsZV91cGRhdGVfd29ya2VyKCkKICAgICAgICAgICAgZW5kCiAgICAgICAgICAgIHByaW50KCJVcGRhdGVkIHNlcnZpY2Ugd29ya2VyIGFjdGl2ZSIpCiAgICAgICAgICBlbmQKCiAgICAgICAgZW5kKQoKICAgICAgZW5kLCA8JSByZXR1cm4gYXBwLnNlcnZpY2Vfd29ya2VyX3BvbGxfdGltZV9tcyAlPikKCiAgICBlbmQKCiAgICBpZiBzZXJ2aWNlV29ya2VyIHRoZW4KCiAgICAgIHNlcnZpY2VXb3JrZXI6cmVnaXN0ZXIoIi9zdy5qcyIsIHsgc2NvcGUgPSAiLyIgfSk6YXdhaXQoZnVuY3Rpb24gKF8sIC4uLikKCiAgICAgICAgbG9jYWwgcmVnID0gZXJyLmNoZWNrb2soLi4uKQoKICAgICAgICBpZiByZWcuaW5zdGFsbGluZyB0aGVuCiAgICAgICAgICBwcmludCgiSW5pdGlhbCBzZXJ2aWNlIHdvcmtlciBpbnN0YWxsaW5nIikKICAgICAgICBlbHNlaWYgcmVnLndhaXRpbmcgdGhlbgogICAgICAgICAgcHJpbnQoIkluaXRpYWwgc2VydmljZSB3b3JrZXIgaW5zdGFsbGVkIikKICAgICAgICBlbHNlaWYgcmVnLmFjdGl2ZSB0aGVuCiAgICAgICAgICBwcmludCgiSW5pdGlhbCBzZXJ2aWNlIHdvcmtlciBhY3RpdmUiKQogICAgICAgIGVuZAoKICAgICAgICBNLnBvbGxfd29ya2VyX3VwZGF0ZShyZWcpCgogICAgICBlbmQpCgogICAgZW5kCgogIDwlIHBvcCgpICU+CgogIE0uZm9yd2FyZCgiaG9tZSIpCgo8JSBwdXNoKGFwcC50cmFjZSkgJT4KZW5kKQo8JSBwb3AoKSAlPgo=") -- luacheck: ignore
      add_copied_target_base64(fs.join(cwd(), cdir(base_client_spa_index_html)), "PCUKICBmcyA9IHJlcXVpcmUoInNhbnRva3UuZnMiKQogIGl0ID0gcmVxdWlyZSgic2FudG9rdS5pdGVyIikKICBhcnIgPSByZXF1aXJlKCJzYW50b2t1LmFycmF5IikKICB2aWV3cyA9IGNvbXBpbGVkaXIoZnMuam9pbigiY2xpZW50L3NwYSIsIHNwYV9uYW1lKSkKICBwYXJ0aWFscyA9IGNvbXBpbGVkaXIoImNsaWVudC9yZXMvcGFydGlhbHMiKQolPgoKPCFET0NUWVBFIGh0bWw+CjxodG1sPgogIDxoZWFkPgoKICAgIDwlIC0tIERvIHdlIHJlYWxseSB3YW50IHRoaXMgYXMgdGhlIGJhc2UgaHJlZj8gU2hvdWxkIGl0IGp1c3QgYmUgZm9yCiAgICAgICAtLSBzcGVjaWZpYyB0aGluZ3MsIGxpa2UgdGhlIGxpbmsgdG8gUGhvdG9tYXBwZXI/ICU+CiAgICA8YmFzZSB0YXJnZXQ9Il9ibGFuayIgcmVsPSJub29wZW5lciBub3JlZmVycmVyIj4KCiAgICA8dGl0bGU+PCUgcmV0dXJuIGFwcC50aXRsZSAlPjwvdGl0bGU+CgogICAgPGxpbmsgcmVsPSJtYW5pZmVzdCIgaHJlZj0iL21hbmlmZXN0LndlYm1hbmlmZXN0Ij4KICAgIDxtZXRhIG5hbWU9InRoZW1lLWNvbG9yIiBjb250ZW50PSI8JSByZXR1cm4gYXBwLmxpZ2h0X2JnICU+Ij4KCiAgICA8bWV0YSBjaGFyc2V0PSJ1dGYtOCI+CiAgICA8bWV0YSBodHRwLWVxdWl2PSJYLVVBLUNvbXBhdGlibGUiIGNvbnRlbnQ9IklFPWVkZ2UiPgogICAgPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEsbWluaW11bS1zY2FsZT0xLG1heGltdW0tc2NhbGU9MSx1c2VyLXNjYWxhYmxlPTwlIHJldHVybiBzY2FsYWJsZSBhbmQgInllcyIgb3IgIm5vIiAlPix1Yy1maXRzY3JlZW49eWVzIj4KICAgIDxtZXRhIG5hbWU9ImRlc2NyaXB0aW9uIiBjb250ZW50PSI8JSByZXR1cm4gYXBwLmRlc2NyaXB0aW9uICU+Ij4KICAgIDxtZXRhIG5hbWU9ImtleXdvcmRzIiBjb250ZW50PSI8JSByZXR1cm4gYXBwLmtleXdvcmRzICU+Ij4KCiAgICA8bWV0YSBuYW1lPSJhcHBsZS1tb2JpbGUtd2ViLWFwcC10aXRsZSIgY29udGVudD0iPCUgcmV0dXJuIGFwcC50aXRsZSAlPiI+CiAgICA8bWV0YSBuYW1lPSJhcHBsZS1tb2JpbGUtd2ViLWFwcC1jYXBhYmxlIiBjb250ZW50PSJ5ZXMiPgogICAgPG1ldGEgbmFtZT0iYXBwbGUtbW9iaWxlLXdlYi1hcHAtc3RhdHVzLWJhci1zdHlsZSIgY29udGVudD0iPCUgcmV0dXJuIGFwcC5saWdodF9iZyAlPiI+CgogICAgPG1ldGEgbmFtZT0ibXNhcHBsaWNhdGlvbi1uYXZidXR0b24tY29sb3IiIGNvbnRlbnQ9IjwlIHJldHVybiBhcHAubGlnaHRfYmcgJT4iPgogICAgPG1ldGEgbmFtZT0ibXNhcHBsaWNhdGlvbi1UaWxlQ29sb3IiIGNvbnRlbnQ9IjwlIHJldHVybiBhcHAubGlnaHRfYmcgJT4iPgoKICAgIDwlIC0tIFRPRE8KICAgICAgIC0tIDxtZXRhIG5hbWU9Im1zYXBwbGljYXRpb24tY29uZmlnIiBjb250ZW50PSJicm93c2VyY29uZmlnLnhtbCI+CiAgICAgICAtLSA8bWV0YSBuYW1lPSJzY3JlZW4tb3JpZW50YXRpb24iIGNvbnRlbnQ9InBvcnRyYWl0Ij4gJT4KCiAgICA8bWV0YSBuYW1lPSJhcHBsaWNhdGlvbi1uYW1lIiBjb250ZW50PSI8JSByZXR1cm4gYXBwLnRpdGxlICU+Ij4KICAgIDxtZXRhIG5hbWU9Im1zYXBwbGljYXRpb24tdG9vbHRpcCIgY29udGVudD0iPCUgcmV0dXJuIGFwcC5kZXNjcmlwdGlvbiAlPiI+CiAgICA8bWV0YSBuYW1lPSJtc2FwcGxpY2F0aW9uLVRpbGVJbWFnZSIgY29udGVudD0iL2ljb24tMTgwLnBuZyI+CiAgICA8bWV0YSBuYW1lPSJtc2FwcGxpY2F0aW9uLXN0YXJ0dXJsIiBjb250ZW50PSIiPgogICAgPG1ldGEgbmFtZT0ibXNhcHBsaWNhdGlvbi10YXAtaGlnaGxpZ2h0IiBjb250ZW50PSJubyI+CgogICAgPG1ldGEgbmFtZT0iZnVsbC1zY3JlZW4iIGNvbnRlbnQ9InllcyI+CiAgICA8bWV0YSBuYW1lPSJicm93c2VybW9kZSIgY29udGVudD0iYXBwbGljYXRpb24iPgogICAgPG1ldGEgbmFtZT0ibmlnaHRtb2RlIiBjb250ZW50PSJlbmFibGUiPgogICAgPG1ldGEgbmFtZT0ibGF5b3V0bW9kZSIgY29udGVudD0iZml0c2NyZWVuIj4KICAgIDxtZXRhIG5hbWU9ImltYWdlbW9kZSIgY29udGVudD0iZm9yY2UiPgoKICAgIDxsaW5rIHJlbD0iaWNvbiIgdHlwZT0iaW1hZ2UvcG5nIiBzaXplcz0iMTk2eDE5NiIgaHJlZj0iL2Zhdmljb24tMTk2LnBuZyI+CiAgICA8bGluayByZWw9ImFwcGxlLXRvdWNoLWljb24iIGhyZWY9Ii9pY29uLTE4MC5wbmciPgogICAgPG1ldGEgbmFtZT0iYXBwbGUtbW9iaWxlLXdlYi1hcHAtY2FwYWJsZSIgY29udGVudD0ieWVzIj4KCiAgICA8c3R5bGU+CiAgICAgIDwlIHJldHVybiBwYXJ0aWFscy5jc3MuY29tbW9uKCkgJT4KICAgIDwvc3R5bGU+CgogICAgPCUgcmV0dXJuIGFyci5jb25jYXQoaXQuY29sbGVjdChpdC5tYXAoZnVuY3Rpb24gKG5hbWUsIHRtcGwpCiAgICAgIHJldHVybiBbWwogICAgICAgIDx0ZW1wbGF0ZSBkYXRhLXZpZXc9Il1dIC4uIG5hbWUgLi4gW1siPgogICAgICAgICAgXV0gLi4gdG1wbCgpIC4uIFtbCiAgICAgICAgPC90ZW1wbGF0ZT4KICAgICAgXV0KICAgIGVuZCwgaXQucGFpcnModmlld3MuaHRtbCkpKSwgIlxuIikgJT4KCiAgICA8dGVtcGxhdGUgY2xhc3M9InJpcHBsZSI+CiAgICAgIDxkaXYgY2xhc3M9InJpcHBsZS1jb250YWluZXIiPgogICAgICAgIDxkaXYgY2xhc3M9InJpcHBsZS13YXZlIj48L2Rpdj4KICAgICAgPC9kaXY+CiAgICA8L3RlbXBsYXRlPgoKICAgIDwlIHB1c2goYXBwLmVydWRhKSAlPgogICAgICA8c2NyaXB0IHNyYz0iL2VydWRhLmpzIj48L3NjcmlwdD4KICAgICAgPHNjcmlwdD5lcnVkYS5pbml0KHsgZGlzcGxheVNpemU6IDQwIH0pO2VydWRhLnNob3coKTs8L3NjcmlwdD4KICAgIDwlIHBvcCgpICU+CgogIDwvaGVhZD4KCiAgPGJvZHk+CiAgICA8c2NyaXB0IHNyYz0iL2luZGV4LmpzIj48L3NjcmlwdD4KICAgIDwlIHB1c2goYXBwLnNlcnZpY2Vfd29ya2VyKSAlPgogICAgICA8YnV0dG9uIGNsYXNzPSJidXR0b24gd2Fybi11cGRhdGUtd29ya2VyIj4KICAgICAgICBBIG5ldyB2ZXJzaW9uIG9mIDwlIHJldHVybiBhcHAudGl0bGUgJT4KICAgICAgICBpcyBhdmFpbGFibGUuIENsaWNrIHRvIFVwZGF0ZSEKICAgICAgPC9idXR0b24+CiAgICA8JSBwb3AoKSAlPgogIDwvYm9keT4KCjwvaHRtbD4K") -- luacheck: ignore
      for fp in fs.files("client/spa", true) do
        add_templated_target(cdir_stripped(fp), fp, env)
      end
      for fp in fs.dirs("client/spa") do
        add_templated_target(cdir(fp) .. ".html", fs.join(cwd(), cdir(base_client_spa_index_html)), pushindex({
          spa_name = fs.basename(fp)
        }, env))
        add_copied_target(ddir_stripped(fp) .. ".html", cdir(fp) .. ".html")
        add_templated_target(
          fs.join(cwd(), cdir("build", "default-wasm", "build", "bin", stripparts(stripexts(fp), 2))) .. ".lua",
          fs.join(cwd(), cdir(base_client_spa_index_lua)),
          pushindex({
            spa_name = fs.basename(fp)
          }, env))
      end
    end

    for fp in ivals(base_client_pages) do
      local pre = absolute(cdir("build", "default-wasm", "build", "bin", stripexts(fp)) .. ".lua")
      local post = absolute(cdir("bundler-post", stripexts(fp)))
      local deps = { cdir(base_client_lua_modules_ok), pre }
      local wd = cwd()
      local extra_flags = it.reduce(function (a, k, v)
        if str.find(post, k) then
          if v.wrap_events then
            arr.push(deps, fs.join(wd, cdir("wrap_events.js")))
            arr.push(a, "--pre-js", fs.join(wd, cdir("wrap_events.js")))
          end
          if v.cxxflags then
            arr.extend(a, v.cxxflags)
          end
          if v.ldflags then
            arr.extend(a, v.ldflags)
          end
        end
        return a
      end, {}, it.pairs(get(env, "rules") or {}))
      target({ post }, deps, function ()
        pushd(cdir("build", "default-wasm", "build"), function ()
          bundle(pre, dirname(post), {
            cc = "emcc",
            ignores = { "debug" },
            path = get_lua_path(nil, fs.join(wd, cdir("build", "default-wasm", "build"))),
            cpath = get_lua_cpath(nil, fs.join(wd, cdir("build", "default-wasm", "build"))),
            flags = extend({
              "-sASSERTIONS", "-sSINGLE_FILE", "-sALLOW_MEMORY_GROWTH",
              "-I" .. join(wd, cdir("build", "default-wasm", "build", "lua-5.1.5"), "include"),
              "-L" .. join(wd, cdir("build", "default-wasm", "build", "lua-5.1.5"), "lib"),
              "-llua", "-lm",
              get(env, "cxxflags") or "",
              get(env, "ldflags") or "",
            }, extra_flags)
          })
        end)
      end)
      add_copied_target(ddir(fp), post)
    end

    target(
      { cdir(base_client_lua_modules_ok) },
      extend({ opts.config_file },
        amap(extend({}, base_client_res_templated), function (fp)
          return cdir_stripped("build", "default-wasm", "build", fp)
        end),
        amap(extend({}, base_client_bins, base_client_libs, base_client_deps, base_client_res), cdir_stripped)),
      function ()
        local config_file = absolute(opts.config_file)
        local config = {
          type = "lib",
          env = tbl.merge({
            name = opts.config.env.name .. "-client",
            version = opts.config.env.version,
          }, env)
        }
        mkdirp(cdir())
        return pushd(cdir(), function ()
          require("santoku.make.project").init({
            config_file = config_file,
            config = config,
            single = opts.single,
            profile = opts.profile,
            skip_coverage = opts.skip_coverage,
            wasm = true,
            skip_tests = true,
          }).install()
          local post_make = get(env, "hooks", "post_make")
          if post_make then
            post_make(env)
          end
          touch(base_client_lua_modules_ok)
        end)
      end)

  end

  target(
    { server_dir(base_server_lua_modules_ok) },
    extend({ server_dir(base_server_luarocks_cfg) },
      amap(extend({}, base_server_libs, base_server_deps), server_dir_stripped)),
    function ()

      local config_file = absolute(opts.config_file)

      local config = {
        type = "lib",
        env = tbl.assign({
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
        }, opts.config.env.server, false)
      }

      return pushd(server_dir(), function ()

        require("santoku.make.project").init({
          config_file = config_file,
          luarocks_config = absolute(base_server_luarocks_cfg),
          config = config,
          single = opts.single,
          profile = opts.profile,
          skip_coverage = opts.skip_coverage,
          skip_tests = true,
        }).install()

        local post_make = get(server_env, "hooks", "post_make")

        if post_make then
          post_make(server_env)
        end

        touch(base_server_lua_modules_ok)

      end)
    end)

  target(
    { test_server_dir(base_server_lua_modules_ok) },
    extend({ test_server_dir(base_server_luarocks_cfg) },
      amap(extend({}, base_server_libs, base_server_deps), test_server_dir_stripped)),
    function ()

      local config_file = absolute(opts.config_file)

      local config = {
        type = "lib",
        env = tbl.assign({
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
        }, opts.config.env.server, false)
      }

      return pushd(test_server_dir(), function ()

        require("santoku.make.project").init({
          config_file = config_file,
          luarocks_config = absolute(base_server_luarocks_cfg),
          config = config,
          single = opts.single,
          profile = opts.profile,
          skip_coverage = opts.skip_coverage,
          skip_tests = true,
          lua = test_server_env.lua,
          lua_path = test_server_env.lua_path,
          lua_cpath = test_server_env.lua_cpath,
        }).install()

        local post_make = get(test_server_env, "hooks", "post_make")

        if post_make then
          post_make(test_server_env)
        end

        touch(base_server_lua_modules_ok)

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
      amap(extend({},
        base_client_static, base_client_assets),
      dist_dir_client_stripped),
      amap(extend({},
        base_client_pages),
      dist_dir_client),
      it.collect(it.flatten(it.map(function (d)
        return it.map(dist_dir_client_stripped, it.ivals({ d .. ".html", d .. ".js" }))
      end, it.ivals(base_client_spa))))), true)

  target(
    { "test-build" },
    extend({
      test_dist_dir(base_server_run_sh),
      test_dist_dir(base_server_nginx_cfg),
      test_dist_dir(base_server_nginx_daemon_cfg),
      test_server_dir(base_server_lua_modules_ok),
      test_client_dir(base_client_lua_modules_ok) },
      amap(extend({},
        base_client_static, base_client_assets),
      test_dist_dir_client_stripped),
      amap(extend({},
        base_client_pages),
      test_dist_dir_client),
      it.collect(it.flatten(it.map(function (d)
        return it.map(test_dist_dir_client_stripped, it.ivals({ d .. ".html", d .. ".js" }))
      end, it.ivals(base_client_spa))))), true)

  target(
    { "start" },
    { "build" },
    function (_, _, background)
      return pushd(dist_dir(), function ()
        execute({
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
      return pushd(test_dist_dir(), function ()
        execute({
          "sh", "run.sh",
          env = {
            [base_env.var("BACKGROUND")] = (background or opts.background) and "1" or "0"
          },
        })
      end)
    end)

  target(
    { "test" },
    amap(extend({}, base_server_test_specs), test_server_dir_stripped),
    function (_, _, iterating)

      build({ "stop", "test-stop" }, opts.verbosity)
      build({ "test-start" }, opts.verbosity, true)

      local config_file = absolute(opts.config_file)

      local config = {
        type = "lib",
        env = tbl.assign({
          name = opts.config.env.name .. "-server",
          version = opts.config.env.version,
        }, opts.config.env.server, false)
      }

      return pushd(test_server_dir(), function ()

        local lib = require("santoku.make.project").init({
          config_file = config_file,
          luarocks_config = absolute(base_server_luarocks_cfg),
          config = config,
          single = opts.single,
          profile = opts.profile,
          skip_coverage = opts.skip_coverage,
          lua = test_server_env.lua,
          lua_path = test_server_env.lua_path,
          lua_cpath = test_server_env.lua_cpath,
        })

        lib.test({ skip_check = true })

        if not iterating then
          build({ "test-stop" }, opts.verbosity)
        end

        lib.check()

      end)
    end)

  target({ "iterate" }, {}, function (_, _)

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

      end, pcall(build, { "test" }, opts.verbosity, true))

      execute({
        "inotifywait", "-qr",
        "-e", "close_write", "-e", "modify",
        "-e", "move", "-e", "create", "-e", "delete",
        spread(collect(filter(function (fp)
          return exists(fp)
        end, chain(files("."), ivals({ "client", "server" })))))
      })

    end

  end)

  target({ "stop" }, {}, function ()
    mkdirp(dist_dir())
    return pushd(dist_dir(), function ()
      if exists("server.pid") then
        execute({ "kill", smatch(readfile("server.pid"), "(%d+)") })
      end
    end)
  end)

  target({ "test-stop" }, {}, function (_, _)
    mkdirp(test_dist_dir())
    return pushd(test_dist_dir(), function ()
      if exists("server.pid") then
        execute({ "kill", smatch(readfile("server.pid"), "(%d+)") })
      end
    end)
  end)

  return {

    config = opts.config,

    test = function (opts)
      opts = opts or {}
      build(assign({ "test" }, opts), opts.verbosity)
    end,

    iterate = function (opts)
      opts = opts or {}
      build(assign({ "iterate" }, opts), opts.verbosity)
    end,

    build = function (opts)
      opts = opts or {}
      build(assign({ opts.test and "test-build" or "build" }, opts), opts.verbosity)
    end,

    start = function (opts)
      opts = opts or {}
      build(assign({ opts.test and "test-start" or "start" }, opts), opts.verbosity)
    end,

    stop = function (opts)
      opts = opts or {}
      build(assign({ "stop", "test-stop" }, opts), opts.verbosity)
    end,

  }

end

return {
  init = init,
  create = create,
}
