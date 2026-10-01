local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local arr = require("santoku.array")
local sys = require("santoku.system")
local err = require("santoku.error")
local str = require("santoku.string")
local utc = require("santoku.utc")
local env = require("santoku.env")
local license = require("santoku.make.license")
local project = require("santoku.make.project")

local dir = fs.absolute("test/res/license")

local files = {
  ["a.lua"] = "local x = 1\nreturn x\n",
  ["bin/run.sh"] = "#!/bin/sh\necho hi\n",
  ["style.css"] = "a { color: red; }\n",
  ["vendored.c"] = "/* Copyright 1999 Someone */\nint x;\n",
  ["README.md"] = "# r\n",
  ["make.lua"] = "local env = {\n  name = \"x\",\n  version = \"0.0.1-1\",\n  license = \"MIT\",\n"
    .. "  copyright = \"Birch Point SWE\",\n}\nreturn { env = env }\n",
  ["vendor.lua"] = "-- Copyright 2001 Someone\nreturn 1\n",
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
  assert(eq("a.lua,bin/run.sh,make.lua,style.css", joined(report.missing)))
  assert(eq("old.lua", joined(report.stale)))
  assert(eq("vendor.lua,vendored.c", joined(report.foreign)))
  assert(eq("-- SPDX-License-Identifier: MIT\n-- SPDX-FileCopyrightText: 2023 Birch Point SWE\n"
    .. files["make.lua"], read("make.lua")))
  assert(eq(files["vendor.lua"], read("vendor.lua")))
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
  assert(eq("a.lua,bin/run.sh,make.lua,old.lua,style.css", joined(report.ok)))
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
    dir = dir, license = "MIT", copyright = "Birch Point SWE", year = "2023",
    exclude = { "vendored.c", "vendor.lua" },
  })
  assert(eq("README.md,vendor.lua,vendored.c", joined(report.skipped)))
  assert(eq("", joined(report.foreign)))
end)

test("check passes on a compliant tree and names each problem otherwise", function ()
  fixture()
  license.headers(mit)
  fs.writefile(fs.join(dir, "LICENSE"), "MIT License\n\nCopyright (c) 2023 Birch Point SWE\n")
  local opts = {
    dir = dir, license = "MIT", copyright = "Birch Point SWE", year = "2023",
    exclude = { "vendored.c", "vendor.lua" },
  }
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

local dashes = str.rep("-", 80)

local third_party = dashes .. "\n\n"
  .. "This package vendors LPeg 1.1.0 (vendor.lua), which is:\n\n  Copyright (C) 2007-2023 Lua.org, PUC-Rio.\n\n"
  .. "  Permission is hereby granted.\n"

local texts = {
  MIT = { "MIT License", "", "Copyright (c) <year> <copyright holders>", "", "Permission is hereby granted." },
  blessing = { "The author disclaims copyright to this source code." },
}

local lpeg = {
  name = "LPeg", version = "1.1.0", path = { "vendor.lua" },
  copyright = "(C) 2007-2023 Lua.org, PUC-Rio.", license = "MIT", note = "Modified for santoku.",
}

local function vopts (vendored)
  return {
    dir = dir, license = "MIT", copyright = "Birch Point SWE", texts = texts,
    exclude = { "vendored.c" }, vendored = vendored,
  }
end

test("glob paths follow REUSE: * stays in a directory, ** crosses them", function ()
  assert(license.glob_match("lib/re/lp*", "lib/re/lpcap.h"))
  assert(not license.glob_match("lib/re/lp*", "lib/re/sub/lpcap.h"))
  assert(license.glob_match("lib/**", "lib/re/sub/lpcap.h"))
  assert(license.glob_match("lib/**/x.h", "lib/x.h"))
  assert(license.glob_match("lib/**/x.h", "lib/a/b/x.h"))
  assert(not license.glob_match("lib/**/x.h", "lib/ax.h"))
  assert(license.glob_match("a\\*b", "a*b"))
  assert(not license.glob_match("a\\*b", "axb"))
end)

test("apply writes one section per vendored component and skips its paths", function ()
  fixture()
  fs.writefile(fs.join(dir, "LICENSE"), "Copyright 2025 Birch Point SWE\n\nOld terms.\n\n" .. third_party)
  local report = license.apply(vopts({ lpeg }))
  local want = "MIT License\n\nCopyright (c) 2023 Birch Point SWE\n\nPermission is hereby granted.\n\n"
    .. dashes .. "\n\nThis package vendors LPeg 1.1.0 (vendor.lua), which is:\n\n"
    .. "  MIT License\n\n  Copyright (C) 2007-2023 Lua.org, PUC-Rio.\n\n  Permission is hereby granted.\n\n"
    .. "Modified for santoku.\n"
  assert(eq(want, read("LICENSE")))
  assert(eq(files["vendor.lua"], read("vendor.lua")))
  assert(eq("", joined(report.foreign)))
  license.apply(vopts({ lpeg }))
  assert(eq(want, read("LICENSE")))
  local problems = license.check(vopts({ lpeg }))
  assert(eq(0, #problems), arr.concat(problems, "\n"))
end)

test("apply refuses, and check reports, a LICENSE section make.lua doesn't declare", function ()
  fixture()
  local before = "Copyright 2025 Birch Point SWE\n\nOld terms.\n\n" .. third_party
  fs.writefile(fs.join(dir, "LICENSE"), before)
  assert(eq(false, (err.pcall(license.apply, vopts({})))))
  assert(eq(before, read("LICENSE")))
  local problems = arr.concat(license.check(vopts({})), "\n")
  assert(str.find(problems, "LICENSE has a section make.lua doesn't declare: LPeg 1.1.0", 1, true), problems)
  assert(str.find(problems, "vendor.lua: foreign header", 1, true), problems)
end)

test("a build-time component gets a links section from its source URL", function ()
  fixture()
  local sqlite = {
    name = "SQLite", version = "3.49.2", source = "https://sqlite.org/2025/sqlite-amalgamation-3490200.zip",
    license = "blessing",
  }
  license.apply(vopts({ lpeg, sqlite }))
  local text = read("LICENSE")
  assert(str.find(text, "\n\n" .. dashes .. "\n\nThis package links SQLite 3.49.2, fetched from", 1, true), text)
  assert(str.find(text, "sqlite-amalgamation-3490200.zip at build time, which is:\n\n"
    .. "  The author disclaims copyright to this source code.\n", 1, true), text)
  for line in str.gmatch(text, "[^\n]+") do
    assert(#line <= 80, line)
  end
  assert(eq(0, #license.check(vopts({ lpeg, sqlite }))))
  local problems = arr.concat(license.check(vopts({ lpeg })), "\n")
  assert(str.find(problems, "LICENSE has a section make.lua doesn't declare: SQLite", 1, true), problems)
end)

test("check reports a declared path that matches nothing and a missing section", function ()
  fixture()
  license.apply(vopts({ lpeg }))
  local ghost = { name = "Ghost", version = "1", path = { "nowhere/*" }, copyright = "2020 X", license = "MIT" }
  local problems = arr.concat(license.check(vopts({ lpeg, ghost })), "\n")
  assert(str.find(problems, "vendored Ghost: nowhere/* matches no tracked file", 1, true), problems)
  assert(str.find(problems, "LICENSE has no section for vendored Ghost", 1, true), problems)
end)

test("apply refuses, and check reports, a second notice above any line of dashes", function ()
  fixture()
  local before = "Copyright 2025 Birch Point SWE\n\nTerms.\n\nCopyright (C) 2007-2023 Lua.org, PUC-Rio.\n"
  fs.writefile(fs.join(dir, "LICENSE"), before)
  local opts = { dir = dir, copyright = "Birch Point SWE" }
  assert(eq(false, (err.pcall(license.apply, opts))))
  assert(eq(before, read("LICENSE")))
  local problems = arr.concat(license.check(opts), "\n")
  assert(str.find(problems, "more than one copyright notice", 1, true), problems)
end)

test("render fills the copyright line once and wraps at 80 columns", function ()
  local long = str.rep("word ", 30)
  local text = license.render("MIT", {
    "MIT License", "", "Copyright (c) <year> <copyright holders>", "", long, "",
    "The above copyright notice and this permission notice shall be included.",
  }, "2023", "Birch Point SWE")
  assert(str.find(text, "\nCopyright (c) 2023 Birch Point SWE\n", 1, true), text)
  for line in str.gmatch(text, "[^\n]+") do
    assert(#line <= 80, line)
  end
  assert(eq(30, select(2, str.gsub(text, "word", "word"))))
  assert(str.find(text, "\n\nThe above copyright", 1, true), text)
end)

local spdx_mit = {
  "MIT License", "", "Copyright (c) <year> <copyright holders>", "",
  "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and",
  "associated documentation files (the \"Software\"), to deal in the Software without restriction, including",
  "without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell",
  "copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the",
  "following conditions:", "",
  "The above copyright notice and this permission notice shall be included in all copies or substantial",
  "portions of the Software.",
}

local function assert_paragraphs (text, prefix)
  for para in str.gmatch(text .. "\n", "(.-)\n\n") do
    local lines = {}
    for line in str.gmatch(para, "[^\n]+") do
      assert(#line <= 80, line)
      arr.push(lines, line)
    end
    for i = 1, #lines - 1 do
      assert(#lines[i] >= 60, "short line inside a paragraph: " .. lines[i])
    end
  end
  assert(str.find(text, "\n" .. prefix .. "Permission is hereby granted", 1, true), text)
  assert(not str.find(text, "\n" .. prefix .. "following conditions:\n", 1, true), text)
  assert(str.find(text, "\n" .. prefix .. "Copyright ", 1, true), text)
end

test("render joins a paragraph's long lines before wrapping, so no short line is left mid-paragraph", function ()
  local text = license.render("MIT", spdx_mit, "2023", "Birch Point SWE")
  assert_paragraphs(text, "")
  assert(str.find(text, "MIT License\n\nCopyright (c) 2023 Birch Point SWE\n\n", 1, true), text)
  local filled = str.gsub(arr.concat(spdx_mit, " "), "<year> <copyright holders>", "2023 Birch Point SWE")
  local words = select(2, str.gsub(filled, "%S+", ""))
  assert(eq(words, select(2, str.gsub(text, "%S+", ""))))
end)

test("a vendored section reflows real-length license text under its indent", function ()
  fixture()
  local opts = vopts({ lpeg })
  opts.texts = { MIT = spdx_mit }
  license.apply(opts)
  local text = read("LICENSE")
  local s = str.find(text, dashes, 1, true)
  assert_paragraphs(str.sub(text, 1, s - 1), "")
  assert_paragraphs(str.sub(text, s), "  ")
  assert(str.find(text, "\n  Copyright (C) 2007-2023 Lua.org, PUC-Rio.\n", 1, true), text)
  assert(eq(0, #license.check(opts)))
end)

local spdx_mit_full = arr.concat({
  "MIT License", "", "Copyright (c) <year> <copyright holders>", "",
  "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and",
  "associated documentation files (the \"Software\"), to deal in the Software without restriction, including",
  "without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell",
  "copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the",
  "following conditions:", "",
  "The above copyright notice and this permission notice shall be included in all copies or substantial",
  "portions of the Software.", "",
  "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT",
  "LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO",
  "EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER",
  "IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE",
  "USE OR OTHER DEALINGS IN THE SOFTWARE.",
}, "\n") .. "\n"

local fetched_license = arr.concat({
  "MIT License",
  "",
  "Copyright (c) 2023 Birch Point SWE",
  "",
  "Permission is hereby granted, free of charge, to any person obtaining a copy of",
  "this software and associated documentation files (the \"Software\"), to deal in",
  "the Software without restriction, including without limitation the rights to",
  "use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of",
  "the Software, and to permit persons to whom the Software is furnished to do so,",
  "subject to the following conditions:",
  "",
  "The above copyright notice and this permission notice shall be included in all",
  "copies or substantial portions of the Software.",
  "",
  "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR",
  "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS",
  "FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR",
  "COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER",
  "IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN",
  "CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.",
  "",
  str.rep("-", 80),
  "",
  "This package vendors LPeg 1.1.0 (vendor.lua), which is:",
  "",
  "  MIT License",
  "",
  "  Copyright (C) 2007-2023 Lua.org, PUC-Rio.",
  "",
  "  Permission is hereby granted, free of charge, to any person obtaining a copy",
  "  of this software and associated documentation files (the \"Software\"), to deal",
  "  in the Software without restriction, including without limitation the rights",
  "  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell",
  "  copies of the Software, and to permit persons to whom the Software is",
  "  furnished to do so, subject to the following conditions:",
  "",
  "  The above copyright notice and this permission notice shall be included in all",
  "  copies or substantial portions of the Software.",
  "",
  "  THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR",
  "  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,",
  "  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE",
  "  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER",
  "  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,",
  "  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE",
  "  SOFTWARE.",
  "",
  "Modified for santoku.",
}, "\n") .. "\n"

test("a fetched license text keeps its blank lines and paragraph breaks", function ()
  fixture()
  local bin = fs.absolute("test/res/license-bin")
  sys.execute({ "rm", "-rf", bin })
  fs.mkdirp(bin)
  fs.writefile(fs.join(bin, "MIT.txt"), spdx_mit_full)
  fs.writefile(fs.join(bin, "curl"), "#!/bin/sh\ncat '" .. fs.join(bin, "MIT.txt") .. "'\n")
  sys.execute({ "chmod", "+x", fs.join(bin, "curl") })
  local opts = vopts({ lpeg })
  opts.texts = nil
  local path = env.var("PATH")
  sys.setenv("PATH", bin .. ":" .. path)
  local ok, _, e = err.pcall(license.apply, opts)
  sys.setenv("PATH", path)
  sys.execute({ "rm", "-rf", bin })
  assert(ok, tostring(e))
  local text = read("LICENSE")
  assert(eq(fetched_license, text))
  local source_paras = select(2, str.gsub(spdx_mit_full, "\n\n", ""))
  local managed = str.sub(text, 1, str.find(text, str.rep("-", 80), 1, true) - 1)
  assert(eq(source_paras, select(2, str.gsub(managed, "\n\n", "")) - 1))
end)

test("a vendored entry's inline text is used verbatim and nothing is fetched", function ()
  fixture()
  local pd = {
    name = "SHA-256", path = { "vendor.lua" }, license = "LicenseRef-PublicDomain",
    text = "This code is released into the public domain.\n\nAcknowledgement is requested, not required.\n",
  }
  local opts = vopts({ pd })
  license.apply(opts)
  local text = read("LICENSE")
  assert(str.find(text, "\n\nThis package vendors SHA-256 (vendor.lua), which is:\n\n"
    .. "  This code is released into the public domain.\n\n"
    .. "  Acknowledgement is requested, not required.\n", 1, true), text)
  assert(eq(0, #license.check(opts)))
end)

test("render refuses a text with no copyright line to fill", function ()
  local ok = err.pcall(license.render, "AGPL-3.0-only", {
    "GNU AFFERO GENERAL PUBLIC LICENSE", "", "Copyright (C) <year>  <name of author>",
  }, "2023", "Birch Point SWE")
  assert(eq(false, ok))
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
