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

local function mirror (config, spec)
  if spec.mirror then
    return spec.mirror
  end
  local homepage = tbl.get(config, { "env", "homepage" })
  if not homepage then
    return nil
  end
  return homepage .. "/releases/download/vendor/" .. fs.basename(spec.file)
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
    err.assert(mirror(config, spec),
      "vendor entry has no mirror and no homepage to derive one from", spec.file)
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
      local url = mirror(config, spec)
      printf("[vendor]\tfetching %s\n", url)
      if not download(url, spec.file) then
        printf("\nThe vendor mirror does not have this artifact. Seed it once:\n\n")
        printf("  download %s\n", spec.url or "the upstream archive")
        printf("  verify its sha256 against the vendor table\n")
        printf("  gh release upload vendor <file> -R <the repo owning this mirror>\n\n")
        err.error("vendored source not on the mirror", spec.file, url)
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
  mirror = mirror,
  check = check,
  ensure = ensure,
  sync = sync,
  fetch_verified = fetch_verified,
}
