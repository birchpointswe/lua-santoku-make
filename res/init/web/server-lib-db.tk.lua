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

  local apply_changes_insert = db.runner([[
    insert or ignore into records (session_id, id, data, created_at, updated_at, deleted, hlc)
    select
      ?1 as session_id,
      json_extract(value, '$.id') as id,
      json_extract(value, '$.data') as data,
      json_extract(value, '$.created_at') as created_at,
      json_extract(value, '$.updated_at') as updated_at,
      json_extract(value, '$.deleted') as deleted,
      json_extract(value, '$.hlc') as hlc
    from json_each(?2)
  ]])

  local apply_changes_update = db.runner([[
    update records set
      data = json_extract(j.value, '$.data'),
      created_at = json_extract(j.value, '$.created_at'),
      updated_at = json_extract(j.value, '$.updated_at'),
      deleted = json_extract(j.value, '$.deleted'),
      hlc = json_extract(j.value, '$.hlc')
    from json_each(?2) j
    where records.session_id = ?1
    and records.id = json_extract(j.value, '$.id')
    and json_extract(j.value, '$.hlc') > records.hlc
  ]])

  M.apply_changes = function (session_id, changes)
    return db.transaction(function ()
      apply_changes_insert(session_id, changes)
      apply_changes_update(session_id, changes)
    end)
  end

  M.get_changes = db.getter([[
    select json_group_array(json_object(
      'id', id,
      'data', data,
      'created_at', created_at,
      'updated_at', updated_at,
      'deleted', deleted,
      'hlc', hlc))
    from
      records
    where
      session_id = ?1 and
      hlc > ?2
  ]])

  return M

end
