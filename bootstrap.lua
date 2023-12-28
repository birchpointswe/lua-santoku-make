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

  local prj = check(require("santoku.make.project").init())
  check(prj[arg[1]](prj, { verbosity = 3 }))

end))
