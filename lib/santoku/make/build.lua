local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")

local M = {}

local function esbuild (input, ext)
  local tmp = fs.tmpname() .. ext
  fs.writefile(tmp, input)
  local parts = {}
  for chunk in sys.sh({ "esbuild", "--minify", tmp }) do
    parts[#parts + 1] = chunk
  end
  fs.rm(tmp)
  return arr.concat(parts, "\n")
end

M.minify_js = function (input)
  return esbuild(input, ".js")
end

M.minify_css = function (input)
  return esbuild(input, ".css")
end

return M
