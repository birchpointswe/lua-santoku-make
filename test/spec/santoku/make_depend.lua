local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local posix = require("santoku.make.posix")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/depend")

local descriptor = [[
return {
  type = "web",
  env = {
    name = "dependfixture",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = {
      domain = "localhost",
      port = "8080",
    },
  },
}
]]

local watched = arr.concat({
  "<% depend(\"data\", function (fp) return require(\"santoku.fs\").basename(fp) == \"skip\" end) %>",
  "<% local fs = require(\"santoku.fs\") ",
  "local n = 0 ",
  "for _ in fs.files(\"data\") do n = n + 1 end ",
  "return fs.readfile(\"data/v.txt\") .. \":\" .. n %>\n",
})

local function write_project (dir)
  sys.execute({ "rm", "-rf", dir })
  local files = {
    ["make.lua"] = descriptor,
    ["client/static/watched.tk.html"] = watched,
    ["client/static/sibling.tk.html"] = "<% return \"sibling\" %>\n",
    ["data/v.txt"] = "one",
    ["data/skip/keep.txt"] = "pruned",
  }
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function out (dir, name)
  return fs.join(dir, "build", "default", "main", "dist", "public-staging", name)
end

local function build (dir)
  return fs.pushd(dir, function ()
    local p = project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    })
    p.submake.build({
      fs.absolute(out(".", "watched.html")),
      fs.absolute(out(".", "sibling.html")),
    }, 0)
  end)
end

local function marks (dir)
  return posix.time(out(dir, "watched.html")) .. ":" .. posix.time(out(dir, "sibling.html"))
end

local function settle (dir)
  for _ = 1, 5 do
    local before = marks(dir)
    sys.sleep(1.1)
    build(dir)
    if marks(dir) == before then
      return true
    end
  end
end

test("depend restales a template on an edit or an addition, and honours prune", function ()

  local dir = fs.join(root, "tree")
  write_project(dir)
  build(dir)
  assert(eq("one:1", fs.readfile(out(dir, "watched.html"))))
  assert(settle(dir), "identical builds must reach a fixed point")
  local sibling_at = posix.time(out(dir, "sibling.html"))

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "data/v.txt"), "two")
  build(dir)
  assert(eq("two:1", fs.readfile(out(dir, "watched.html"))),
    "editing a file under a depended directory must re-render the template")

  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "data/new.txt"), "added")
  build(dir)
  assert(eq("two:2", fs.readfile(out(dir, "watched.html"))),
    "adding a file under a depended directory must re-render the template")

  assert(settle(dir), "identical builds must reach a fixed point after an addition")
  local watched_at = posix.time(out(dir, "watched.html"))
  sys.sleep(1.1)
  fs.writefile(fs.join(dir, "data/skip/keep.txt"), "changed")
  build(dir)
  assert(eq(watched_at, posix.time(out(dir, "watched.html"))),
    "a change under a pruned directory must not re-render the template")

  assert(eq(sibling_at, posix.time(out(dir, "sibling.html"))),
    "a template that depends on nothing here must never re-render")

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
