local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local arr = require("santoku.array")
local fs = require("santoku.fs")
local make = require("santoku.make")

test("targets are built from their dependencies, dependencies first", function ()

  local dir = "test/res/readme"

  fs.mkdirp(dir)

  arr.ieach(function (fp)
    return fs.rm(fp)
  end, fs.files(dir))

  local ran = {}
  local m = make()

  m.target({ dir .. "/head.txt", dir .. "/body.txt" }, {}, function (ts)
    ran[#ran + 1] = "parts"
    fs.writefile(ts[1], "Header\n")
    fs.writefile(ts[2], "Body\n")
  end)

  m.target({ dir .. "/all.txt" }, { dir .. "/head.txt", dir .. "/body.txt" },
    function (ts, ds)
      ran[#ran + 1] = "all"
      local parts = {}
      for i = 1, #ds do parts[i] = fs.readfile(ds[i]) end
      fs.writefile(ts[1], arr.concat(parts))
    end)

  m.target({ "everything" }, { dir .. "/all.txt" }, true)

  m.build({ "everything" }, 0)

  assert(eq("Header\nBody\n", fs.readfile(dir .. "/all.txt")))
  assert(eq(2, #ran))
  assert(eq("parts", ran[1]))
  assert(eq("all", ran[2]))

end)
