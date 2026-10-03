-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2023 Birch Point SWE
local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local stale = require("santoku.make.stale")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/stale")

sys.execute({ "rm", "-rf", root })

local function write (dir, files)
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function rocks_dir (tree)
  return fs.join(tree, "lib", "luarocks", "rocks-5.1")
end

local function c (op, ...)
  return { op = op, version = { ... } }
end

local function dep (name, ...)
  return { name = name, constraints = { ... } }
end

local function write_manifest (tree, repository, dependencies)
  local repo = {}
  for name, versions in pairs(repository) do
    local vs = {}
    for i = 1, #versions do
      vs[#vs + 1] = "[\"" .. versions[i] .. "\"] = { { arch = \"installed\" } }"
    end
    repo[#repo + 1] = "[\"" .. name .. "\"] = { " .. arr.concat(vs, ", ") .. " }"
  end
  local function con (cs)
    local out = {}
    for i = 1, #cs do
      out[#out + 1] = "{ op = \"" .. cs[i].op .. "\", version = { " .. arr.concat(cs[i].version, ", ")
        .. ", string = \"x\" } }"
    end
    return "{ " .. arr.concat(out, ", ") .. " }"
  end
  local deps = {}
  for name, versions in pairs(dependencies or {}) do
    local vs = {}
    for ver, list in pairs(versions) do
      local ds = {}
      for i = 1, #list do
        ds[#ds + 1] = "{ name = \"" .. list[i].name .. "\", constraints = " .. con(list[i].constraints) .. " }"
      end
      vs[#vs + 1] = "[\"" .. ver .. "\"] = { " .. arr.concat(ds, ", ") .. " }"
    end
    deps[#deps + 1] = "[\"" .. name .. "\"] = { " .. arr.concat(vs, ", ") .. " }"
  end
  local dir = rocks_dir(tree)
  fs.mkdirp(dir)
  fs.writefile(fs.join(dir, "manifest"), "repository = { " .. arr.concat(repo, ", ") .. " }\n"
    .. "dependencies = { " .. arr.concat(deps, ", ") .. " }\n")
end

test("versions compare and match constraints the way luarocks does", function ()
  local v = stale.parse("2.0.0-1")
  assert(eq(true, stale.satisfies(v, { c(">=", 2, 0, 0), c("<", 3, 0, 0) })))
  assert(eq(false, stale.satisfies(stale.parse("3.0.0-1"), { c(">=", 2, 0, 0), c("<", 3, 0, 0) })))
  assert(eq(true, stale.satisfies(stale.parse("5.1"), { c("==", 5, 1) })))
  assert(eq(true, stale.satisfies(stale.parse("1.2.9-1"), { c("~>", 1, 2) })))
  assert(eq(false, stale.satisfies(stale.parse("1.3.0-1"), { c("~>", 1, 2) })))
  assert(eq(true, stale.satisfies(stale.parse("0.0.10-1"), { c(">", 0, 0, 9) })))
  assert(eq(false, stale.satisfies(stale.parse("2.0.0-1"), { c("~=", 2, 0, 0) })))
end)

test("a tree holding an older release than the home tree, still in range, is stale", function ()
  local tree = fs.join(root, "unit", "tree")
  local home = fs.join(root, "unit", "home")
  write_manifest(tree, {
    santoku = { "1.0.0-1", "2.0.0-1" },
    ["santoku-lpeg"] = { "1.0.0-1", "2.0.0-1" },
    ["santoku-template"] = { "2.0.4-1" },
  }, {
    ["santoku-lpeg"] = {
      ["1.0.0-1"] = { dep("santoku", c(">=", 1, 0, 0), c("<", 2, 0, 0)) },
      ["2.0.0-1"] = { dep("santoku", c(">=", 2, 0, 0), c("<", 3, 0, 0)) },
    },
    ["santoku-template"] = {
      ["2.0.4-1"] = {
        dep("santoku", c(">=", 2, 0, 0), c("<", 3, 0, 0)),
        dep("santoku-lpeg", c(">=", 2, 0, 0), c("<", 3, 0, 0)),
      },
    },
  })
  write_manifest(home, {
    santoku = { "2.5.0-1", "3.0.0-1" },
    ["santoku-lpeg"] = { "2.0.0-1" },
    ["santoku-template"] = { "2.0.9-1" },
  })
  local found = stale.rocks(rocks_dir(tree), rocks_dir(home), { ["santoku-template"] = true })
  assert(eq(1, #found))
  assert(eq("santoku", found[1].name))
  assert(eq("2.0.0-1", found[1].version))
  assert(eq("2.5.0-1", found[1].newer))
  write_manifest(home, { santoku = { "3.0.0-1" } })
  assert(eq(0, #stale.rocks(rocks_dir(tree), rocks_dir(home), {})))
end)

test("refresh clears a stale tree once, then only warns while luarocks can't resolve the newer release", function ()
  local dir = fs.join(root, "refresh")
  local tree = fs.join(dir, "lua_modules")
  local stamp = fs.join(dir, "stale-rocks.txt")
  local marker = fs.join(dir, "lua_modules.ok")
  local function plant ()
    write_manifest(tree, {
      santoku = { "0.0.0-1" },
      ["refresh-fixture"] = { "0.0.1-1" },
    }, {
      ["refresh-fixture"] = { ["0.0.1-1"] = { dep("santoku", c(">=", 0)) } },
    })
    fs.writefile(marker, "")
  end
  local function skip ()
    return { ["refresh-fixture"] = true }
  end
  plant()
  assert(eq(true, stale.refresh(tree, stamp, { marker }, skip)))
  assert(eq(false, fs.exists(tree)))
  assert(eq(false, fs.exists(marker)))
  assert(eq(true, fs.exists(stamp)))
  plant()
  assert(eq(false, stale.refresh(tree, stamp, { marker }, skip)))
  assert(eq(true, fs.exists(tree)))
  assert(eq(true, fs.exists(marker)))
end)

test("init clears a lib project's stale test tree and its markers", function ()
  local dir = fs.join(root, "lib-init")
  write(dir, {
    ["make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "stale-init-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1", "santoku >= 0.0.0" },
  }
}
]],
    ["lib/staleinit.lua"] = "return true\n",
  })
  local test_dir = fs.join(dir, "build", "default", "test")
  local tree = fs.join(test_dir, "lua_modules")
  write_manifest(tree, {
    santoku = { "0.0.0-1" },
    ["stale-init-fixture"] = { "0.0.1-1" },
  }, {
    ["stale-init-fixture"] = { ["0.0.1-1"] = { dep("santoku", c(">=", 0)) } },
  })
  fs.writefile(fs.join(test_dir, "lua_modules.ok"), "")
  fs.pushd(dir, function ()
    project.init({})
  end)
  assert(eq(false, fs.exists(tree)))
  assert(eq(false, fs.exists(fs.join(test_dir, "lua_modules.ok"))))
  assert(eq(true, fs.exists(fs.join(test_dir, "stale-rocks.txt"))))
end)

test("prune keeps declared entries and removes everything else", function ()
  local dir = fs.join(root, "prune")
  write(dir, {
    ["Makefile"] = "",
    ["patches/a.patch"] = "",
    ["results.mk"] = "",
    ["archive.tar.gz"] = "",
    ["src-old/x.o"] = "",
  })
  stale.prune(dir, { Makefile = true, patches = true })
  assert(eq(true, fs.exists(fs.join(dir, "Makefile"))))
  assert(eq(true, fs.exists(fs.join(dir, "patches", "a.patch"))))
  assert(eq(false, fs.exists(fs.join(dir, "results.mk"))))
  assert(eq(false, fs.exists(fs.join(dir, "archive.tar.gz"))))
  assert(eq(false, fs.exists(fs.join(dir, "src-old"))))
end)

test("a rewritten deps Makefile drops the old extraction and keeps tracked files", function ()
  local dir = fs.join(root, "deps")
  local function makefile (sub)
    return "results.mk: Makefile\n\tmkdir -p " .. sub .. "\n\ttouch " .. sub .. "/lib.o\n\ttouch results.mk\n"
  end
  write(dir, {
    ["make.lua"] = [[
return {
  type = "lib",
  env = {
    name = "stale-deps-fixture",
    version = "0.0.1-1",
    dependencies = { "lua == 5.1" },
  }
}
]],
    ["lib/staledeps.lua"] = "return true\n",
    ["deps/fx/Makefile"] = makefile("extract-a"),
    ["deps/fx/patches/keep.patch"] = "keep\n",
  })
  local deps_dir = fs.join(dir, "build", "default", "test", "deps", "fx")
  local function build ()
    fs.pushd(dir, function ()
      project.init({}).lua_env("test")
    end)
  end
  build()
  assert(eq(true, fs.exists(fs.join(deps_dir, "extract-a", "lib.o"))))
  sys.sleep(1.1)
  write(dir, { ["deps/fx/Makefile"] = makefile("extract-b") })
  build()
  assert(eq(false, fs.exists(fs.join(deps_dir, "extract-a"))))
  assert(eq(true, fs.exists(fs.join(deps_dir, "extract-b", "lib.o"))))
  assert(eq(true, fs.exists(fs.join(deps_dir, "patches", "keep.patch"))))
end)
