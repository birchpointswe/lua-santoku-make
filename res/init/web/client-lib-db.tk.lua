<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), readfile(fp)
  end, fs.files("res/client/migrations"))), true)
%>

local js = require("santoku.web.js")
local sqlite_worker = require("santoku.web.sqlite.worker")
local migrate = require("santoku.sqlite.migrate")
local tpl = require("__NAME__.web.templates")
local Math = js.Math

return sqlite_worker("/__NAME__.db", function (ok, db, callback)

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
      numbers[i] = { number = numbers[i], tag = "SW", sw = true }
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

  local get_setting = db.getter([[
    select value from settings where key = ?
  ]])

  local set_setting = db.runner([[
    insert into settings (key, value) values (?1, ?2)
    on conflict (key) do update set value = ?2
  ]])

  M.get_authorization = function ()
    return get_setting("authorization")
  end

  M.set_authorization = function (auth)
    return set_setting("authorization", auth)
  end

  M.has_authorization = function ()
    return M.get_authorization() ~= nil
  end

  return callback(true, M)

end)
