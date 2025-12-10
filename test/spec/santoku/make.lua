local test = require("santoku.test")
local arr = require("santoku.array")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local make = require("santoku.make")

test("make", function ()

  for fp, m in fs.walk("test/res", function (fp)
    return fp == "test/res/partials"
  end) do
    if m == "file" then
      fs.rm(fp)
    end
  end

  local submake = make()
  local target = submake.target
  local build = submake.build

  target(
    { "test/res/main.txt" },
    { "test/res/header.txt", "test/res/body.txt", "test/res/footer.txt" },
    function (ts, ds)
      for i = 1, #ts do fs.mkdirp(fs.dirname(ts[i])) end
      local parts = {}
      for i = 1, #ds do parts[i] = fs.readfile(ds[i]) end
      fs.writefile(ts[1], arr.concat(parts))
    end)

  target(
    { "test/res/header.txt" },
    { "test/res/partials/header-content.txt", },
    function (ts, ds)
      for i = 1, #ts do fs.mkdirp(fs.dirname(ts[i])) end
      fs.writefile(ts[1], "Header: " .. fs.readfile(ds[1]))
    end)

  target(
    { "test/res/body.txt", "test/res/footer.txt" }, {},
    function (ts)
      for i = 1, #ts do fs.mkdirp(fs.dirname(ts[i])) end
      fs.writefile(ts[1], "Body\n")
      fs.writefile(ts[2], "Footer\n")
    end)

  target(
    { "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" }, {},
    function (ts)
      for i = 1, #ts do fs.mkdirp(fs.dirname(ts[i])) end
      fs.writefile(ts[1], "a\n")
      fs.writefile(ts[2], "b\n")
      fs.writefile(ts[3], "c\n")
    end)

  target(
    { "test/res/test.txt" },
    { "test/res/partials/test-content.txt", "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" },
    function (ts, ds)
      for i = 1, #ts do fs.mkdirp(fs.dirname(ts[i])) end
      fs.writefile(ts[1], "Test: " .. fs.readfile(ds[1]))
    end)

  target({ "all-deps" }, { "test/res/main.txt", "test/res/test.txt" }, true)
  target({ "all" }, { "all-deps" }, true)

  build({ "all" }, 3)

  assert(eq("Header: Header content!\n", fs.readfile("test/res/header.txt")))
  assert(eq("Body\n", fs.readfile("test/res/body.txt")))
  assert(eq("Footer\n", fs.readfile("test/res/footer.txt")))
  assert(eq("Header: Header content!\nBody\nFooter\n", fs.readfile("test/res/main.txt")))

end)
