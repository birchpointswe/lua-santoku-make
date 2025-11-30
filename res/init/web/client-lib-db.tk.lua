<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), fs.readfile(fp)
  end, fs.files("res/client/migrations"))), true)
%>

local js = require("santoku.web.js")
local sqlite_worker = require("santoku.web.sqlite.worker")
local migrate = require("santoku.sqlite.migrate")
local tpl = require("<% return name %>.web.templates")
local Math = js.Math

return sqlite_worker("/<% return name %>.db", function (ok, db, callback)

  if not ok then
    return callback(false, db)
  end

  migrate(db, <% return t_migrations %>) -- luacheck: ignore

  local M = {}

  local get_numbers = db.all([[
    select number from numbers order by created_at desc
  ]])

  M.get_numbers = function ()
    local numbers = get_numbers()
    for i = 1, #numbers do
      numbers[i] = { number = numbers[i].number, tag = "SW", sw = true }
    end
    return tpl["number-items"]({ numbers = numbers })
  end

  local add_random = db.inserter([[
    insert into numbers (number) values (?1)
  ]])

  M.add_random = function ()
    local num = Math:floor(Math:random() * 1000) + 1
    add_random(num)
    return tpl["number-item"]({ number = num, tag = "SW", sw = true })
  end

  return callback(true, M)

end)
