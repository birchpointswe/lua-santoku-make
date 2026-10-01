local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local err = require("santoku.error")
local str = require("santoku.string")
local utc = require("santoku.utc")
local license = require("santoku.make.license")
local project = require("santoku.make.project")

local dir = fs.absolute("test/res/license")

local files = {
  ["a.lua"] = "local x = 1\nreturn x\n",
  ["bin/run.sh"] = "#!/bin/sh\necho hi\n",
  ["style.css"] = "a { color: red; }\n",
  ["vendored.c"] = "/* Copyright 1999 Someone */\nint x;\n",
  ["README.md"] = "# r\n",
  ["old.lua"] = "-- SPDX-License-Identifier: GPL-2.0-only\n-- SPDX-FileCopyrightText: 2020 Old\nreturn 1\n",
}

local function git (...)
  sys.execute({ "git", "-C", dir, "-c", "core.hooksPath=/nonexistent", "-c", "init.defaultBranch=master", ... })
end

local function fixture ()
  sys.execute({ "rm", "-rf", dir })
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
  git("init", "-q")
  git("add", "-A")
  git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--no-verify",
    "--date=2023-05-01T12:00:00", "-m", "x")
end

local function read (rel)
  return fs.readfile(fs.join(dir, rel))
end

local function joined (t)
  arr.sort(t)
  return arr.concat(t, ",")
end

local mit = { dir = dir, license = "MIT", copyright = "Birch Point SWE", year = "2023" }

test("first_year reads the earliest commit's year", function ()
  fixture()
  assert(eq("2023", license.first_year(dir)))
end)

test("a copyright with no license writes the all-rights-reserved line and no headers", function ()
  fixture()
  local report = license.apply({ dir = dir, copyright = "Birch Point SWE" })
  assert(eq("Copyright 2023 Birch Point SWE. All rights reserved.\n", read("LICENSE")))
  assert(eq(files["a.lua"], read("a.lua")))
  assert(eq(1, #report.warnings))
end)

test("no copyright writes nothing and warns twice", function ()
  fixture()
  local report = license.apply({ dir = dir })
  assert(eq(false, fs.exists(fs.join(dir, "LICENSE"))))
  assert(eq(2, #report.warnings))
end)

test("a license with no holder raises", function ()
  fixture()
  assert(eq(false, (err.pcall(license.apply, { dir = dir, license = "MIT" }))))
end)

test("headers insert, replace stale ones, and leave foreign and data files alone", function ()
  fixture()
  local report = license.headers(mit)
  assert(eq("a.lua,bin/run.sh,style.css", joined(report.missing)))
  assert(eq("old.lua", joined(report.stale)))
  assert(eq("vendored.c", joined(report.foreign)))
  assert(eq("README.md", joined(report.skipped)))
  assert(eq("-- SPDX-License-Identifier: MIT\n-- SPDX-FileCopyrightText: 2023 Birch Point SWE\n"
    .. files["a.lua"], read("a.lua")))
  assert(eq("#!/bin/sh\n# SPDX-License-Identifier: MIT\n# SPDX-FileCopyrightText: 2023 Birch Point SWE\n"
    .. "echo hi\n", read("bin/run.sh")))
  assert(eq("/* SPDX-License-Identifier: MIT\n   SPDX-FileCopyrightText: 2023 Birch Point SWE */\n"
    .. files["style.css"], read("style.css")))
  assert(eq("-- SPDX-License-Identifier: MIT\n-- SPDX-FileCopyrightText: 2023 Birch Point SWE\nreturn 1\n",
    read("old.lua")))
  assert(eq(files["vendored.c"], read("vendored.c")))
  assert(eq(files["README.md"], read("README.md")))
end)

test("a second headers run changes nothing", function ()
  fixture()
  license.headers(mit)
  local before = read("style.css") .. read("bin/run.sh") .. read("a.lua")
  local report = license.headers(mit)
  assert(eq("a.lua,bin/run.sh,old.lua,style.css", joined(report.ok)))
  assert(eq(before, read("style.css") .. read("bin/run.sh") .. read("a.lua")))
end)

test("a stale block header is replaced whole", function ()
  fixture()
  fs.writefile(fs.join(dir, "style.css"),
    "/* SPDX-License-Identifier: GPL-2.0-only\n   SPDX-FileCopyrightText: 2020 Old */\n" .. files["style.css"])
  license.headers(mit)
  assert(eq("/* SPDX-License-Identifier: MIT\n   SPDX-FileCopyrightText: 2023 Birch Point SWE */\n"
    .. files["style.css"], read("style.css")))
end)

test("exclude skips matching paths", function ()
  fixture()
  local report = license.headers({
    dir = dir, license = "MIT", copyright = "Birch Point SWE", year = "2023", exclude = { "^vendored%.c$" },
  })
  assert(eq("README.md,vendored.c", joined(report.skipped)))
  assert(eq("", joined(report.foreign)))
end)

test("check passes on a compliant tree and names each problem otherwise", function ()
  fixture()
  license.headers(mit)
  fs.writefile(fs.join(dir, "LICENSE"), "MIT License\n\nCopyright (c) 2023 Birch Point SWE\n")
  local opts = { dir = dir, license = "MIT", copyright = "Birch Point SWE", year = "2023", exclude = { "^vendored%.c$" } }
  local problems = license.check(opts)
  assert(eq(0, #problems), arr.concat(problems, "\n"))
  fs.writefile(fs.join(dir, "a.lua"), files["a.lua"])
  fs.writefile(fs.join(dir, "LICENSE"), "MIT License\n\nCopyright (c) <year> <copyright holders>\n")
  problems = license.check(opts)
  assert(eq("LICENSE still has unfilled placeholders\na.lua: missing header", arr.concat(problems, "\n")))
end)

test("check on an all-rights-reserved project wants the exact line", function ()
  fixture()
  local opts = { dir = dir, copyright = "Birch Point SWE" }
  assert(eq("LICENSE is missing", arr.concat(license.check(opts), "\n")))
  license.apply(opts)
  assert(eq(0, #license.check(opts)))
end)

test("a scaffold with no flags drops the boilerplate's license and headers", function ()
  local proj = fs.join(dir, "scaffold-none")
  sys.execute({ "rm", "-rf", proj })
  project.create_lib({ name = "lictest", dir = proj, git = false, quiet = true })
  assert(eq(false, fs.exists(fs.join(proj, "LICENSE"))))
  local mk = fs.readfile(fs.join(proj, "make.lua"))
  assert(eq(nil, str.find(mk, "license =", 1, true)))
  assert(eq(nil, str.find(mk, "copyright =", 1, true)))
  for fp in fs.files(proj, true) do
    assert(eq(nil, str.find(fs.readfile(fp), "SPDX-", 1, true)), fp)
  end
end)

test("a scaffold with only a copyright gets the all-rights-reserved line", function ()
  local proj = fs.join(dir, "scaffold-arr")
  sys.execute({ "rm", "-rf", proj })
  project.create_lib({ name = "lictest", dir = proj, git = false, quiet = true, copyright = "Acme" })
  local year = utc.format(utc.time(), "%Y")
  assert(eq("Copyright " .. year .. " Acme. All rights reserved.\n", fs.readfile(fs.join(proj, "LICENSE"))))
  local mk = fs.readfile(fs.join(proj, "make.lua"))
  assert(str.find(mk, "  copyright = \"Acme\",\n", 1, true), mk)
  assert(eq(nil, str.find(mk, "license =", 1, true)))
end)

sys.execute({ "rm", "-rf", dir })
