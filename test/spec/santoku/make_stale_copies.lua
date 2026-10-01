-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2023 Birch Point SWE
local test = require("santoku.test")
local validate = require("santoku.validate")
local eq = validate.isequal
local fs = require("santoku.fs")
local sys = require("santoku.system")
local project = require("santoku.make.project")

local root = fs.absolute("test/res/stale-copies")

local function write_files (dir, files)
  sys.execute({ "rm", "-rf", dir })
  for rel, body in pairs(files) do
    local fp = fs.join(dir, rel)
    fs.mkdirp(fs.dirname(fp))
    fs.writefile(fp, body)
  end
end

local function init ()
  return project.init({ openresty_dir = "/nonexistent" })
end

test("a web project drops test-tree copies whose source was deleted", function ()

  local dir = fs.join(root, "web")
  write_files(dir, {
    ["make.lua"] = [[
return {
  type = "web",
  env = {
    name = "stalefixture",
    version = "0.0.1-1",
    client = {},
    server = {},
    nginx = { domain = "localhost", port = "8080" },
  },
}
]],
    ["client/test/spec/kept.lua"] = "return true\n",
    ["client/test/spec/gone.lua"] = "return true\n",
    ["server/test/spec/kept.lua"] = "return true\n",
    ["server/test/spec/gone.lua"] = "return true\n",
    ["server/lib/stalefixture.lua"] = "return \"ok\"\n",
    ["server/lib/stalefixture/gone.lua"] = "return \"ok\"\n",
  })

  fs.pushd(dir, function ()

    local function copy (...)
      return fs.join(fs.absolute("build"), "default", "test", ...)
    end

    local copies = {
      kept = {
        copy("client", "test/spec/kept.lua"),
        copy("server", "test/spec/kept.lua"),
        copy("server", "lib/stalefixture.lua"),
      },
      gone = {
        copy("client", "test/spec/gone.lua"),
        copy("server", "test/spec/gone.lua"),
        copy("server", "lib/stalefixture/gone.lua"),
      },
    }

    local all = {}
    for _, group in pairs(copies) do
      for _, fp in ipairs(group) do
        all[#all + 1] = fp
      end
    end
    init().submake.build(all, 0)
    for _, fp in ipairs(all) do
      assert(eq(true, fs.exists(fp)), "the copy must exist before its source is deleted: " .. fp)
    end

    fs.rm("client/test/spec/gone.lua")
    fs.rm("server/test/spec/gone.lua")
    fs.rm("server/lib/stalefixture/gone.lua")
    init()

    for _, fp in ipairs(copies.gone) do
      assert(eq(false, fs.exists(fp)), "a copy whose source was deleted must be removed: " .. fp)
    end
    for _, fp in ipairs(copies.kept) do
      assert(eq(true, fs.exists(fp)), "a copy whose source still exists must stay: " .. fp)
    end

  end)

  sys.execute({ "rm", "-rf", dir })

end)

sys.execute({ "rm", "-rf", root })
