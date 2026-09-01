
local fs = require("santoku.fs")
local tmpl = require("santoku.template")
local str = require("santoku.string")
local tbl = require("santoku.table")
local arr = require("santoku.array")
local err = require("santoku.error")
local sys = require("santoku.system")
local senv = require("santoku.env")

local embedded_source = senv.searchpath("santoku.make.common", package.path)

local function watch_snapshot (paths)
  local posix = require("santoku.make.posix")
  local snap = {}
  for i = 1, #paths do
    local p = paths[i]
    if fs.exists(p) then
      if fs.isdir(p) then
        for fp in fs.files(p, true) do
          snap[fp] = posix.time(fp)
        end
      else
        snap[p] = posix.time(p)
      end
    end
  end
  return snap
end

local function watch_changed (before, after)
  for fp, t in pairs(after) do
    if before[fp] ~= t then
      return true
    end
  end
  for fp in pairs(before) do
    if after[fp] == nil then
      return true
    end
  end
  return false
end

local function get_action(fp, config)
  config = config or {}
  if str.endswith(fp, ".d") then
    return "ignore"
  end
  local rules = tbl.get(config, {"env", "rules"}) or config.rules or {}
  local exclude = tbl.get(rules, {"exclude"}) or {}
  for i = 1, #exclude do
    if str.match(fp, exclude[i]) then return "ignore" end
  end
  local copy = tbl.get(rules, {"copy"}) or {}
  for i = 1, #copy do
    if str.match(fp, copy[i]) then return "copy" end
  end
  if not (str.find(fp, "%.tk$") or str.find(fp, "%.tk%.")) then
    return "copy"
  end
  return "template"
end

local function force_template(fp, config)
  config = config or {}
  local rules = tbl.get(config, {"env", "rules"}) or config.rules or {}
  local template = tbl.get(rules, {"template"}) or {}
  for i = 1, #template do
    if str.match(fp, template[i]) then return true end
  end
  return false
end

local function remove_tk(fp, config)
  return get_action(fp, config) == "template"
    and str.gsub(fp, "%.tk", "")
    or fp
end

local function add_copied_target(target_fn, dest, src, extra_srcs)
  target_fn({ dest }, arr.flatten({ src, extra_srcs or {} }), function ()
    fs.mkdirp(fs.dirname(dest))
    fs.writefile(dest, fs.readfile(src))
  end)
end

local function get_lua_version()
  return (str.match(_VERSION, "(%d+.%d+)"))
end

local function get_require_paths(prefix, ...)
  local pfx = prefix and fs.join(prefix, "lua_modules") or "lua_modules"
  local ver = get_lua_version()
  local t = {}
  for i = 1, select("#", ...) do
    local n = select(i, ...)
    arr.push(t, fs.join(pfx, str.format(n, ver)))
  end
  return arr.concat(t, ";")
end

local function get_lua_path(prefix)
  return get_require_paths(prefix,
    "share/lua/%s/?.lua",
    "share/lua/%s/?/init.lua",
    "lib/lua/%s/?.lua",
    "lib/lua/%s/?/init.lua")
end

local function get_lua_cpath(prefix)
  return get_require_paths(prefix,
    "lib/lua/%s/?.so",
    "lib/lua/%s/loadall.so")
end

local function luarocks_var (name)
  local val
  local ok = pcall(function ()
    for line in sys.sh({ "luarocks", "config", "variables." .. name }) do
      local v = str.match(line, "^%s*(.-)%s*$")
      if v ~= "" then
        val = v
      end
    end
  end)
  return ok and val or nil
end

local function get_bundle_flags ()
  local flags = {}
  local incdir = luarocks_var("LUA_INCDIR")
  local libdir = luarocks_var("LUA_LIBDIR")
  local lualib = luarocks_var("LUALIB")
  if incdir then
    arr.push(flags, "-I" .. incdir)
  end
  if libdir then
    arr.push(flags, "-L" .. libdir, "-Wl,-rpath," .. libdir)
  end
  arr.push(flags, "-l" .. (lualib and str.match(lualib, "^lib(.-)%.[^.]+$") or "lua"), "-lm")
  return flags
end

local function with_build_deps(build_deps_dir, fn)
  if not build_deps_dir then
    return fn()
  end
  local old_path = package.path
  local old_cpath = package.cpath
  local deps_path = get_lua_path(build_deps_dir)
  local deps_cpath = get_lua_cpath(build_deps_dir)
  package.path = deps_path .. ";" .. old_path
  package.cpath = deps_cpath .. ";" .. old_cpath
  return (function (...)
    package.path = old_path
    package.cpath = old_cpath
    return ...
  end)(fn())
end

local function get_config_files(config_file)
  if not config_file then
    return {}
  end
  local files = { config_file }
  local dir = fs.dirname(config_file)
  local common_cfg = dir == "." and "make.common.lua" or fs.join(dir, "make.common.lua")
  if fs.exists(common_cfg) then
    arr.push(files, common_cfg)
  end
  return files
end

local function add_file_target(target_fn, dest, src, env, config, config_file, extra_srcs, build_deps_dir, build_deps_ok)
  local action = get_action(src, config)
  if action == "copy" then
    return add_copied_target(target_fn, dest, src, extra_srcs)
  elseif action == "template" then
    dest = str.gsub(dest, "%.tk", "")
    target_fn({ dest }, arr.flatten({ src, get_config_files(config_file), extra_srcs or {}, build_deps_ok or {} }), function ()
      fs.mkdirp(fs.dirname(dest))
      local deps = {}
      env.readfile = function (fp) deps[fp] = true; return fs.readfile(fp) end
      local t = with_build_deps(build_deps_dir, function ()
        return tmpl.renderfile(src, env, _G)
      end)
      fs.writefile(dest, t)
      fs.writefile(dest .. ".d", tmpl.serialize_deps(src, dest, deps))
    end)
  end
end

local function add_templated_target_base64(target_fn, dest, data, env, config_file, extra_srcs, build_deps_dir, build_deps_ok)
  target_fn({ dest }, arr.flatten({ get_config_files(config_file), extra_srcs or {}, build_deps_ok or {},
    embedded_source and { embedded_source } or {} }), function ()
    fs.mkdirp(fs.dirname(dest))
    local deps = {}
    env.readfile = function (fp) deps[fp] = true; return fs.readfile(fp) end
    local t = with_build_deps(build_deps_dir, function ()
      return tmpl.render(str.from_base64(data), env, _G)
    end)
    fs.writefile(dest, t)
    fs.writefile(dest .. ".d", tmpl.serialize_deps(dest, config_file, deps))
  end)
end

local function get_files(dir, config, check_tpl)
  local tpl = check_tpl and {} or nil
  local result = {}
  local seen = {}
  if fs.exists(dir) then
    for fp in fs.files(dir, true) do
      if get_action(fp, config) ~= "ignore" then
        if check_tpl and force_template(fp, config) then
          arr.push(tpl, fp)
        else
          arr.push(result, fp)
        end
        seen[fp] = true
      end
    end
  end
  local rules = tbl.get(config or {}, {"env", "rules"}) or (config or {}).rules or {}
  local include = tbl.get(rules, {"include"}) or {}
  for i = 1, #include do
    local fp = include[i]
    if not seen[fp] and str.startswith(fp, dir .. "/") then
      arr.push(result, fp)
      seen[fp] = true
    end
  end
  return result, tpl
end

local function local_dep_wanted(spec, target)
  if type(spec) ~= "table" or not spec.targets then
    return true
  end
  if not target then
    return true
  end
  for i = 1, #spec.targets do
    if spec.targets[i] == target then
      return true
    end
  end
  return false
end

local function local_dep_paths(root_dir, config, target)
  local specs = tbl.get(config or {}, {"env", "local_deps"}) or {}
  local paths = {}
  for i = 1, #specs do
    local spec = specs[i]
    if local_dep_wanted(spec, target) then
      local p = type(spec) == "table" and spec.path or spec
      if type(p) ~= "string" then
        err.error("local_deps entry must be a path or a table with a path field", i)
      end
      if not str.startswith(p, "/") then
        p = fs.join(root_dir, p)
      end
      if not fs.isdir(p) then
        err.error("local_deps path not found", p)
      end
      if not fs.exists(fs.join(p, "make.lua")) then
        err.error("local_deps path has no make.lua (submodule not initialized?)", p)
      end
      arr.push(paths, p)
    end
  end
  return paths
end

local function local_dep_srcs(paths)
  local srcs = {}
  for i = 1, #paths do
    for _, d in ipairs({ "lib", "bin", "deps", "res" }) do
      local dir = fs.join(paths[i], d)
      if fs.exists(dir) then
        for fp in fs.files(dir, true) do
          arr.push(srcs, fp)
        end
      end
    end
    for _, f in ipairs({ "make.lua", "make.common.lua" }) do
      local fp = fs.join(paths[i], f)
      if fs.exists(fp) then
        arr.push(srcs, fp)
      end
    end
  end
  return srcs
end

local function clear_stale_lock (...)
  for i = 1, select("#", ...) do
    local root = select(i, ...)
    if root and fs.isdir(root) then
      local stale = { "lockfile.lfs" }
      for name in fs.dir(root) do
        if str.match(name, "^%.lock%.tmp%.") then
          arr.push(stale, name)
        end
      end
      for j = 1, #stale do
        os.remove(fs.join(root, stale[j]))
      end
    end
  end
end

local function install_local_deps(paths, lcfg)
  for i = 1, #paths do
    local p = paths[i]
    fs.pushd(p, function ()
      local m = require("santoku.make.project").init({
        skip_tests = true,
        in_local_dep = true,
        luarocks_config = lcfg,
      })
      if not m.install then
        err.error("local_deps entry is not a lib project", p)
      end
      (function (ok, ...)
        if not ok then
          err.error("local dep install failed", p, ...)
        end
      end)(err.pcall(m.install))
    end)
  end
end

local function compute_file_hash(filepath)
  local handle = io.popen("sha256sum " .. str.quote(filepath))
  local output = handle:read("*a")
  handle:close()
  local hash = str.match(output, "^(%x+)")
  return str.sub(hash, 1, 12)
end

local function compute_string_hash(content)
  local tmp = os.tmpname()
  local f = io.open(tmp, "wb")
  f:write(content)
  f:close()
  local h = compute_file_hash(tmp)
  os.remove(tmp)
  return h
end

local function hash_filename(filepath, hash)
  local dir = fs.dirname(filepath)
  local base = fs.basename(filepath)
  local name, ext = str.match(base, "^(.+)(%.[^.]+)$")
  if not name then
    name, ext = base, ""
  end
  local hashed_name = name .. "." .. hash .. ext
  return dir and dir ~= "" and dir ~= "." and fs.join(dir, hashed_name) or hashed_name
end

local function substitute_refs (content, manifest)
  for orig, h in pairs(manifest) do
    if str.find(content, orig, 1, true) then
      content = str.gsub(content, "\"" .. str.escape(orig) .. "\"", "\"" .. h .. "\"")
      content = str.gsub(content, "'" .. str.escape(orig) .. "'", "'" .. h .. "'")
      content = str.gsub(content, "\"/" .. str.escape(orig) .. "\"", "\"/" .. h .. "\"")
      content = str.gsub(content, "'/" .. str.escape(orig) .. "'", "'/" .. h .. "'")
      content = str.gsub(content, "url%(/" .. str.escape(orig) .. "%)", "url(/" .. h .. ")")
      content = str.gsub(content, "url%(" .. str.escape(orig) .. "%)", "url(" .. h .. ")")
    end
  end
  return content
end

local function hash_token (name)
  return "___TKHASH_" .. (str.gsub(name, ".", function (c)
    return str.format("%02x", str.byte(c))
  end)) .. "___"
end

local function resolve_tokens (content, manifest, strict, src)
  return (str.gsub(content, "___TKHASH_(%x+)___", function (hex)
    local name = str.gsub(hex, "%x%x", function (b)
      return str.char(tonumber(b, 16))
    end)
    local h = manifest[name]
    if h then
      return h
    end
    if strict then
      err.error("unresolvable hashed() reference", src, name)
    end
  end))
end

local text_extensions = {
  html = true, htm = true, css = true, js = true, json = true,
  xml = true, svg = true, txt = true, md = true, lua = true,
  map = true,
}

local function is_text_file(filepath)
  local ext = str.match(filepath, "%.([^.]+)$")
  return ext and text_extensions[str.lower(ext)]
end

return {
  watch_snapshot = watch_snapshot,
  watch_changed = watch_changed,
  get_action = get_action,
  force_template = force_template,
  remove_tk = remove_tk,
  add_copied_target = add_copied_target,
  add_file_target = add_file_target,
  add_templated_target_base64 = add_templated_target_base64,
  with_build_deps = with_build_deps,
  get_lua_version = get_lua_version,
  get_require_paths = get_require_paths,
  get_lua_path = get_lua_path,
  get_lua_cpath = get_lua_cpath,
  get_bundle_flags = get_bundle_flags,
  get_config_files = get_config_files,
  get_files = get_files,
  local_dep_paths = local_dep_paths,
  local_dep_srcs = local_dep_srcs,
  install_local_deps = install_local_deps,
  clear_stale_lock = clear_stale_lock,
  compute_file_hash = compute_file_hash,
  compute_string_hash = compute_string_hash,
  hash_filename = hash_filename,
  substitute_refs = substitute_refs,
  hash_token = hash_token,
  resolve_tokens = resolve_tokens,
  is_text_file = is_text_file,
}
