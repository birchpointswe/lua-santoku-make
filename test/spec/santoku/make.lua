local err = require("santoku.err")
local test = require("santoku.test")
local fs = require("santoku.fs")
local gen = require("santoku.gen")
local make = require("santoku.make")

test("make", function ()

  err.check(err.pwrap(function (check)

    fs.walk("test/res", {
      recurse = true,
      prune = function (fp)
        return fp == "test/res/partials"
      end
    }):map(check):filter(function (_, m)
      return m == "file"
    end):each(function (fp)
      check(fs.rm(fp))
    end)

    local build = make()

    build:target({ "test/res/main.txt" }, { "test/res/header.txt", "test/res/body.txt", "test/res/footer.txt" }, function (ts, ds)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], gen.ivals(ds):map(fs.readfile):map(check):concat()))
      return true
    end)

    build:target({ "test/res/header.txt" }, { "test/res/partials/header-content.txt", }, function (ts, ds)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "Header: " .. check(fs.readfile(ds[1]))))
      return true
    end)

    build:target({ "test/res/body.txt", "test/res/footer.txt" }, {}, function (ts)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "Body\n"))
      check(fs.writefile(ts[2], "Footer\n"))
      return true
    end)

    build:target({ "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" }, {}, function (ts)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "a\n"))
      check(fs.writefile(ts[2], "b\n"))
      check(fs.writefile(ts[3], "c\n"))
      return true
    end)

    build:target(
      { "test/res/test.txt" },
      { "test/res/partials/test-content.txt", "test/res/a.txt", "test/res/b.txt", "test/res/c.txt" },
      function (ts, ds)
        gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
        check(fs.writefile(ts[1], "Test: " .. check(fs.readfile(ds[1]))))
        return true
      end)

    build:target({ "all-deps" }, { "test/res/main.txt", "test/res/test.txt" }, true)

    build:target({ "all" }, { "all-deps" }, true)

    check(build:make({ "all" }, 2))
    assert("Header: Header content!\n" == check(fs.readfile("test/res/header.txt")))
    assert("Body\n" == check(fs.readfile("test/res/body.txt")))
    assert("Footer\n" == check(fs.readfile("test/res/footer.txt")))
    assert("Header: Header content!\nBody\nFooter\n" == check(fs.readfile("test/res/main.txt")))

  end))

end)
