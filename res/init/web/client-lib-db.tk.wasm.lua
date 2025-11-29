<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), fs.readfile(fp)
  end, fs.files("res/client/migrations"))), true)
%>
local db = require("santoku.web.sqlite.db")

return db.define("<% return name %>.db", <% return t_migrations %>, function (db) -- luacheck: ignore
  return {
    add_number = db.inserter("insert into numbers (number) values (?)"),
    get_numbers = db.all("select number from numbers order by created_at desc", true),
  }
end)
