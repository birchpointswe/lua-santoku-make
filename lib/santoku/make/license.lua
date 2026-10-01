local fs = require("santoku.fs")
local str = require("santoku.string")
local arr = require("santoku.array")
local num = require("santoku.num")
local sys = require("santoku.system")
local err = require("santoku.error")
local strip = require("santoku.lpeg.strip")

local spdx_url = "https://raw.githubusercontent.com/spdx/license-list-data/main/text/%s.txt"

local function first_year (dir)
  local year
  for line in sys.sh({ "git", "-C", dir, "log", "--max-parents=0", "--format=%ad", "--date=format:%Y", "HEAD" }) do
    local y = tonumber(line)
    if y then
      year = year and num.min(year, y) or y
    end
  end
  if not year then
    err.error("license: no commits in " .. dir .. ", so there's no first-commit year")
  end
  return tostring(year)
end

local function tracked (dir)
  local out = {}
  for line in sys.sh({ "git", "-C", dir, "ls-files" }) do
    if line ~= "" then
      arr.push(out, line)
    end
  end
  return out
end

local function header_lines (id, year, holder)
  return {
    "SPDX-License-Identifier: " .. id,
    "SPDX-FileCopyrightText: " .. year .. " " .. holder,
  }
end

local function line_end (src, pos)
  return str.find(src, "\n", pos, true) or #src
end

local function stale_span (src, pos)
  local e = line_end(src, pos)
  if not str.find(str.sub(src, pos, e), "SPDX-License-Identifier:", 1, true) then
    return nil
  end
  for _ = 1, 2 do
    local e2 = line_end(src, e + 1)
    if str.find(str.sub(src, e + 1, e2), "SPDX-FileCopyrightText:", 1, true) then
      return e2
    end
    e = e2
  end
  return nil
end

local function foreign (src, pos)
  local e = pos - 1
  for _ = 1, 5 do
    e = line_end(src, e + 1)
  end
  local head = str.sub(src, pos, e)
  return str.find(head, "Copyright", 1, true) or str.find(head, "copyright", 1, true)
    or str.find(head, "SPDX-", 1, true)
end

local function file_status (src, fp, lines)
  local text, pos = strip.license_at(src, fp, lines)
  if not text then
    return "skip"
  end
  if str.sub(src, pos, pos + #text - 1) == text then
    return "ok"
  end
  local stale = stale_span(src, pos)
  if stale then
    return "stale", str.sub(src, 1, pos - 1) .. text .. str.sub(src, stale + 1)
  end
  if foreign(src, pos) then
    return "foreign"
  end
  return "missing", str.sub(src, 1, pos - 1) .. text .. str.sub(src, pos)
end

local function fetch_text (id)
  local parts = {}
  for line in sys.sh({ "curl", "-fsSL", str.format(spdx_url, id) }) do
    arr.push(parts, line)
  end
  if #parts == 0 then
    err.error("license: empty license text for " .. id)
  end
  return arr.concat(parts, "\n") .. "\n"
end

local function license_text (id, year, holder)
  if id then
    local text = fetch_text(id)
    text = str.gsub(text, "<year>", year)
    text = str.gsub(text, "<copyright holders>", holder)
    return text
  end
  return "Copyright " .. year .. " " .. holder .. ". All rights reserved.\n"
end

local function resolve (opts)
  local dir = opts.dir or "."
  local id = opts.license
  local holder = opts.copyright
  if id and not holder then
    err.error("license: a license needs a copyright holder; set copyright")
  end
  return dir, id, holder
end

local function warnings (id, holder)
  local out = {}
  if not holder then
    arr.push(out, "copyright is not set, so this project is all rights reserved with no notice")
  end
  if not id then
    arr.push(out, "license is not set, so this project is all rights reserved")
  end
  return out
end

local function excluded (fp, exclude)
  for i = 1, #exclude do
    if str.match(fp, exclude[i]) then
      return true
    end
  end
  return false
end

local function walk (dir, id, holder, year, files, exclude, write)
  local report = { ok = {}, missing = {}, stale = {}, foreign = {}, skipped = {} }
  local lines = header_lines(id, year, holder)
  for i = 1, #files do
    local fp = files[i]
    local abs = fs.join(dir, fp)
    if excluded(fp, exclude) then
      arr.push(report.skipped, fp)
    elseif fs.isfile(abs) then
      local status, updated = file_status(fs.readfile(abs), fp, lines)
      if status == "skip" then
        arr.push(report.skipped, fp)
      else
        arr.push(report[status], fp)
        if write and updated then
          fs.writefile(abs, updated)
        end
      end
    end
  end
  return report
end

local function headers (opts)
  local dir, id, holder = resolve(opts)
  if not id then
    err.error("license: headers need a license id")
  end
  local year = opts.year or first_year(dir)
  local report = walk(dir, id, holder, year, opts.files or tracked(dir), opts.exclude or {}, true)
  report.year = year
  return report
end

local function apply (opts)
  local dir, id, holder = resolve(opts)
  local report = { warnings = warnings(id, holder) }
  if not holder then
    return report
  end
  local year = opts.year or first_year(dir)
  fs.writefile(fs.join(dir, "LICENSE"), license_text(id, year, holder))
  if id then
    report = headers({
      dir = dir, license = id, copyright = holder, year = year,
      files = opts.files, exclude = opts.exclude,
    })
    report.warnings = warnings(id, holder)
  end
  report.year = year
  return report
end

local function check (opts)
  local dir, id, holder = resolve(opts)
  local problems = {}
  if not holder then
    return problems, warnings(id, holder)
  end
  local year = opts.year or first_year(dir)
  local lic = fs.join(dir, "LICENSE")
  if not fs.exists(lic) then
    arr.push(problems, "LICENSE is missing")
  else
    local text = fs.readfile(lic)
    if id then
      if str.find(text, "<year>", 1, true) or str.find(text, "<copyright holders>", 1, true) then
        arr.push(problems, "LICENSE still has unfilled placeholders")
      elseif not str.find(text, year .. " " .. holder, 1, true) then
        arr.push(problems, "LICENSE doesn't name " .. year .. " " .. holder)
      end
    elseif text ~= license_text(nil, year, holder) then
      arr.push(problems, "LICENSE isn't the all-rights-reserved line for " .. year .. " " .. holder)
    end
  end
  if id then
    local report = walk(dir, id, holder, year, opts.files or tracked(dir), opts.exclude or {}, false)
    for _, k in ipairs({ "missing", "stale", "foreign" }) do
      for j = 1, #report[k] do
        arr.push(problems, report[k][j] .. ": " .. k .. " header")
      end
    end
  end
  return problems, warnings(id, holder)
end

local function project_files (dir)
  local base = fs.absolute(dir)
  local out = {}
  for fp in fs.files(base, true) do
    local rel = str.sub(fp, #base + 2)
    if not str.match(rel, "^%.git/") then
      arr.push(out, rel)
    end
  end
  return out
end

local function unheader (dir, files)
  local lines = header_lines("x", "x", "x")
  for i = 1, #files do
    local abs = fs.join(dir, files[i])
    local src = fs.readfile(abs)
    local text, pos = strip.license_at(src, files[i], lines)
    local stale = text and stale_span(src, pos)
    if stale then
      fs.writefile(abs, str.sub(src, 1, pos - 1) .. str.sub(src, stale + 1))
    end
  end
end

local function descriptor_lines (indent, id, holder)
  local out = {}
  if id then
    arr.push(out, indent .. "license = " .. str.quote(id) .. ",\n")
  end
  if holder then
    arr.push(out, indent .. "copyright = " .. str.quote(holder) .. ",\n")
  end
  return arr.concat(out)
end

local function scaffold (opts)
  local dir, id, holder = resolve(opts)
  local lic = fs.join(dir, "LICENSE")
  if fs.exists(lic) then
    fs.rm(lic)
  end
  local files = project_files(dir)
  unheader(dir, files)
  local mk = fs.join(dir, "make.lua")
  local src = fs.readfile(mk)
  local out, n = str.gsub(src, "\n([ ]*)license = \"[^\"]*\",\n", function (indent)
    return "\n" .. descriptor_lines(indent, id, holder)
  end)
  if n ~= 1 then
    err.error("license: expected one license field in the scaffold's make.lua, found " .. n)
  end
  fs.writefile(mk, out)
  if holder then
    apply({
      dir = dir, license = id, copyright = holder, year = opts.year,
      files = files,
    })
  end
  return warnings(id, holder)
end

return {
  apply = apply,
  headers = headers,
  check = check,
  scaffold = scaffold,
  warnings = warnings,
  first_year = first_year,
  file_status = file_status,
}
