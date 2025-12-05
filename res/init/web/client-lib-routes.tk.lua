local util = require("santoku.web.util")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
local async = require("santoku.async")
local tpl = require("__NAME__.web.templates")

local Headers = js.Headers
local Request = js.Request

return function (db)

  local function do_sync (authorization, page, done)
    return async.pipe(function (next)
      return db.get_changes(next)
    end, function (next, changes)
      local headers = Headers:new()
      headers:set("Content-Type", "application/json")
      headers:set("Authorization", authorization)
      local req = Request:new("/sync", val({
        method = "POST",
        headers = headers,
        body = changes
      }))
      return util.fetch(req, nil, { raw = true, done = next })
    end, function (next, response)
      if not response or not response.ok then
        return next(false)
      end
      return response:text():await(function (_, ok, text)
        return next(ok, text)
      end)
    end, function (ok, server_changes)
      if not ok then
        return db.get_numbers_with_error_state(page, done)
      end
      return db.complete_sync(server_changes, page, done)
    end)
  end

  local function create_session_and_sync (page, done)
    local req = Request:new("/session/create", val({ method = "POST" }))
    return async.pipe(function (next)
      return util.fetch(req, nil, { raw = true, done = next })
    end, function (next, response)
      if not response or not response.ok then
        return next(false)
      end
      local auth = response.headers:get("Authorization")
      if not auth then
        return next(false)
      end
      return db.set_authorization(auth, function (ok)
        return next(ok, auth)
      end)
    end, function (ok, auth)
      if not ok then
        return db.get_numbers_with_error_state(page, done)
      end
      return do_sync(auth, page, done)
    end)
  end

  return {

    ["^/app$"] = function (_, _, _, done)
      return done(true, tpl["app"]())
    end,

    ["^/numbers$"] = function (_, _, params, done)
      local page = tonumber(params.page) or 1
      return db.get_numbers(page, done)
    end,

    ["^/number/create$"] = function (_, _, _, done)
      return db.create_number_with_state(done)
    end,

    ["^/number/update$"] = function (_, _, params, done)
      err.assert(params.id, "missing id parameter")
      return db.update_number_with_state(params.id, done)
    end,

    ["^/number/delete$"] = function (_, _, params, done)
      err.assert(params.id, "missing id parameter")
      local page = tonumber(params.page) or 1
      return db.delete_number_with_state(params.id, page, done)
    end,

    ["^/auth/status$"] = function (_, _, _, done)
      return db.get_auth_status(done)
    end,

    ["^/session/delete$"] = function (_, _, _, done)
      return db.delete_session(done)
    end,

    ["^/session/create$"] = function (req, _, _, done)
      return async.pipe(function (next)
        return util.fetch(req.raw, nil, { raw = true, done = next })
      end, function (_, response)
        if not response or not response.ok then
          return done(false, "Failed to create session")
        end
        local auth = response.headers:get("Authorization")
        if not auth then
          return done(false, "Failed to create session")
        end
        return db.save_session(auth, done)
      end)
    end,

    ["^/sync/status$"] = function (_, _, _, done)
      return db.get_sync_status(done)
    end,

    ["^/auto%-sync/toggle$"] = function (_, _, _, done)
      return db.toggle_auto_sync(done)
    end,

    ["^/sync$"] = function (_, _, params, done)
      local page = tonumber(params.page) or 1
      return db.get_authorization(function (ok, auth)
        if not ok then
          return db.get_numbers_with_error_state(page, done)
        end
        if auth then
          return do_sync(auth, page, done)
        end
        return create_session_and_sync(page, done)
      end)
    end,

  }

end
