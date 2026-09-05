<%
  str = require("santoku.string")
  sys = require("santoku.system")
%>

local sys = require("santoku.system")
local vdt = require("santoku.validate")
local err = require("santoku.error")
local fs = require("santoku.fs")
local str = require("santoku.string")

local boilerplate_tar_b64 = <%
  local fs = require("santoku.fs")
  local tmp = fs.tmpname()
  sys.execute({ "tar", "-C", "submodules/tokuboilerplate-api", "--exclude", ".git", "--exclude", "build",
    "--mode", "a+rX,u+w,go-w", "-czf", tmp, "." })
  local content = fs.readfile(tmp)
  fs.rm(tmp)
  return str.quote(str.to_base64(content))
%>; -- luacheck: ignore

local function create (opts)
  err.assert(vdt.istable(opts), "opts must be a table")
  err.assert(vdt.isstring(opts.name), "opts.name is required")

  local name = opts.name
  local dir = opts.dir or name

  if not str.match(name, "^[a-z][a-z0-9%-]*$") then
    err.error("Invalid name: must start with lowercase letter and contain only lowercase letters, numbers, and hyphens")
  end

  if fs.exists(dir) then
    for _ in fs.files(dir, true) do
      err.error("target directory is not empty, refusing to scaffold into it", dir)
    end
  end

  fs.mkdirp(dir)
  local tmp = fs.tmpname()
  fs.writefile(tmp, str.from_base64(boilerplate_tar_b64))
  sys.execute({ "tar", "-C", dir, "-xzf", tmp })
  fs.rm(tmp)

  local mod_name = str.gsub(name, "%-", "_")

  do
    local src = fs.join(dir, "server/lib/tokuboilerplate")
    if fs.isdir(src) then
      fs.mv(src, fs.join(dir, "server/lib/" .. mod_name))
    end
  end

  do
    local src = fs.join(dir, "server/test/spec/tokuboilerplate.lua")
    if fs.exists(src) then
      fs.mv(src, fs.join(dir, "server/test/spec/" .. mod_name .. ".lua"))
    end
  end

  for fp in fs.files(dir, { recurse = true }) do
    local content = fs.readfile(fp)
    if content:find("tokuboilerplate") then
      if str.endswith(fp, "make.lua") then
        content = str.gsub(content, 'name = "tokuboilerplate"', 'name = "' .. name .. '"')
      end
      content = str.gsub(content, "tokuboilerplate", mod_name)
      fs.writefile(fp, content)
    end
  end

  if opts.git ~= false then
    sys.execute({ "git", "init", dir })
  end

  if opts.quiet then
    return
  end

  fs.stdout:write("Created API project: " .. name .. "\n")
  fs.stdout:write("\nNext steps:\n")
  if dir ~= "." then
    fs.stdout:write("  cd " .. dir .. "\n")
  end
  fs.stdout:write("  toku build --test  # Build for testing\n")
  fs.stdout:write("  toku start --test  # Start development server\n")
end

return {
  create = create,
}
