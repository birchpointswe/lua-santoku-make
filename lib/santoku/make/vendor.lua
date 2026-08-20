local fs = require("santoku.fs")
local sys = require("santoku.system")
local str = require("santoku.string")
local err = require("santoku.error")

local printf = str.printf

local function sha256 (fp)
  local first
  for line in sys.sh({ "sha256sum", "--", fp }) do
    first = first or line
  end
  return first and (str.match(first, "^(%x+)")) or nil
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

return {
  sha256 = sha256,
  fetch = fetch,
}
