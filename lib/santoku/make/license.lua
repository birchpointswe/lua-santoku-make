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

local function list (v)
  if v == nil then
    return {}
  end
  if type(v) == "table" then
    return v
  end
  return { v }
end

local function glob_match (p, s, pi, si)
  pi = pi or 1
  si = si or 1
  while pi <= #p do
    if str.sub(p, pi, pi + 2) == "**/" then
      for k = si, #s + 1 do
        if (k == si or str.sub(s, k - 1, k - 1) == "/") and glob_match(p, s, pi + 3, k) then
          return true
        end
      end
      return false
    elseif str.sub(p, pi, pi + 1) == "**" then
      for k = si, #s + 1 do
        if glob_match(p, s, pi + 2, k) then
          return true
        end
      end
      return false
    end
    local c = str.sub(p, pi, pi)
    if c == "*" then
      for k = si, #s + 1 do
        if k > si and str.sub(s, k - 1, k - 1) == "/" then
          break
        end
        if glob_match(p, s, pi + 1, k) then
          return true
        end
      end
      return false
    end
    if c == "\\" then
      pi = pi + 1
      c = str.sub(p, pi, pi)
    end
    if str.sub(s, si, si) ~= c then
      return false
    end
    pi = pi + 1
    si = si + 1
  end
  return si > #s
end

local function matches_any (fp, globs)
  for i = 1, #globs do
    if glob_match(globs[i], fp) then
      return true
    end
  end
  return false
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

local comment_rules = {
  ["--"] = { line = "--", open = "--[[", close = "]]" },
  ["//"] = { line = "//", open = "/*", close = "*/" },
  ["/*"] = { open = "/*", close = "*/" },
  ["<!--"] = { open = "<!--", close = "-->" },
  ["#"] = { line = "#" },
}

local function comment_head (src, pos, opener)
  local rule = comment_rules[opener]
  local out = {}
  local inblock = false
  local s = pos
  for _ = 1, 5 do
    if s > #src then
      break
    end
    local e = line_end(src, s)
    local line = str.sub(src, s, e)
    local t = str.match(line, "^%s*(.-)%s*$")
    if inblock then
      arr.push(out, line)
      inblock = not str.find(t, rule.close, 1, true)
    elseif rule.open and str.sub(t, 1, #rule.open) == rule.open then
      arr.push(out, line)
      inblock = not str.find(t, rule.close, #rule.open + 1, true)
    elseif rule.line and str.sub(t, 1, #rule.line) == rule.line then
      arr.push(out, line)
    end
    s = e + 1
  end
  return arr.concat(out)
end

local function foreign (src, pos, opener)
  local head = comment_head(src, pos, opener)
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
  if foreign(src, pos, str.match(text, "^(%S+)")) then
    return "foreign"
  end
  return "missing", str.sub(src, 1, pos - 1) .. text .. str.sub(src, pos)
end

local wrap_width = 80

local function wrap (line, out)
  if #line <= wrap_width then
    arr.push(out, line)
    return
  end
  local indent = str.match(line, "^(%s*)")
  local cur = indent
  for word in str.gmatch(line, "%S+") do
    if cur ~= indent and #cur + 1 + #word > wrap_width then
      arr.push(out, cur)
      cur = indent .. word
    elseif cur == indent then
      cur = cur .. word
    else
      cur = cur .. " " .. word
    end
  end
  arr.push(out, cur)
end

local function reflow (lines, prefix, out)
  local para = {}
  local function flush ()
    if #para == 0 then
      return
    end
    local fits = true
    for i = 1, #para do
      if #prefix + #para[i] > wrap_width then
        fits = false
        break
      end
    end
    if fits then
      for i = 1, #para do
        arr.push(out, prefix .. para[i])
      end
    else
      local words = {}
      for i = 1, #para do
        arr.push(words, (str.match(para[i], "^%s*(.-)%s*$")))
      end
      wrap(prefix .. str.match(para[1], "^(%s*)") .. arr.concat(words, " "), out)
    end
    para = {}
  end
  for i = 1, #lines do
    if str.match(lines[i], "^%s*$") then
      flush()
      arr.push(out, "")
    else
      arr.push(para, lines[i])
    end
  end
  flush()
end

local holder_slots = { "<copyright holders>", "<owner>" }

local function fill (line, year, holder)
  if not str.find(line, "<year>", 1, true) then
    return nil
  end
  for i = 1, #holder_slots do
    local s, e = str.find(line, holder_slots[i], 1, true)
    if s then
      local filled = str.sub(line, 1, s - 1) .. holder .. str.sub(line, e + 1)
      local ys, ye = str.find(filled, "<year>", 1, true)
      return str.sub(filled, 1, ys - 1) .. year .. str.sub(filled, ye + 1)
    end
  end
  return nil
end

local function render (id, lines, year, holder)
  local done = {}
  local filled = false
  for i = 1, #lines do
    local line = lines[i]
    local f = not filled and fill(line, year, holder)
    if f then
      filled = true
      line = f
    end
    arr.push(done, line)
  end
  local out = {}
  reflow(done, "", out)
  if #out == 0 then
    err.error("license: empty license text for " .. id)
  end
  if not filled then
    err.error("license: the " .. id .. " text has no copyright line to fill, "
      .. "so toku license can't write it; keep that LICENSE by hand")
  end
  return arr.concat(out, "\n") .. "\n"
end

local function texts_source (texts)
  local cache = {}
  return function (id)
    if texts and texts[id] then
      return texts[id]
    end
    if not cache[id] then
      local lines = {}
      for line in sys.sh({ "curl", "-fsSL", str.format(spdx_url, id) }) do
        arr.push(lines, line)
      end
      while lines[#lines] == "" do
        lines[#lines] = nil
      end
      cache[id] = lines
    end
    return cache[id]
  end
end

local function managed_text (id, year, holder, text_of)
  if not id then
    return "Copyright " .. year .. " " .. holder .. ". All rights reserved.\n"
  end
  return render(id, text_of(id), year, holder)
end

local separator = str.rep("-", wrap_width)

local function component_label (c)
  local paths = list(c.path)
  local name = c.name .. (c.version and (" " .. c.version) or "")
  if #paths > 0 then
    return "This package vendors " .. name .. " (" .. arr.concat(paths, ", ") .. "), which is:"
  end
  return "This package links " .. name .. ", fetched from " .. c.source .. " at build time, which is:"
end

local function component_text (c, text_of)
  local notices = {}
  local copyrights = list(c.copyright)
  for i = 1, #copyrights do
    local line = copyrights[i]
    if not str.match(line, "^Copyright") then
      line = "Copyright " .. line
    end
    arr.push(notices, line)
  end
  local lines
  if c.text then
    lines = {}
    for line in str.gmatch((str.gsub(c.text, "\n+$", "")) .. "\n", "([^\n]*)\n") do
      arr.push(lines, line)
    end
  else
    lines = text_of(c.license)
  end
  local body = {}
  local placed = false
  for i = 1, #lines do
    if not placed and fill(lines[i], "y", "h") then
      for j = 1, #notices do
        arr.push(body, notices[j])
      end
      placed = true
    else
      arr.push(body, lines[i])
    end
  end
  if not placed and #notices > 0 then
    local pre = {}
    for j = 1, #notices do
      arr.push(pre, notices[j])
    end
    arr.push(pre, "")
    for j = 1, #body do
      arr.push(pre, body[j])
    end
    body = pre
  end
  local out = { separator, "" }
  wrap(component_label(c), out)
  arr.push(out, "")
  reflow(body, "  ", out)
  if c.note then
    arr.push(out, "")
    wrap(c.note, out)
  end
  return arr.concat(out, "\n") .. "\n"
end

local function split_license (text)
  local sections = {}
  local start = 1
  while true do
    local s = str.find(text, "\n%-%-%-%-%-%-%-%-%-%-+\n", start)
    if not s then
      break
    end
    arr.push(sections, str.sub(text, start, s))
    start = s + 1
  end
  arr.push(sections, str.sub(text, start))
  return sections
end

local function notice_count (text)
  local n = 0
  for _ in str.gmatch(text, "Copyright[^\n]-%d%d%d%d") do
    n = n + 1
  end
  return n
end

local function section_component (section, vendored)
  for i = 1, #vendored do
    local name = vendored[i].name
    if str.find(section, "This package vendors " .. name .. " ", 1, true)
      or str.find(section, "This package links " .. name .. ",", 1, true)
      or str.find(section, "This package links " .. name .. " ", 1, true) then
      return i
    end
  end
  return nil
end

local function section_name (section)
  local line = str.match(section, "This package [a-z]+ ([^\n]*)")
  return line or str.match(section, "%S[^\n]*") or "(empty)"
end

local function license_problems (text, vendored)
  local problems = {}
  local sections = split_license(text)
  if notice_count(sections[1]) > 1 then
    arr.push(problems, "LICENSE holds more than one copyright notice above any line of dashes; "
      .. "declare the third-party code in make.lua's vendored list")
  end
  local seen = {}
  for i = 2, #sections do
    local k = section_component(sections[i], vendored)
    if k then
      seen[k] = true
    else
      arr.push(problems, "LICENSE has a section make.lua doesn't declare: " .. section_name(sections[i]))
    end
  end
  for i = 1, #vendored do
    if not seen[i] then
      arr.push(problems, "LICENSE has no section for vendored " .. vendored[i].name)
    end
  end
  return problems, sections[1]
end

local function validate_vendored (vendored)
  for i = 1, #vendored do
    local c = vendored[i]
    if not c.name or not c.license then
      err.error("license: each vendored entry needs a name and a license", tostring(c.name))
    end
    if #list(c.path) == 0 and not c.source then
      err.error("license: vendored " .. c.name .. " needs a path, or a source URL for build-time code")
    end
  end
end

local function write_license (dir, text, vendored)
  local lic = fs.join(dir, "LICENSE")
  if fs.exists(lic) then
    local current = fs.readfile(lic)
    local sections = split_license(current)
    if notice_count(sections[1]) > 1 then
      err.error("license: LICENSE holds more than one copyright notice above any line of dashes, "
        .. "and rewriting it would drop one; declare that code in make.lua's vendored list")
    end
    for i = 2, #sections do
      if not section_component(sections[i], vendored) then
        err.error("license: LICENSE has a section make.lua doesn't declare, and rewriting it would "
          .. "drop it; declare it in make.lua's vendored list", section_name(sections[i]))
      end
    end
  end
  fs.writefile(lic, text)
end

local function resolve (opts)
  local dir = opts.dir or "."
  local id = opts.license
  local holder = opts.copyright
  if id and not holder then
    err.error("license: a license needs a copyright holder; set copyright")
  end
  local vendored = opts.vendored or {}
  validate_vendored(vendored)
  return dir, id, holder, vendored
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

local function skip_globs (exclude, vendored)
  local out = {}
  local ex = list(exclude)
  for i = 1, #ex do
    arr.push(out, ex[i])
  end
  for i = 1, #vendored do
    local paths = list(vendored[i].path)
    for j = 1, #paths do
      arr.push(out, paths[j])
    end
  end
  return out
end

local function walk (dir, id, holder, year, files, globs, write)
  local report = { ok = {}, missing = {}, stale = {}, foreign = {}, skipped = {} }
  local lines = header_lines(id, year, holder)
  for i = 1, #files do
    local fp = files[i]
    local abs = fs.join(dir, fp)
    if matches_any(fp, globs) then
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
  local dir, id, holder, vendored = resolve(opts)
  if not id then
    err.error("license: headers need a license id")
  end
  local year = opts.year or first_year(dir)
  local report = walk(dir, id, holder, year, opts.files or tracked(dir),
    skip_globs(opts.exclude, vendored), true)
  report.year = year
  return report
end

local function apply (opts)
  local dir, id, holder, vendored = resolve(opts)
  local report = { warnings = warnings(id, holder) }
  if not holder then
    return report
  end
  local year = opts.year or first_year(dir)
  local text_of = texts_source(opts.texts)
  local parts = { managed_text(id, year, holder, text_of) }
  for i = 1, #vendored do
    arr.push(parts, component_text(vendored[i], text_of))
  end
  write_license(dir, arr.concat(parts, "\n"), vendored)
  if id then
    report = headers({
      dir = dir, license = id, copyright = holder, year = year,
      files = opts.files, exclude = opts.exclude, vendored = vendored,
    })
    report.warnings = warnings(id, holder)
  end
  report.year = year
  return report
end

local function check (opts)
  local dir, id, holder, vendored = resolve(opts)
  local problems = {}
  if not holder then
    return problems, warnings(id, holder)
  end
  local year = opts.year or first_year(dir)
  local files = opts.files or tracked(dir)
  local lic = fs.join(dir, "LICENSE")
  if not fs.exists(lic) then
    arr.push(problems, "LICENSE is missing")
  else
    local found, text = license_problems(fs.readfile(lic), vendored)
    for i = 1, #found do
      arr.push(problems, found[i])
    end
    if id then
      if str.find(text, "<year>", 1, true) or str.find(text, "<copyright holders>", 1, true) then
        arr.push(problems, "LICENSE still has unfilled placeholders")
      elseif not str.find(text, year .. " " .. holder, 1, true) then
        arr.push(problems, "LICENSE doesn't name " .. year .. " " .. holder)
      end
    elseif str.gsub(text, "\n+$", "") ~= str.gsub(managed_text(nil, year, holder), "\n+$", "") then
      arr.push(problems, "LICENSE isn't the all-rights-reserved line for " .. year .. " " .. holder)
    end
  end
  for i = 1, #vendored do
    local paths = list(vendored[i].path)
    for j = 1, #paths do
      local hit = false
      for k = 1, #files do
        if glob_match(paths[j], files[k]) then
          hit = true
          break
        end
      end
      if not hit then
        arr.push(problems, "vendored " .. vendored[i].name .. ": " .. paths[j] .. " matches no tracked file")
      end
    end
  end
  if id then
    local report = walk(dir, id, holder, year, files, skip_globs(opts.exclude, vendored), false)
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
      files = files, texts = opts.texts,
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
  render = render,
  glob_match = glob_match,
  first_year = first_year,
  file_status = file_status,
}
