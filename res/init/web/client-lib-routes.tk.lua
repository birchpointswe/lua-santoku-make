local tpl = require("<% return name %>.web.templates")

return function (db)
  return {

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

  }
end
