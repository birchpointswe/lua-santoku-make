-- Common utilities shared between lib and web project builders

local fs = require("santoku.fs")
local fun = require("santoku.functional")
local tmpl = require("santoku.template")
local str = require("santoku.string")
local tbl = require("santoku.table")
local varg = require("santoku.varg")
local arr = require("santoku.array")
local iter = require("santoku.iter")

-- Determine action for a file: "copy", "template", or "ignore"
local function get_action(fp, config)
  config = config or {}
  local match_fp = fun.bind(str.match, fp)
  local rules = tbl.get(config, "env", "rules") or config.rules or {}
  if iter.find(match_fp, iter.ivals(tbl.get(rules, "exclude") or {})) then
    return "ignore"
  elseif iter.find(match_fp, iter.ivals(tbl.get(rules, "copy") or {}))
    or not (str.find(fp, "%.tk$") or str.find(fp, "%.tk%."))
  then
    return "copy"
  else
    return "template"
  end
end

-- Check if file matches rules.template pattern
local function force_template(fp, config)
  config = config or {}
  local match_fp = fun.bind(str.match, fp)
  local rules = tbl.get(config, "env", "rules") or config.rules or {}
  return iter.find(match_fp, iter.ivals(tbl.get(rules, "template") or {}))
end

-- Remove .tk extension from template files
local function remove_tk(fp, config)
  return get_action(fp, config) == "template"
    and str.gsub(fp, "%.tk", "")
    or fp
end

-- Create a target that copies a file
local function add_copied_target(target_fn, dest, src, extra_srcs)
  extra_srcs = extra_srcs or {}
  target_fn({ dest }, arr.extend({ src }, extra_srcs), function ()
    fs.mkdirp(fs.dirname(dest))
    fs.writefile(dest, fs.readfile(src))
  end)
end

-- Get Lua version from _VERSION global
local function get_lua_version()
  return (str.match(_VERSION, "(%d+.%d+)"))
end

-- Build require paths for lua_modules
local function get_require_paths(prefix, ...)
  local pfx = prefix and fs.join(prefix, "lua_modules") or "lua_modules"
  local ver = get_lua_version()
  return arr.concat(varg.reduce(function (t, n)
    return arr.push(t, fs.join(pfx, str.format(n, ver)))
  end, {}, ...), ";")
end

-- Get LUA_PATH for a prefix
local function get_lua_path(prefix)
  return get_require_paths(prefix,
    "share/lua/%s/?.lua",
    "share/lua/%s/?/init.lua",
    "lib/lua/%s/?.lua",
    "lib/lua/%s/?/init.lua")
end

-- Get LUA_CPATH for a prefix
local function get_lua_cpath(prefix)
  return get_require_paths(prefix,
    "lib/lua/%s/?.so",
    "lib/lua/%s/loadall.so")
end

-- Helper to run a function with modified package paths
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
  return varg.tup(function (...)
    package.path = old_path
    package.cpath = old_cpath
    return ...
  end, fn())
end

-- Create a target that processes a file (copy or template)
local function add_file_target(target_fn, dest, src, env, config, config_file, extra_srcs, build_deps_dir, build_deps_ok)
  extra_srcs = extra_srcs or {}
  local action = get_action(src, config)
  if action == "copy" then
    return add_copied_target(target_fn, dest, src, extra_srcs)
  elseif action == "template" then
    dest = str.gsub(dest, "%.tk", "")
    local deps = arr.extend({ src, config_file }, extra_srcs)
    if build_deps_ok then
      arr.push(deps, build_deps_ok)
    end
    target_fn({ dest }, deps, function ()
      fs.mkdirp(fs.dirname(dest))
      local t, ds = with_build_deps(build_deps_dir, function ()
        return tmpl.renderfile(src, env, _G)
      end)
      fs.writefile(dest, t)
      fs.writefile(dest .. ".d", tmpl.serialize_deps(src, dest, ds))
    end)
  end
end

-- Create a target from base64-encoded template data
local function add_templated_target_base64(target_fn, dest, data, env, config_file, extra_srcs, build_deps_dir, build_deps_ok)
  extra_srcs = extra_srcs or {}
  local deps = arr.extend({ config_file }, extra_srcs)
  if build_deps_ok then
    arr.push(deps, build_deps_ok)
  end
  target_fn({ dest }, deps, function ()
    fs.mkdirp(fs.dirname(dest))
    local t, ds = with_build_deps(build_deps_dir, function ()
      return tmpl.render(str.from_base64(data), env, _G)
    end)
    fs.writefile(dest, t)
    fs.writefile(dest .. ".d", tmpl.serialize_deps(dest, config_file, ds))
  end)
end

-- Scan directory for files, optionally checking for template patterns
local function get_files(dir, config, check_tpl)
  local tpl = check_tpl and {} or nil
  if not fs.exists(dir) then
    return {}, tpl
  end
  return iter.collect(iter.filter(function (fp)
    if check_tpl and force_template(fp, config) then
      arr.push(tpl, fp)
      return false
    end
    return get_action(fp, config) ~= "ignore"
  end, fs.files(dir, true))), tpl
end

local function compute_file_hash(filepath)
  local handle = io.popen("sha256sum " .. str.quote(filepath))
  local output = handle:read("*a")
  handle:close()
  local hash = str.match(output, "^(%x+)")
  return str.sub(hash, 1, 12)
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
  get_files = get_files,
  compute_file_hash = compute_file_hash,
  hash_filename = hash_filename,
  is_text_file = is_text_file,
}
