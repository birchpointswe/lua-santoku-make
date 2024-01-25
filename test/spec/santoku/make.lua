local check = require("santoku.check")
local test = require("santoku.test")
local fs = require("santoku.fs")
local gen = require("santoku.gen")
local make = require("santoku.make")

test("make", function ()

  check(check:wrap(function (check_init)

    fs.walk("test/res", {
      recurse = true,
      prune = function (fp)
        return fp == "test/res/partials"
      end
    }):map(check_init):filter(function (_, m)
      return m == "file"
    end):each(function (fp)
      check_init(fs.rm(fp))
    end)

    local build = make()

    build:target(
      { "test/res/main.txt" },
      { "test/res/header.txt", "test/res/body.txt", "test/res/footer.txt" },
      function (ts, ds, check_target)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check_target)
        check_target(fs.writefile(ts[1], gen.ivals(ds):map(fs.readfile):map(check_target):concat()))
        return true
      end)

    build:target(
      { "test/res/header.txt" },
      { "test/res/partials/header-content.txt", },
      function (ts, ds, check_target)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check_target)
        check_target(fs.writefile(ts[1], "Header: " .. check_target(fs.readfile(ds[1]))))
        return true
      end)

    build:target(
      { "test/res/body.txt", "test/res/footer.txt" }, {},
      function (ts, _, check_target)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check_target)
        check_target(fs.writefile(ts[1], "Body\n"))
        check_target(fs.writefile(ts[2], "Footer\n"))
        return true
      end)

    build:target(
      { "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" }, {},
      function (ts, _, check_target)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check_target)
        check_target(fs.writefile(ts[1], "a\n"))
        check_target(fs.writefile(ts[2], "b\n"))
        check_target(fs.writefile(ts[3], "c\n"))
        return true
      end)

    build:target(
      { "test/res/test.txt" },
      { "test/res/partials/test-content.txt", "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" },
      function (ts, ds, check_target)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check_target)
        check_target(fs.writefile(ts[1], "Test: " .. check_target(fs.readfile(ds[1]))))
        return true
      end)

    build:target({ "all-deps" }, { "test/res/main.txt", "test/res/test.txt" }, true)

    build:target({ "all" }, { "all-deps" }, true)

    check_init(build:make({ "all", verbosity = 3 }, check_init))
    assert("Header: Header content!\n" == check_init(fs.readfile("test/res/header.txt")))
    assert("Body\n" == check_init(fs.readfile("test/res/body.txt")))
    assert("Footer\n" == check_init(fs.readfile("test/res/footer.txt")))
    assert("Header: Header content!\nBody\nFooter\n" == check_init(fs.readfile("test/res/main.txt")))

  end))

end)
