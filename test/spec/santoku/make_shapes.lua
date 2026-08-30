local test = require("santoku.test")
local fs = require("santoku.fs")
local sys = require("santoku.system")
local str = require("santoku.string")
local project = require("santoku.make.project")

local root = "test/res/shapes"

local descriptor = [[
return {
  type = "web",
  env = {
    name = "shape",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = { domain = "localhost", port = "8080", workers = 1 },
  },
}
]]

local shapes = {
  {
    name = "client-lua",
    bundles = true,
    files = {
      ["client/bin/bundle.lua"] = "return 1\n",
      ["client/lib/shape/main.lua"] = "return 1\n",
    },
  },
  {
    name = "client-res-only",
    bundles = false,
    files = {
      ["client/res/index.tk.css"] = "a{}\n",
      ["client/static/index.html"] = "<!doctype html>\n",
    },
  },
  {
    name = "client-static-only",
    bundles = false,
    files = {
      ["client/static/index.html"] = "<!doctype html>\n",
      ["client/assets/app.js"] = "void 0;\n",
    },
  },
}

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

local function count_matching (sm, needle)
  local n = 0
  for t in pairs(sm.targets) do
    if str.find(t, needle, 1, true) then
      n = n + 1
    end
  end
  return n
end

local function with_shape (shape, fn)
  local dir = fs.join(root, shape.name)
  write_shape(dir, shape.files)
  fs.pushd(dir, function ()
    fn(project.init({
      dir = fs.absolute("build"),
      openresty_dir = "/nonexistent",
    }))
  end)
  sys.execute({ "rm", "-rf", dir })
end

for _, shape in ipairs(shapes) do

  test("static_files_ok has a producer: " .. shape.name, function ()
    with_shape(shape, function (p)
      local n = 0
      for t, fn in pairs(p.submake.fns) do
        if str.find(t, "static-files.ok", 1, true) and fn ~= nil then
          n = n + 1
        end
      end
      assert(n == 2, shape.name ..
        ": expected 2 static-files.ok producers (main and test), got " .. n)
    end)
  end)

  test("wasm bundling matches the shape: " .. shape.name, function ()
    with_shape(shape, function (p)
      local n = count_matching(p.submake, "bundler-post")
      if shape.bundles then
        assert(n > 0, shape.name .. ": expected bundle targets, got none")
      else
        assert(n == 0, shape.name ..
          ": expected no bundle targets, got " .. n)
      end
    end)
  end)

end
