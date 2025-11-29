<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), fs.readfile(fp)
  end, fs.files("res/client/migrations"))), true)
%>
local js = require("santoku.web.js")
local sqlite = require("santoku.web.sqlite")
local migrate = require("santoku.sqlite.migrate")
local tpl = require("__NAME__.web.templates")

local Math = js.Math
local M = {}

M.init = function (callback)
  sqlite.open_opfs("/__NAME__.db", function (ok, db)
    if not ok then
      return callback(false, db)
    end

    migrate(db, <% return t_migrations %>) -- luacheck: ignore

    local handlers = {}

    handlers.get_numbers = function ()
      local get_all = db.all([[
        select number from numbers order by created_at desc
      ]], true)
      local numbers = {}
      for i, row in ipairs(get_all()) do
        numbers[i] = { number = row.number, tag = "SW", sw = true }
      end
      return tpl["number-items"]({ numbers = numbers })
    end

    handlers.add_random = function ()
      local insert = db.inserter([[
        insert into numbers (number) values ($1)
      ]])
      local num = Math:floor(Math:random() * 1000) + 1
      insert(num)
      return tpl["number-item"]({
        number = num,
        tag = "SW",
        sw = true
      })
    end

    callback(true, handlers)
  end)
end

return M
