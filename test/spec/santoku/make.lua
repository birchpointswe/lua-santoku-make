local test = require("santoku.test")

local arr = require("santoku.array")
local concat = arr.concat

local iter = require("santoku.iter")
local ivals = iter.ivals
local collect = iter.collect
local map = iter.map
local each = iter.each
local filter = iter.filter

local validate = require("santoku.validate")
local eq = validate.isequal

local fs = require("santoku.fs")
local rm = fs.rm
local walk = fs.walk
local writefile = fs.writefile
local readfile = fs.readfile
local mkdirp = fs.mkdirp
local dirname = fs.dirname

local make = require("santoku.make")

test("make", function ()

  each(function (fp)
    return rm(fp)
  end, filter(function (_, m)
    return m == "file"
  end, walk("test/res", function (fp)
    return fp == "test/res/partials"
  end)))

  local submake = make()
  local target = submake.target
  local build = submake.build

  target(
    { "test/res/main.txt" },
    { "test/res/header.txt", "test/res/body.txt", "test/res/footer.txt" },
    function (ts, ds)
      each(mkdirp, map(dirname, ivals(ts)))
      writefile(ts[1], concat(collect(map(readfile, ivals(ds)))))
    end)

  target(
    { "test/res/header.txt" },
    { "test/res/partials/header-content.txt", },
    function (ts, ds)
      each(mkdirp, map(dirname, ivals(ts)))
      writefile(ts[1], "Header: " .. readfile(ds[1]))
    end)

  target(
    { "test/res/body.txt", "test/res/footer.txt" }, {},
    function (ts)
      each(mkdirp, map(dirname, ivals(ts)))
      writefile(ts[1], "Body\n")
      writefile(ts[2], "Footer\n")
    end)

  target(
    { "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" }, {},
    function (ts)
      each(mkdirp, map(dirname, ivals(ts)))
      writefile(ts[1], "a\n")
      writefile(ts[2], "b\n")
      writefile(ts[3], "c\n")
    end)

  target(
    { "test/res/test.txt" },
    { "test/res/partials/test-content.txt", "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" },
    function (ts, ds)
      each(mkdirp, map(dirname, ivals(ts)))
      writefile(ts[1], "Test: " .. readfile(ds[1]))
    end)

  target({ "all-deps" }, { "test/res/main.txt", "test/res/test.txt" }, true)
  target({ "all" }, { "all-deps" }, true)

  build({ "all" }, 3)

  assert(eq("Header: Header content!\n", readfile("test/res/header.txt")))
  assert(eq("Body\n", readfile("test/res/body.txt")))
  assert(eq("Footer\n", readfile("test/res/footer.txt")))
  assert(eq("Header: Header content!\nBody\nFooter\n", readfile("test/res/main.txt")))

end)
