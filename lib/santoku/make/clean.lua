local fs = require("santoku.fs")
local sys = require("santoku.system")
local iter = require("santoku.iter")
local arr = require("santoku.array")
local str = require("santoku.string")
local err = require("santoku.error")

local function is_contained(path)
  local cwd = str.gsub(fs.cwd() or "", "/+$", "")
  local abs = str.gsub(fs.absolute(path) or "", "/+$", "")
  if abs == "" then
    return false
  end
  return abs == cwd or str.startswith(abs, cwd .. "/")
end

local function remove_if_exists(path, dry_run, removed)
  if not is_contained(path) then
    err.error("refusing to remove path outside project directory: " .. tostring(path))
  end
  if fs.exists(path) then
    arr.push(removed, path)
    if not dry_run then
      sys.execute({ "rm", "-rf", path })
    end
  end
end

local function remove_matching(dir, pattern, dry_run, removed)
  if not fs.exists(dir) then
    return
  end
  if not is_contained(dir) then
    err.error("refusing to remove from path outside project directory: " .. tostring(dir))
  end
  for fp in fs.files(dir, true) do
    if str.match(fp, pattern) then
      arr.push(removed, fp)
      if not dry_run then
        sys.execute({ "rm", "-rf", fp })
      end
    end
  end
end

local function clean_lib(opts)
  opts = opts or {}
  local removed = {}
  local dry_run = opts.dry_run
  local base_dir = opts.dir or "build"

  if opts.all then
    if opts.env then
      remove_if_exists(fs.join(base_dir, opts.env), dry_run, removed)
    else
      remove_if_exists(base_dir, dry_run, removed)
    end
    return removed
  end

  local work_dir = fs.join(base_dir, opts.env or "default")

  local test_dir = fs.join(work_dir, "test")
  local build_dir = fs.join(work_dir, "build")

  if opts.deps then
    remove_if_exists(fs.join(test_dir, "lua_modules"), dry_run, removed)
    remove_if_exists(fs.join(test_dir, "lua_modules.ok"), dry_run, removed)
    remove_if_exists(fs.join(build_dir, "lua_modules"), dry_run, removed)
    remove_if_exists(fs.join(build_dir, "lua_modules.ok"), dry_run, removed)
    return removed
  end

  remove_matching(work_dir, "%.ok$", dry_run, removed)
  for i = #removed, 1, -1 do
    if str.match(removed[i], "lua_modules%.ok$") then
      arr.remove(removed, i)
    end
  end

  remove_matching(work_dir, "%.d$", dry_run, removed)

  for _, subdir in iter.ivals({ "lib", "bin", "test/res" }) do
    remove_matching(fs.join(test_dir, subdir), "%.lua$", dry_run, removed)
    remove_matching(fs.join(build_dir, subdir), "%.lua$", dry_run, removed)
  end

  remove_if_exists(fs.join(test_dir, "luarocks.lua"), dry_run, removed)
  remove_if_exists(fs.join(test_dir, "luacheck.lua"), dry_run, removed)
  remove_if_exists(fs.join(build_dir, "luarocks.lua"), dry_run, removed)
  remove_if_exists(fs.join(build_dir, "luacheck.lua"), dry_run, removed)

  return removed
end

local function clean_web(opts)
  opts = opts or {}
  local removed = {}
  local dry_run = opts.dry_run
  local base_dir = opts.dir or "build"

  if opts.all then
    if opts.env then
      remove_if_exists(fs.join(base_dir, opts.env), dry_run, removed)
    else
      remove_if_exists(base_dir, dry_run, removed)
    end
    return removed
  end

  local work_dir = fs.join(base_dir, opts.env or "default")

  local clean_client = opts.client or (not opts.server)
  local clean_server = opts.server or (not opts.client)

  local test_dir = fs.join(work_dir, "test")
  local main_dir = fs.join(work_dir, "main")

  if opts.deps then
    remove_if_exists(fs.join(work_dir, "build-deps"), dry_run, removed)
    remove_if_exists(fs.join(work_dir, "build-deps.ok"), dry_run, removed)
    remove_if_exists(fs.join(work_dir, "build-deps-luarocks.lua"), dry_run, removed)
  end

  for _, env_dir in iter.ivals({ test_dir, main_dir }) do
    if env_dir then
      if clean_server then
        local server_dir = fs.join(env_dir, "server")
        local dist_dir = fs.join(env_dir, "dist")

        if opts.deps then
          remove_if_exists(fs.join(server_dir, "lua_modules"), dry_run, removed)
          remove_if_exists(fs.join(server_dir, "lua_modules.ok"), dry_run, removed)
          remove_if_exists(fs.join(dist_dir, "lua_modules"), dry_run, removed)
        elseif not opts.wasm then
          remove_if_exists(fs.join(server_dir, "luarocks.lua"), dry_run, removed)
          remove_if_exists(fs.join(server_dir, "nginx.conf"), dry_run, removed)
          remove_if_exists(fs.join(server_dir, "run.sh"), dry_run, removed)
          remove_if_exists(fs.join(server_dir, "init-test.lua"), dry_run, removed)
          remove_if_exists(fs.join(server_dir, "init-worker-test.lua"), dry_run, removed)
          remove_if_exists(fs.join(dist_dir, "nginx.conf"), dry_run, removed)
          remove_if_exists(fs.join(dist_dir, "run.sh"), dry_run, removed)
          remove_if_exists(fs.join(dist_dir, "init-test.lua"), dry_run, removed)
          remove_if_exists(fs.join(dist_dir, "init-worker-test.lua"), dry_run, removed)

          remove_matching(server_dir, "%.lua$", dry_run, removed)
          remove_matching(server_dir, "%.d$", dry_run, removed)

          if fs.exists(server_dir) and is_contained(server_dir) then
            for fp in fs.files(server_dir, true) do
              if str.match(fp, "%.ok$") and not str.match(fp, "lua_modules%.ok$") then
                arr.push(removed, fp)
                if not dry_run then
                  sys.execute({ "rm", "-rf", fp })
                end
              end
            end
          end
        end
      end

      if clean_client then
        local client_dir = fs.join(env_dir, "client")
        local dist_public = fs.join(env_dir, "dist", "public")

        if opts.deps then
          remove_if_exists(fs.join(client_dir, "lua_modules.ok"), dry_run, removed)
          remove_if_exists(fs.join(client_dir, "lua_modules.deps.ok"), dry_run, removed)
          remove_if_exists(fs.join(client_dir, "build"), dry_run, removed)
        elseif opts.wasm then
          remove_if_exists(fs.join(client_dir, "bundler-post"), dry_run, removed)
          remove_if_exists(fs.join(client_dir, "lua_modules.ok"), dry_run, removed)
          remove_matching(dist_public, "%.js$", dry_run, removed)
          remove_matching(dist_public, "%.wasm$", dry_run, removed)
        else
          remove_if_exists(fs.join(client_dir, "bundler-post"), dry_run, removed)
          remove_matching(client_dir, "%.d$", dry_run, removed)

          if fs.exists(client_dir) and is_contained(client_dir) then
            for fp in fs.files(client_dir, true) do
              if str.match(fp, "%.ok$") and not str.match(fp, "lua_modules") then
                arr.push(removed, fp)
                if not dry_run then
                  sys.execute({ "rm", "-rf", fp })
                end
              end
            end
          end

          remove_matching(dist_public, "%.js$", dry_run, removed)
          remove_matching(dist_public, "%.wasm$", dry_run, removed)
        end
      end
    end
  end

  return removed
end

return {
  lib = clean_lib,
  web = clean_web,
}
