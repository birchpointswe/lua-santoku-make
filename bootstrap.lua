local err = require("santoku.err")
local fs = require("santoku.fs")
local gen = require("santoku.gen")
local tpl = require("santoku.template")

err.check(err.pwrap(function (check)

  check(fs.mkdirp(".bootstrap"))

  local tplcfg = { env = setmetatable({}, { __index = _G }) }

  fs.files("lib", { recurse = true }):map(check):each(function (fp)
    local outfile = fs.join(".bootstrap", fp)
    local outdir = fs.dirname(outfile)
    check(fs.mkdirp(outdir))
    check(fs.writefile(outfile, check(tpl.renderfile(fp, tplcfg))))
  end)

  package.path = ".bootstrap/lib/?.lua;" .. package.path


  if arg[1] == "test-wasm" then
    local prj = check(require("santoku.make.project").init({ wasm = true }))
    check(prj["test"](prj, { verbosity = 3 }))
  elseif arg[1] == "iterate-wasm" then
    local prj = check(require("santoku.make.project").init({ wasm = true }))
    check(prj["iterate"](prj, { verbosity = 3 }))
  else
    local prj = check(require("santoku.make.project").init())
    check(prj[arg[1]](prj, { verbosity = 3 }))
  end

end))
