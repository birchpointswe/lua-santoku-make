local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")
local err = require("santoku.error")
local common = require("santoku.make.common")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/local-deps")

sys.execute({ "rm", "-rf", root })

local function write_dep (dir, body)
  fs.mkdirp(fs.join(dir, "lib"))
  fs.writefile(fs.join(dir, "make.lua"), [[
return {
  type = "lib",
  env = {
    name = "dep-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
  }
}
]])
  fs.writefile(fs.join(dir, "lib", "depfixture.lua"), body)
end

local function write_consumer (dir, dep_path)
  fs.mkdirp(fs.join(dir, "lib"))
  fs.writefile(fs.join(dir, "make.lua"), str.interp([[
return {
  type = "lib",
  env = {
    name = "consumer-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
    local_deps = { "%1" },
  }
}
]], { dep_path }))
  fs.writefile(fs.join(dir, "lib", "consumerfixture.lua"), "return true\n")
end

test("local_deps missing path fails at init", function ()
  local dir = fs.join(root, "missing")
  write_consumer(dir, "submodules/nope")
  local ok, e = err.pcall(function ()
    return fs.pushd(dir, function ()
      return project.init({})
    end)
  end)
  assert(eq(ok, false))
  assert(str.find(tostring(e), "local_deps path not found"))
end)

test("local_deps path without make.lua fails at init", function ()
  local dir = fs.join(root, "uninitialized")
  write_consumer(dir, "submodules/dep-fixture")
  fs.mkdirp(fs.join(dir, "submodules", "dep-fixture"))
  local ok, e = err.pcall(function ()
    return fs.pushd(dir, function ()
      return project.init({})
    end)
  end)
  assert(eq(ok, false))
  assert(str.find(tostring(e), "local_deps path has no make.lua"))
end)

test("local_dep_srcs enumerates dep sources", function ()
  local dir = fs.join(root, "srcs")
  write_dep(fs.join(dir, "submodules", "dep-fixture"), "return { value = \"one\" }\n")
  local paths = common.local_dep_paths(dir, {
    env = { local_deps = { "submodules/dep-fixture" } }
  })
  assert(eq(#paths, 1))
  assert(str.startswith(paths[1], "/"))
  local srcs = common.local_dep_srcs(paths)
  local found_lib, found_make = false, false
  for i = 1, #srcs do
    if str.find(srcs[i], "lib/depfixture%.lua$") then found_lib = true end
    if str.find(srcs[i], "make%.lua$") then found_make = true end
  end
  assert(eq(found_lib, true))
  assert(eq(found_make, true))
end)

test("local_deps installed into test tree, restaled by source edits, cleaned by --deps", function ()
  local dir = fs.join(root, "e2e")
  write_consumer(dir, "submodules/dep-fixture")
  write_dep(fs.join(dir, "submodules", "dep-fixture"), "return { value = \"one\" }\n")
  local installed = fs.join(dir, "build", "default", "test",
    "lua_modules", "share", "lua", "5.1", "depfixture.lua")
  fs.pushd(dir, function ()
    project.init({}).exec({ "true" })
  end)
  assert(eq(true, fs.exists(installed)))
  assert(str.find(fs.readfile(installed), "one"))
  fs.writefile(fs.join(dir, "submodules", "dep-fixture", "lib", "depfixture.lua"),
    "return { value = \"two\" }\n")
  fs.pushd(dir, function ()
    project.init({}).exec({ "true" })
  end)
  assert(str.find(fs.readfile(installed), "two"))
  fs.pushd(dir, function ()
    local m = project.init({})
    local removed = m.clean({ deps = true })
    local found = false
    for i = 1, #removed do
      if str.find(removed[i], "local%-deps%.ok$") then found = true end
    end
    assert(eq(found, true))
    assert(eq(false, fs.exists(fs.join(dir, "build", "default", "test", "local-deps.ok"))))
    m.exec({ "true" })
  end)
  assert(eq(true, fs.exists(installed)))
  assert(str.find(fs.readfile(installed), "two"))
end)

test("local_deps installed into the install target tree", function ()
  local dir = fs.join(root, "install")
  write_consumer(dir, "submodules/dep-fixture")
  write_dep(fs.join(dir, "submodules", "dep-fixture"), "return { value = \"one\" }\n")
  local tree = fs.join(dir, "tree")
  local cfg = fs.join(dir, "scratch-luarocks.lua")
  fs.writefile(cfg, str.interp([[
rocks_trees = {
  { name = "scratch",
    root = "%1"
  } }
lua_version = "5.1"
rocks_provided = { lua = "5.1" }
]], { tree }))
  fs.pushd(dir, function ()
    project.init({ skip_tests = true, luarocks_config = cfg }).install()
  end)
  assert(eq(true, fs.exists(fs.join(tree, "share", "lua", "5.1", "depfixture.lua"))))
  assert(eq(true, fs.exists(fs.join(tree, "share", "lua", "5.1", "consumerfixture.lua"))))
end)

test("recursive local_deps refused", function ()
  local dir = fs.join(root, "recursive")
  write_consumer(dir, "submodules/dep-fixture")
  local dep = fs.join(dir, "submodules", "dep-fixture")
  fs.mkdirp(fs.join(dep, "lib"))
  fs.writefile(fs.join(dep, "lib", "depfixture.lua"), "return {}\n")
  fs.mkdirp(fs.join(dep, "submodules", "inner", "lib"))
  fs.writefile(fs.join(dep, "submodules", "inner", "lib", "inner.lua"), "return {}\n")
  fs.writefile(fs.join(dep, "submodules", "inner", "make.lua"), [[
return {
  type = "lib",
  env = {
    name = "inner-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
  }
}
]])
  fs.writefile(fs.join(dep, "make.lua"), [[
return {
  type = "lib",
  env = {
    name = "dep-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
    local_deps = { "submodules/inner" },
  }
}
]])
  local ok, e = err.pcall(function ()
    return fs.pushd(dir, function ()
      return project.init({}).exec({ "true" })
    end)
  end)
  assert(eq(ok, false))
  assert(str.find(tostring(e), "recursive local_deps not supported"))
end)
