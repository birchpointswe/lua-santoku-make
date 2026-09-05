local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local err = require("santoku.error")
local site = require("santoku.make.site")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/site")

local function write_public (dir, files)
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

test("pages maps manifest html entries to urls", function ()
  local page_set = site.pages({
    ["index.html"] = "index.abcdefabcdef.html",
    ["docs/index.html"] = "docs/index.abcdefabcdef.html",
    ["about.html"] = "about.abcdefabcdef.html",
    ["app.js"] = "app.abcdefabcdef.js",
  })
  assert(eq(page_set["/"], "index.abcdefabcdef.html"))
  assert(eq(page_set["/docs"], "docs/index.abcdefabcdef.html"))
  assert(eq(page_set["/about.html"], "about.abcdefabcdef.html"))
  assert(eq(page_set["/app.js"], nil))
end)

test("check_links passes a consistent site and fails a planted dead link", function ()
  local dir = fs.join(root, "unit")
  local manifest = {
    ["index.html"] = "index.abcdefabcdef.html",
    ["docs/index.html"] = "docs/index.abcdefabcdef.html",
    ["app.js"] = "app.abcdefabcdef.js",
  }
  write_public(dir, {
    ["index.abcdefabcdef.html"] =
      "<a href=\"/docs\">docs</a><a href=\"/docs#intro\">intro</a>" ..
      "<script src=\"/app.abcdefabcdef.js\"></script>" ..
      "<a href=\"/robots.txt\">robots</a>" ..
      "<code><a href=\"/not-checked\">in code</a></code>",
    ["docs/index.abcdefabcdef.html"] =
      "<div id=\"intro\"></div><a href=\"/\">home</a>",
  })
  site.check_links({
    public_dir = dir,
    manifest = manifest,
    stable = { "robots.txt" },
  })
  write_public(dir, {
    ["index.abcdefabcdef.html"] = "<a href=\"/missing\">dead</a>",
    ["docs/index.abcdefabcdef.html"] = "<a href=\"/\">home</a>",
  })
  local ok, e = err.pcall(site.check_links, {
    public_dir = dir,
    manifest = manifest,
    stable = { "robots.txt" },
  })
  assert(eq(ok, false))
  assert(str.find(tostring(e), "link check failed"))
  assert(str.find(tostring(e), "/missing", 1, true))
  sys.execute({ "rm", "-rf", dir })
end)

test("check_links fails a missing fragment and honors allow patterns", function ()
  local dir = fs.join(root, "frag")
  local manifest = {
    ["index.html"] = "index.abcdefabcdef.html",
    ["docs/index.html"] = "docs/index.abcdefabcdef.html",
  }
  write_public(dir, {
    ["index.abcdefabcdef.html"] = "<a href=\"/docs#nope\">gone</a>",
    ["docs/index.abcdefabcdef.html"] = "<div id=\"intro\"></div>",
  })
  local ok, e = err.pcall(site.check_links, {
    public_dir = dir,
    manifest = manifest,
  })
  assert(eq(ok, false))
  assert(str.find(tostring(e), "no element with that id"))
  write_public(dir, {
    ["index.abcdefabcdef.html"] = "<img src=\"/generated-thing.png\">",
    ["docs/index.abcdefabcdef.html"] = "<div id=\"intro\"></div>",
  })
  local ok2 = err.pcall(site.check_links, {
    public_dir = dir,
    manifest = manifest,
  })
  assert(eq(ok2, false))
  site.check_links({
    public_dir = dir,
    manifest = manifest,
    allow = { "^/generated%-[%w%-]+%.png$" },
  })
  sys.execute({ "rm", "-rf", dir })
end)

test("sitemap emits sorted page urls under the site root", function ()
  local xml = site.sitemap("https://example.com", {
    ["index.html"] = "index.abcdefabcdef.html",
    ["docs/index.html"] = "docs/index.abcdefabcdef.html",
    ["app.js"] = "app.abcdefabcdef.js",
  })
  assert(str.find(xml, "<loc>https://example.com/</loc>", 1, true))
  assert(str.find(xml, "<loc>https://example.com/docs</loc>", 1, true))
  assert(not str.find(xml, "app%.js"))
  assert(str.find(xml, "^<%?xml"))
end)

local descriptor = [[
return {
  type = "web",
  env = {
    name = "siteshape",
    version = "0.0.1-1",
    client = {
      stable = { "robots.txt" },
      check_links = true,
      sitemap = "https://example.com",
    },
    server = {},
    nginx = { domain = "localhost", port = "8080", workers = 1 },
  },
}
]]

local function write_shape (dir, files)
  sys.execute({ "rm", "-rf", dir })
  fs.mkdirp(dir)
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
  fs.writefile(fs.join(dir, "make.lua"), descriptor)
end

local function build_checks (dir)
  return fs.pushd(dir, function ()
    local p = project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    })
    p.submake.build({ fs.join(fs.absolute("build"), "default", "main", "dist", "checks.ok") }, 0)
  end)
end

test("client.stable emits a stable-named copy and sitemap lands post-hash", function ()
  local dir = fs.join(root, "shape-ok")
  write_shape(dir, {
    ["client/static/index.html"] = "<!doctype html><a href=\"/docs\">docs</a>" ..
      "<a href=\"/robots.txt\">robots</a>",
    ["client/static/docs/index.html"] = "<!doctype html><a href=\"/\">home</a>",
    ["client/static/robots.txt"] = "User-agent: *\n",
  })
  build_checks(dir)
  local public = fs.join(dir, "build", "default", "main", "dist", "public")
  assert(eq(true, fs.exists(fs.join(public, "robots.txt"))))
  assert(eq("User-agent: *\n", fs.readfile(fs.join(public, "robots.txt"))))
  local manifest = dofile(fs.join(dir, "build", "default", "main", "dist", "hash-manifest.lua"))
  assert(eq(true, fs.exists(fs.join(public, manifest["robots.txt"]))))
  local xml = fs.readfile(fs.join(public, "sitemap.xml"))
  assert(str.find(xml, "<loc>https://example.com/docs</loc>", 1, true))
  sys.execute({ "rm", "-rf", dir })
end)

test("check_links fails the build on a planted dead link", function ()
  local dir = fs.join(root, "shape-dead")
  write_shape(dir, {
    ["client/static/index.html"] = "<!doctype html><a href=\"/nowhere\">dead</a>",
    ["client/static/robots.txt"] = "User-agent: *\n",
  })
  local ok, e = err.pcall(build_checks, dir)
  assert(eq(ok, false))
  assert(str.find(tostring(e), "link check failed"))
  sys.execute({ "rm", "-rf", dir })
end)

test("snapshot returns the real scaffold tree in memory", function ()
  local snap = project.snapshot("api", { name = "my-api" })
  assert(eq(snap.name, "my-api"))
  assert(eq(snap.mod, "my_api"))
  assert(#snap.all > 0)
  assert(eq(#snap.all, #snap.files))
  local by_path = {}
  for i = 1, #snap.files do
    by_path[snap.files[i].path] = snap.files[i].code
  end
  assert(by_path["make.lua"])
  assert(str.find(by_path["make.lua"], "my%-api"))
  assert(by_path["server/nginx.tk.conf"])
  local seen_make = false
  for i = 1, #snap.all do
    if snap.all[i] == "make.lua" then
      seen_make = true
    end
  end
  assert(eq(seen_make, true))
end)

test("snapshot rejects unknown kinds", function ()
  local ok = pcall(project.snapshot, "nope")
  assert(eq(ok, false))
end)

sys.execute({ "rm", "-rf", root })
