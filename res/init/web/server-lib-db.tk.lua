<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), readfile(fp)
  end, fs.files("res/server/migrations"))), true)
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
  db.exec("pragma cache_size = -2000")
  db.exec("pragma temp_store = MEMORY")
  db.exec("pragma mmap_size = 268435456")

  sqlite_migrate(db, <% return t_migrations %>) -- luacheck: ignore

  db.exec([[
    create temporary table if not exists records_incoming (
      id integer primary key,
      data text,
      created_at real,
      updated_at real,
      deleted integer,
      hlc real
    )
  ]])

  M.db = db

  M.random_hex = db.getter("select lower(hex(randomblob(?)))")

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

  local clear_incoming = db.runner([[
    delete from records_incoming
  ]])

  local populate_incoming = db.runner([[
    insert into records_incoming (id, data, created_at, updated_at, deleted, hlc)
    select
      json_extract(value, '$.id'),
      json_extract(value, '$.data'),
      json_extract(value, '$.created_at'),
      json_extract(value, '$.updated_at'),
      json_extract(value, '$.deleted'),
      json_extract(value, '$.hlc')
    from json_each(?1)
  ]])

  local insert_from_incoming = db.runner([[
    insert or ignore into records (session_id, id, data, created_at, updated_at, deleted, hlc)
    select ?1, id, data, created_at, updated_at, deleted, hlc
    from records_incoming
  ]])

  local update_from_incoming = db.runner([[
    update records set
      data = i.data,
      created_at = i.created_at,
      updated_at = i.updated_at,
      deleted = i.deleted,
      hlc = i.hlc
    from records_incoming i
    where records.session_id = ?1
      and records.id = i.id
      and i.hlc > records.hlc
  ]])

  local get_changes_excluding_incoming = db.getter([[
    select json_group_array(json_object(
      'id', id,
      'data', data,
      'created_at', created_at,
      'updated_at', updated_at,
      'deleted', deleted,
      'hlc', hlc))
    from records
    where session_id = ?1
      and hlc > ?2
      and id not in (select id from records_incoming)
  ]])

  M.sync = function (session_id, changes, since)
    return db.transaction(function ()
      clear_incoming()
      if changes then
        populate_incoming(changes)
        insert_from_incoming(session_id)
        update_from_incoming(session_id)
      end
      return get_changes_excluding_incoming(session_id, since)
    end)
  end

  return M

end
