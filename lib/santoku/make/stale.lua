-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2023 Birch Point SWE
local fs = require("santoku.fs")
local str = require("santoku.string")
local arr = require("santoku.array")
local sys = require("santoku.system")

local deltas = {
  dev = 120000000, scm = 110000000, cvs = 100000000,
  rc = -1000, pre = -10000, beta = -100000, alpha = -1000000,
}

local function parse (s)
  local v = {}
  local main, rev = str.match(s, "^(.*)%-(%d+)$")
  if rev then
    s = main
    v.revision = tonumber(rev)
  end
  local i = 1
  while #s > 0 do
    local tok, rest = str.match(s, "^(%d+)[%.%-_]*(.*)")
    if tok then
      v[i] = v[i] and v[i] + tonumber(tok) / 100000 or tonumber(tok)
      i = i + 1
    else
      tok, rest = str.match(s, "^(%a+)[%.%-_]*(.*)")
      if not tok then
        v[i] = 0
        break
      end
      v[i] = deltas[tok] or str.byte(tok) / 1000
    end
    s = rest
  end
  return v
end

local function lt (a, b)
  for i = 1, #a > #b and #a or #b do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then
      return x < y
    end
  end
  if a.revision and b.revision then
    return a.revision < b.revision
  end
  return false
end

local function eq (a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  if a.revision and b.revision then
    return a.revision == b.revision
  end
  return true
end

local function partial (v, r)
  for i = 1, #r do
    if r[i] ~= (v[i] or 0) then
      return false
    end
  end
  if r.revision then
    return r.revision == v.revision
  end
  return true
end

local ops = {
  ["=="] = eq,
  ["~="] = function (v, c) return not eq(v, c) end,
  [">"] = function (v, c) return lt(c, v) end,
  ["<"] = lt,
  [">="] = function (v, c) return not lt(v, c) end,
  ["<="] = function (v, c) return not lt(c, v) end,
  ["~>"] = partial,
}

local function satisfies (v, constraints)
  for i = 1, #constraints do
    local c = constraints[i]
    if not ops[c.op](v, type(c.version) == "string" and parse(c.version) or c.version) then
      return false
    end
  end
  return true
end

local function manifest (rocks_dir)
  local fp = fs.join(rocks_dir, "manifest")
  if not fs.exists(fp) then
    return nil
  end
  local env = {}
  fs.runfile(fp, env, true)
  return env
end

local function newest (versions)
  local best, bv
  for s in pairs(versions) do
    local v = parse(s)
    if not bv or lt(bv, v) then
      best, bv = s, v
    end
  end
  return best
end

local function rocks (tree_rocks_dir, home_rocks_dir, skip)
  local tree = manifest(tree_rocks_dir)
  local home = manifest(home_rocks_dir)
  if not (tree and home) then
    return {}
  end
  local current = {}
  for name, versions in pairs(tree.repository or {}) do
    current[name] = newest(versions)
  end
  local constraints = {}
  for name, ver in pairs(current) do
    local deps = tree.dependencies and tree.dependencies[name] and tree.dependencies[name][ver] or {}
    for i = 1, #deps do
      constraints[deps[i].name] = constraints[deps[i].name] or {}
      arr.push(constraints[deps[i].name], deps[i].constraints or {})
    end
  end
  local out = {}
  for name, ver in pairs(current) do
    local installed = home.repository and home.repository[name]
    if installed and not (skip and skip[name]) then
      local v = parse(ver)
      local cons = constraints[name] or {}
      local best, bv
      for s in pairs(installed) do
        local w = parse(s)
        if lt(v, w) and (not bv or lt(bv, w)) then
          local ok = true
          for i = 1, #cons do
            ok = ok and satisfies(w, cons[i])
          end
          if ok then
            best, bv = s, w
          end
        end
      end
      if best then
        arr.push(out, { name = name, version = ver, newer = best })
      end
    end
  end
  arr.sort(out, function (a, b)
    return a.name < b.name
  end)
  return out
end

local home_dir

local function home_rocks_dir ()
  if not home_dir then
    for line in sys.sh({ "env", "-u", "LUAROCKS_CONFIG", "luarocks", "config", "rocks_dir" }) do
      local v = str.match(line, "^%s*(.-)%s*$")
      if v ~= "" then
        home_dir = v
      end
    end
  end
  return home_dir
end

local function refresh (tree, stamp, markers, skip)
  local rocks_dir = fs.join(tree, "lib", "luarocks", "rocks-5.1")
  if not fs.exists(fs.join(rocks_dir, "manifest")) then
    return false
  end
  local stale = rocks(rocks_dir, home_rocks_dir(), skip())
  local seen = {}
  if fs.exists(stamp) then
    for line in str.gmatch(fs.readfile(stamp), "[^\n]+") do
      seen[line] = true
    end
  end
  local fresh = {}
  for i = 1, #stale do
    local s = stale[i]
    local key = s.name .. " " .. s.newer
    if seen[key] then
      fs.stderr:write("toku: " .. tree .. " resolved " .. s.name .. " " .. s.version .. " again after a clear for "
        .. s.newer .. "; luarocks' servers may not offer " .. s.newer .. " yet\n")
    else
      arr.push(fresh, s)
      seen[key] = true
    end
  end
  if #fresh == 0 then
    return false
  end
  for i = 1, #fresh do
    local s = fresh[i]
    fs.stderr:write("toku: clearing " .. tree .. ": it holds " .. s.name .. " " .. s.version .. ", and "
      .. s.newer .. " is installed and in range\n")
  end
  sys.execute({ "rm", "-rf", tree })
  for i = 1, #markers do
    fs.rm(markers[i], true)
  end
  local keys = {}
  for k in pairs(seen) do
    arr.push(keys, k)
  end
  arr.sort(keys)
  fs.mkdirp(fs.dirname(stamp))
  fs.writefile(stamp, arr.concat(keys, "\n") .. "\n")
  return true
end

local function prune (dir, keep)
  if not fs.isdir(dir) then
    return
  end
  local doomed = {}
  for fp in fs.dir(dir) do
    if fp ~= "." and fp ~= ".." and not keep[fp] then
      arr.push(doomed, fs.join(dir, fp))
    end
  end
  for i = 1, #doomed do
    sys.execute({ "rm", "-rf", doomed[i] })
  end
end

return {
  parse = parse,
  satisfies = satisfies,
  rocks = rocks,
  refresh = refresh,
  prune = prune,
}
