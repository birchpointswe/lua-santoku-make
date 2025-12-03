local tpl = require("<% return name %>.web.templates")
local util = require("santoku.web.util")
local js = require("santoku.web.js")
local val = require("santoku.web.val")

local Headers = js.Headers
local Request = js.Request

return function (db)

  local authorized_routes = {
    "/random",
    "/numbers"
  }

  local routes = {

    ["/app"] = function (_, _, done)
      return done(true, tpl["app"]())
    end,

    ["/random-sw"] = function (_, _, done)
      return db.add_random(function (ok, html)
        return done(ok, html or "Failed to add number")
      end)
    end,

    ["/numbers-sw"] = function (_, _, done)
      return db.get_numbers(function (ok, html)
        return done(ok, html or "Failed to get numbers")
      end)
    end,

    ["/auth/status"] = function (_, _, done)
      return db.has_authorization(function (ok2, has)
        return done(ok2, tpl["session-state"]({ has_session = has }))
      end)
    end,

    ["/session/delete"] = function (_, _, done)
      return db.set_authorization(nil, function (ok)
        if not ok then
          return done(false, "Failed to disable session")
        end
        return db.has_authorization(function (ok2, has)
          return done(ok2, tpl["session-state"]({ has_session = has }))
        end)
      end)
    end,

    ["/session/create"] = function (request, _, done)
      return util.fetch(request, nil, {
        raw = true,
        done = function (ok, response)
          local auth = response.headers:get("Authorization")
          if not ok or not response.ok or not auth then
            return done(false, "Failed to create session")
          end
          return db.set_authorization(auth, function (ok2)
            if not ok2 then
              return done(false, "Failed to enable session")
            end
            return response:text():await(function (_, ok3, html)
              return done(ok3, html or "Failed to read response")
            end)
          end)
        end
      })
    end,

  }

  for i = 1, #authorized_routes do
    routes[authorized_routes[i]] = function (request, _, done)
      return db.get_authorization(function (ok, auth)
        if not ok then
          return done(false, auth or "Failed to get auth token")
        end
        local req = request
        if auth then
          local headers = Headers:new(request.headers)
          headers:set("Authorization", auth)
          req = Request:new(request, val({ headers = headers }))
        end
        return util.fetch(req, nil, {
          raw = true,
          done = function (ok2, response)
            if not ok2 or not response.ok then
              return done(false, "Fetch failed")
            end
            return response:text():await(function (_, ok3, text)
              return done(ok3, text)
            end)
          end
        })
      end)
    end
  end

  return routes

end
