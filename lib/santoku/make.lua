local err = require("santoku.error")
local assert = err.assert
local error = err.error

local validate = require("santoku.validate")
local hascall = validate.hascall
local hasindex = validate.hasindex
local isnumber = validate.isnumber

local str = require("santoku.string")
local printf = str.printf

local fs = require("santoku.fs")
local exists = fs.exists
local readfile = fs.readfile

local iter = require("santoku.iter")
local ivals = iter.ivals
local keys = iter.keys

local arr = require("santoku.array")
local extend = arr.extend

local huge = math.huge
local max = math.max

local posix = require("santoku.make.posix")
local modtime = posix.time

local tmpl = require("santoku.template")
local deserialize_deps = tmpl.deserialize_deps

return function ()

  local targets = {}
  local deps = {}
  local fns = {}

  local function target (ts, ds, fn)
    if not (fn == nil or fn == true) then
      assert(hascall(fn))
    end
    for t in ivals(ts) do
      local tt = targets[t] or {}
      local td = deps[t] or {}
      extend(tt, ts)
      extend(td, ds)
      targets[t] = tt
      deps[t] = td
      if fn ~= nil then
        assert(fns[t] == nil, "target already has a registered function or is registered as phony", t)
        fns[t] = fn
      end
    end
  end

  local function get_dfile_deps_time (t)
    local dfile = t .. ".d"
    if not exists(dfile) then
      return nil
    end
    local data = readfile(dfile)
    local file_deps = deserialize_deps(data)
    local maxtime = -huge
    for fp in keys(file_deps) do
      if exists(fp) then
        maxtime = max(maxtime, modtime(fp))
      end
    end
    return maxtime > -huge and maxtime or nil
  end

  local function _build (ts, verbosity, cache, ...)

    local maxtime = -huge

    for t in ivals(ts) do

      local tc = cache[t]

      if tc then

        maxtime = max(maxtime, tc)

      else

        local ttime = exists(t) and modtime(t)
        local dtime = deps[t] and _build(deps[t], verbosity, cache, ...)
        local ddtime = get_dfile_deps_time(t)
        if ddtime then
          dtime = dtime and max(dtime, ddtime) or ddtime
        end

        if ttime and (not dtime or dtime < ttime) then

          if verbosity > 1 then
            printf("[ok]    \t%s\n", t)
          end

          cache[t] = ttime
          maxtime = max(maxtime, ttime)

        elseif not ttime and not fns[t] then

          error("target doesn't exist and corresponding function not registered", t)

        elseif fns[t] == true then

          if verbosity > 1 then
            printf("[phony] \t%s\n", t)
          end

          maxtime = huge -- now()

        else

          if verbosity > 0 then
            printf("[make]  \t%s\n", t)
          end

          fns[t](targets[t], deps[t], ...)
          cache[t] = exists(t) and modtime(t) or nil
          maxtime = max(maxtime, cache[t] or maxtime)

        end

      end

    end

    return maxtime

  end

  local function build (ts, verbosity, ...)
    assert(hasindex(ts))
    verbosity = verbosity or 1
    assert(isnumber(verbosity))
    return _build(ts, verbosity, {}, ...)
  end

  return {
    target = target,
    build = build,
    targets = targets,
    deps = deps,
    fns = fns,
  }

end
