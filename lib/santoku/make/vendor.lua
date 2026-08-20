local fs = require("santoku.fs")
local sys = require("santoku.system")
local str = require("santoku.string")
local err = require("santoku.error")
local tbl = require("santoku.table")
local arr = require("santoku.array")

local printf = str.printf

local function sha256 (fp)
  local first
  for line in sys.sh({ "sha256sum", "--", fp }) do
    first = first or line
  end
  return first and (str.match(first, "^(%x+)")) or nil
end

local function specs (config)
  return tbl.get(config, { "env", "vendor" }) or {}
end

local function urls (config, spec)
  local out = {}
  if spec.mirror then
    arr.push(out, spec.mirror)
  else
    local homepage = tbl.get(config, { "env", "homepage" })
    if homepage then
      arr.push(out, homepage .. "/releases/download/vendor/" .. fs.basename(spec.file))
    end
  end
  if spec.url then
    arr.push(out, spec.url)
  end
  return out
end

local function download (url, dest)
  local part = dest .. ".part"
  fs.mkdirp(fs.dirname(dest))
  if fs.exists(part) then
    fs.rm(part)
  end
  return (function (ok, ...)
    if not ok then
      if fs.exists(part) then
        fs.rm(part)
      end
      return false, ...
    end
    fs.mv(part, dest)
    return true
  end)(err.pcall(sys.execute, { "wget", "-q", "-O", part, "--", url }))
end

local function check (spec)
  if not fs.exists(spec.file) then
    return false, "missing"
  end
  if not spec.sha256 then
    return false, "no sha256 declared"
  end
  local got = sha256(spec.file)
  if got ~= spec.sha256 then
    return false, str.format("sha256 mismatch (declared %s, actual %s)", spec.sha256, tostring(got))
  end
  return true
end

local function validate (config)
  local ss = specs(config)
  for i = 1, #ss do
    local spec = ss[i]
    err.assert(spec.file, "vendor entry missing file")
    err.assert(spec.url or spec.mirror, "vendor entry missing url and mirror", spec.file)
  end
  return ss
end

local function ensure (config)
  local ss = validate(config)
  for i = 1, #ss do
    local spec = ss[i]
    local ok, reason = check(spec)
    if not ok then
      err.error("vendored source unusable, run 'toku vendor'", spec.file, reason)
    end
  end
  return ss
end

local function sync (config)
  local ss = validate(config)
  local undeclared = {}
  for i = 1, #ss do
    local spec = ss[i]
    if not fs.exists(spec.file) then
      local sources = urls(config, spec)
      local fetched = false
      for j = 1, #sources do
        printf("[vendor]\tfetching %s\n", sources[j])
        if download(sources[j], spec.file) then
          fetched = true
          break
        end
        printf("[vendor]\tfailed %s\n", sources[j])
      end
      if not fetched then
        err.error("unable to fetch vendored source", spec.file, arr.concat(sources, ", "))
      end
    end
    if not spec.sha256 then
      arr.push(undeclared, { file = spec.file, sha256 = sha256(spec.file) })
    else
      local ok, reason = check(spec)
      if not ok then
        err.error("vendored source failed verification", spec.file, reason)
      end
      printf("[vendor]\tok %s\n", spec.file)
    end
  end
  if #undeclared > 0 then
    printf("\nAdd the following sha256 values to the vendor table in make.lua:\n\n")
    for i = 1, #undeclared do
      printf("  { file = %q, sha256 = %q, ... }\n", undeclared[i].file, undeclared[i].sha256)
    end
    printf("\n")
    err.error("vendored sources have no declared sha256", #undeclared)
  end
  return ss
end

local function fetch_verified (dest, sources, expected)
  if fs.exists(dest) then
    if sha256(dest) == expected then
      return dest
    end
    printf("[vendor]\tdiscarding unverified %s\n", dest)
    fs.rm(dest)
  end
  for i = 1, #sources do
    printf("[vendor]\tfetching %s\n", sources[i])
    if download(sources[i], dest) then
      local got = sha256(dest)
      if got ~= expected then
        fs.rm(dest)
        err.error("vendored source failed verification", dest, expected, got)
      end
      return dest
    end
    printf("[vendor]\tfailed %s\n", sources[i])
  end
  return err.error("unable to fetch vendored source", dest, arr.concat(sources, ", "))
end

return {
  sha256 = sha256,
  specs = specs,
  urls = urls,
  check = check,
  ensure = ensure,
  sync = sync,
  fetch_verified = fetch_verified,
}
