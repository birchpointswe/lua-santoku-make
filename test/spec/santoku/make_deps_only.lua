-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2023 Birch Point SWE
local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local err = require("santoku.error")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/deps-only")

sys.execute({ "rm", "-rf", root })

local function write (dir, files)
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function pack_rock (server, name)
  local src = fs.join(root, "rock-src", name)
  local tree = fs.join(root, "rock-tree")
  write(src, {
    [name .. "-0.0.1-1.rockspec"] = "package = \"" .. name .. "\"\nversion = \"0.0.1-1\"\n"
      .. "source = { url = \".\" }\n"
      .. "build = { type = \"builtin\", modules = { " .. name .. " = \"" .. name .. ".lua\" } }\n",
    [name .. ".lua"] = "return \"" .. name .. "\"\n",
  })
  fs.pushd(src, function ()
    sys.execute({ "luarocks", "make", "--tree", tree, name .. "-0.0.1-1.rockspec" })
  end)
  fs.mkdirp(server)
  fs.pushd(server, function ()
    sys.execute({ "luarocks", "pack", "--tree", tree, name, "0.0.1-1" })
  end)
end

local function scratch_config (dir, server, tree)
  local cfg = fs.join(dir, "scratch-luarocks.lua")
  fs.writefile(cfg, str.interp([[
rocks_trees = {
  { name = "scratch",
    root = "%1"
  } }
rocks_servers = { "%2" }
lua_version = "5.1"
rocks_provided = { lua = "5.1" }
]], { tree, server }))
  return cfg
end

test("deps_only installs the declared deps of a lib and its local deps, reading no sources", function ()
  local dir = fs.join(root, "lib")
  local server = fs.join(root, "server")
  local tree = fs.join(dir, "tree")
  pack_rock(server, "fxdepa")
  pack_rock(server, "fxdepb")
  sys.execute({ "luarocks-admin", "make-manifest", server })
  write(dir, {
    ["make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "deps-only-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1", "fxdepa == 0.0.1-1" },
    local_deps = { "submodules/inner" },
  }
}
]],
    ["lib/depsonly/broken.c"] = "this is not C\n",
    ["submodules/inner/make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "inner-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1", "fxdepb == 0.0.1-1" },
  }
}
]],
    ["submodules/inner/lib/innerfixture.lua"] = "return true\n",
  })
  local cfg = scratch_config(dir, server, tree)
  local share = fs.join(tree, "share", "lua", "5.1")
  fs.pushd(dir, function ()
    project.init({ skip_tests = true, luarocks_config = cfg }).deps_only()
  end)
  assert(eq(true, fs.exists(fs.join(share, "fxdepa.lua"))))
  assert(eq(true, fs.exists(fs.join(share, "fxdepb.lua"))))
  assert(eq(false, fs.exists(fs.join(share, "innerfixture.lua"))))
  sys.execute({ "rm", "-rf", server })
  sys.execute({ "rm", "-f", fs.join(dir, "lib", "depsonly", "broken.c") })
  write(dir, { ["lib/depsonly.lua"] = "return \"consumer\"\n" })
  fs.pushd(dir, function ()
    project.init({ skip_tests = true, luarocks_config = cfg }).install()
  end)
  assert(eq(true, fs.exists(fs.join(share, "depsonly.lua"))))
  assert(eq(true, fs.exists(fs.join(share, "innerfixture.lua"))))
end)

test("deps_only on a web project needs no server or client sources", function ()
  local dir = fs.join(root, "web")
  write(dir, {
    ["make.lua"] = [[
return {
  type = "web",
  env = {
    name = "deps-only-web",
    version = "0.0.1-1",
    local_deps = { { path = "submodules/inner", targets = { "server" } } },
    server = { dependencies = { "lua == 5.1" } },
    nginx = { domain = "localhost", port = "8080", workers = 1 },
  },
}
]],
    ["submodules/inner/make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "inner-web-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
  }
}
]],
    ["submodules/inner/lib/innerwebfixture.lua"] = "return true\n",
  })
  local ok, e = err.pcall(function ()
    return fs.pushd(dir, function ()
      project.init({ dir = fs.absolute("build"), openresty_dir = "/nonexistent" }).deps_only()
    end)
  end)
  assert(eq(true, ok), tostring(e))
  local found = false
  for fp in fs.files(fs.join(dir, "build"), true) do
    if str.find(fp, "innerwebfixture", 1, true) or str.find(fp, "deps%-only%-web%-server%-0") then
      found = found or str.find(fp, "lua_modules", 1, true) ~= nil
    end
  end
  assert(eq(false, found))
end)
