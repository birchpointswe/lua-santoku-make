local compat = require("santoku.compat")
local err = require("santoku.err")
local str = require("santoku.string")
local gen = require("santoku.gen")
local vec = require("santoku.vector")
local fs = require("santoku.fs")

local posix = require("santoku.make.posix")

local M = {}
local MT = { __index = M }

M.target = function (o, ts, ds, fn)
  assert(compat.hasmeta.ipairs(ts))
  assert(compat.hasmeta.ipairs(ds))
  assert(fn == nil or fn == true or compat.hasmeta.call(fn))
  vec.wrap(ts)
  vec.wrap(ds)
  ts:each(function (t)
    assert(compat.istype.string(t))
    assert(o.targets[t] == nil and o.deps[t] == nil and o.fns[t] == nil,
      "target already registered: " .. (t or "(nil)"))
    o.targets[t] = ts
    o.deps[t] = ds
    o.fns[t] = fn
  end)
end

M.make = function (o, ts, verbosity, seen)
  verbosity = verbosity or 1
  seen = seen or {}
  return err.pwrap(function (check)
    vec.wrap(ts)
    return gen.ivals(ts):map(function (t)
      if seen[t] then
        return seen[t]
      end
      local ttime = check(fs.exists(t)) and check(posix.time(t))
      local dtimes = check(o:make(o.deps[t] or {}, verbosity, seen))
      if ttime and not dtimes:find(function (dt) return dt > ttime end) then
        if verbosity > 1 then
          str.printf("[ok]    \t%s\n", t)
        end
        seen[t] = ttime
        return ttime
      end
      if not ttime and not o.fns[t] then
        check(false, t .. ": target doesn't exist and no corresponding function registered")
      end
      if o.fns[t] == true then
        if verbosity > 0 then
          str.printf("[phony] \t%s\n", t)
        end
        return check(posix.now())
      else
        if verbosity > 0 then
          str.printf("[make]  \t%s\n", t)
        end
        check(o.fns[t](o.targets[t], o.deps[t]))
        seen[t] = check(posix.time(t))
        return seen[t]
      end
    end):vec()
  end)
end

return function ()
  return setmetatable({ targets = {}, deps = {}, fns = {} }, MT)
end
