local fs = require("santoku.fs")
local sys = require("santoku.system")
local str = require("santoku.string")
local err = require("santoku.error")
local tbl = require("santoku.table")

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

local function check (spec, path)
  path = path or spec.file
  if not fs.exists(path) then
    return false, "missing"
  end
  if not spec.sha256 then
    return false, "no sha256 declared"
  end
  local got = sha256(path)
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
    err.assert(spec.url, "vendor entry missing url", spec.file)
  end
  return ss
end

local function fetch (spec, dest)
  if fs.exists(dest) then
    if spec.sha256 and sha256(dest) == spec.sha256 then
      return dest
    end
    printf("[vendor]\tdiscarding unverified %s\n", dest)
    fs.rm(dest)
  end
  printf("[vendor]\tfetching %s\n", spec.url)
  if not download(spec.url, dest) then
    return err.error("unable to fetch vendored source", dest, spec.url)
  end
  local got = sha256(dest)
  if not spec.sha256 then
    fs.rm(dest)
    printf("\nAdd to the vendor entry in make.lua:\n\n  sha256 = %q\n\n", got)
    return err.error("vendored source has no declared sha256", dest)
  end
  if got ~= spec.sha256 then
    fs.rm(dest)
    return err.error("vendored source failed verification", dest, spec.sha256, got)
  end
  printf("[vendor]\tok %s\n", dest)
  return dest
end

local function fetch_verified (dest, url, expected)
  if fs.exists(dest) then
    if sha256(dest) == expected then
      return dest
    end
    printf("[vendor]\tdiscarding unverified %s\n", dest)
    fs.rm(dest)
  end
  printf("[vendor]\tfetching %s\n", url)
  if not download(url, dest) then
    return err.error("unable to fetch vendored source", dest, url)
  end
  local got = sha256(dest)
  if got ~= expected then
    fs.rm(dest)
    return err.error("vendored source failed verification", dest, expected, got)
  end
  return dest
end

return {
  sha256 = sha256,
  specs = specs,
  check = check,
  validate = validate,
  fetch = fetch,
  fetch_verified = fetch_verified,
}
