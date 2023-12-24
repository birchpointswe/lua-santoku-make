local err = require("santoku.err")
local test = require("santoku.test")
local fs = require("santoku.fs")
local gen = require("santoku.gen")
local make = require("santoku.make")

test("make", function ()

  err.check(err.pwrap(function (check)

    fs.walk("res", {
      recurse = true,
      prune = function (fp)
        return fp == "res/partials"
      end
    }):map(check):filter(function (_, m)
      return m == "file"
    end):each(function (fp)
      check(fs.rm(fp))
    end)

    local build = make()

    build:target({ "res/main.txt" }, { "res/header.txt", "res/body.txt", "res/footer.txt" }, function (ts, ds)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], gen.ivals(ds):map(fs.readfile):map(check):concat()))
      return true
    end)

    build:target({ "res/header.txt" }, { "res/partials/header-content.txt", }, function (ts, ds)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "Header: " .. check(fs.readfile(ds[1]))))
      return true
    end)

    build:target({ "res/body.txt", "res/footer.txt" }, {}, function (ts)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "Body\n"))
      check(fs.writefile(ts[2], "Footer\n"))
      return true
    end)

    build:target({ "res/a.txt", "res/b.txt", "res/c.txt" }, {}, function (ts)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "a\n"))
      check(fs.writefile(ts[2], "b\n"))
      check(fs.writefile(ts[3], "c\n"))
      return true
    end)

    build:target({ "res/test.txt" }, { "res/partials/test-content.txt", "res/a.txt", "res/b.txt", "res/c.txt" }, function (ts, ds)
      gen.ivals(ts):map(fs.dirname):map(fs.mkdirp):each(check)
      check(fs.writefile(ts[1], "Test: " .. check(fs.readfile(ds[1]))))
      return true
    end)

    build:target({ "all-deps" }, { "res/main.txt", "res/test.txt" }, true)

    build:target({ "all" }, { "all-deps" }, true)

    check(build:make({ "all" }, 2))
    assert("Header: Header content!\n" == check(fs.readfile("res/header.txt")))
    assert("Body\n" == check(fs.readfile("res/body.txt")))
    assert("Footer\n" == check(fs.readfile("res/footer.txt")))
    assert("Header: Header content!\nBody\nFooter\n" == check(fs.readfile("res/main.txt")))

  end))

end)
