<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), fs.readfile(fp)
  end, fs.files("res/migrations"))), true)
%>

local lsqlite3 = require("lsqlite3")
local sqlite = require("santoku.sqlite")
local sqlite_migrate = require("santoku.sqlite.migrate")

return function (db_file)

  if type(db_file) == "table" then
    return db_file
  end

  local M = {}
  local db = sqlite(lsqlite3.open(db_file))

  db.exec("pragma journal_mode = WAL")
  db.exec("pragma synchronous = NORMAL")
  db.exec("pragma busy_timeout = 30000")

  sqlite_migrate(db, <%% return t_migrations %%>) -- luacheck: ignore

  M.db = db

  local get_session = db.getter([[
    select id, session_id from sessions where session_id = ?
  ]], true)

  local insert_session = db.inserter([[
    insert into sessions (session_id) values (?) returning id
  ]])

  M.get_or_create_session = function (session_id)
    local session = get_session(session_id)
    if session then
      return session.id
    end
    return insert_session(session_id)
  end

  M.add_number = db.inserter([[
    insert into numbers (session_id, number) values (?, ?)
  ]])

  M.get_numbers = db.all([[
    select number from numbers where session_id = ? order by created_at asc
  ]])

  return M

end
