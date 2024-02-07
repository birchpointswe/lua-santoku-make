package.path = "build/default/test/lua_modules/share/lua/5.1/?.lua"
package.cpath = "build/default/test/lua_modules/lib/lua/5.1/?.so"

local err = require("santoku.error")
local pcall = err.pcall

local fs = require("santoku.fs")
local mkdirp = fs.mkdirp
local join = fs.join
local dirname = fs.dirname
local writefile = fs.writefile
local files = fs.files

local template = require("santoku.template")
local renderfile = template.renderfile

print(xpcall(function ()

  mkdirp(".bootstrap")

  local env = setmetatable({}, { __index = _G })

  for fp in files("lib", true) do
    local outfile = join(".bootstrap", fp)
    local outdir = dirname(outfile)
    mkdirp(outdir)
    writefile(outfile, (renderfile(fp, env)))
  end

  package.path = ".bootstrap/lib/?.lua;" .. package.path

  if arg[1] == "test-wasm" then
    local prj = require("santoku.make.project").init({ wasm = true })
    prj.test({ verbosity = 3 })
  elseif arg[1] == "iterate-wasm" then
    local prj = require("santoku.make.project").init({ wasm = true })
    prj.iterate({ verbosity = 3 })
  else
    local prj = require("santoku.make.project").init()
    prj[arg[1]]({ verbosity = 3 })
  end

end, function (...)
  print(debug.traceback())
  return ...
end))
