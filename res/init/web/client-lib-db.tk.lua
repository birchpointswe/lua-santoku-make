<%
  local fs = require("santoku.fs")
  local iter = require("santoku.iter")
  local serialize = require("santoku.serialize")
  t_migrations = serialize(iter.tabulate(iter.map(function (fp)
    return fs.basename(fp), readfile(fp)
  end, fs.files("res/client/migrations"))), true)
%>

local sqlite_worker = require("santoku.web.sqlite.worker")
local migrate = require("santoku.sqlite.migrate")
local tpl = require("__NAME__.web.templates")
local utc = require("santoku.utc")

local PAGE_SIZE = 10

local function format_record (rec)
  if not rec then return nil end
  rec.created_ats = utc.format(rec.created_at, "%Y-%m-%d %H:%M", true)
  rec.updated_ats = utc.format(rec.updated_at, "%Y-%m-%d %H:%M", true)
  rec.needs_sync = not rec.synced_at or rec.synced_at < rec.updated_at
  return rec
end

local function format_records (recs)
  for i = 1, #recs do
    format_record(recs[i])
  end
  return recs
end

return sqlite_worker("/__NAME__.db", function (ok, db, callback)

  if not ok then
    return callback(false, db)
  end

  db.exec("pragma locking_mode = EXCLUSIVE")
  db.exec("pragma journal_mode = WAL")
  db.exec("pragma synchronous = NORMAL")
  db.exec("pragma temp_store = MEMORY")
  db.exec("pragma cache_size = -2000")

  migrate(db, <% return t_migrations %>) -- luacheck: ignore

  local M = {}

  local get_records_page = db.all([[
    select id, data as number, created_at, updated_at, synced_at, hlc, true as sw
    from records
    where not deleted
    order by created_at desc, id desc
    limit ?1 offset ?2
  ]], true)

  local get_record_count = db.getter([[
    select count(*) as total from records where not deleted
  ]], true)

  local get_dirty_ids = db.all([[
    select id from records
    where (synced_at is null or synced_at < updated_at)
    and not deleted
  ]], true)

  M.get_numbers = function (page)
    page = tonumber(page) or 1
    if page < 1 then page = 1 end
    local offset = (page - 1) * PAGE_SIZE
    local count_result = get_record_count()
    local total = count_result and count_result.total or 0
    local total_pages = math.max(1, math.ceil(total / PAGE_SIZE))
    if page > total_pages then page = total_pages end
    return tpl["number-items"]({
      numbers = format_records(get_records_page(PAGE_SIZE, offset) or {}),
      page = page,
      total_pages = total_pages,
      show_pagination = total_pages > 1,
      has_prev = page > 1,
      has_next = page < total_pages,
      prev_page = page - 1,
      next_page = page + 1
    })
  end

  local get_setting = db.getter([[
    select value from settings where key = ?
  ]])

  local set_setting_insert = db.runner([[
    insert or ignore into settings (key, value) values (?1, ?2)
  ]])

  local set_setting_update = db.runner([[
    update settings set value = ?2 where key = ?1
  ]])

  local function set_setting (key, value)
    set_setting_insert(key, value)
    set_setting_update(key, value)
  end

  local create_number = db.getter([[
    insert into records (data, hlc)
    values (
      abs(random()) % 1000000000,
      max(unixepoch('now', 'subsec'), coalesce((select max(hlc) from records), 0) + 0.001)
    )
    returning id, data as number, created_at, updated_at, synced_at, hlc, true as sw
  ]], true)

  local update_number = db.getter([[
    update records set
      data = abs(random()) % 1000000000,
      updated_at = unixepoch('now', 'subsec'),
      hlc = max(unixepoch('now', 'subsec'), hlc + 0.001)
    where id = ?1
    returning id, data as number, created_at, updated_at, synced_at, true as sw
  ]], true)

  local was_dirty = db.getter([[
    select synced_at is null or synced_at < updated_at
    from records where id = ?1
  ]])

  M.create_number = function ()
    return tpl["number-item"](format_record(create_number()))
  end

  M.update_number = function (id)
    return tpl["number-item"](format_record(update_number(id)))
  end

  M.delete_number = db.runner([[
    update records set
      deleted = true,
      updated_at = unixepoch('now', 'subsec'),
      hlc = max(unixepoch('now', 'subsec'), hlc + 0.001)
    where id = ?1
  ]])

  M.get_changes = db.getter([[
    select json_group_array(json_object(
      'id', id,
      'data', data,
      'created_at', created_at,
      'updated_at', updated_at,
      'deleted', deleted,
      'hlc', hlc
    )) from records
    where synced_at is null or synced_at < updated_at
  ]])

  local apply_changes_insert = db.runner([[
    insert or ignore into records (id, data, created_at, updated_at, deleted, synced_at, hlc)
    select
      json_extract(value, '$.id'),
      json_extract(value, '$.data'),
      json_extract(value, '$.created_at'),
      json_extract(value, '$.updated_at'),
      json_extract(value, '$.deleted'),
      unixepoch('now', 'subsec'),
      json_extract(value, '$.hlc')
    from json_each(?1)
  ]])

  local apply_changes_update = db.runner([[
    update records set
      data = json_extract(j.value, '$.data'),
      created_at = json_extract(j.value, '$.created_at'),
      updated_at = json_extract(j.value, '$.updated_at'),
      deleted = json_extract(j.value, '$.deleted'),
      synced_at = unixepoch('now', 'subsec'),
      hlc = json_extract(j.value, '$.hlc')
    from json_each(?1) j
    where records.id = json_extract(j.value, '$.id')
    and json_extract(j.value, '$.hlc') > records.hlc
  ]])

  M.apply_changes = function (changes)
    apply_changes_insert(changes)
    apply_changes_update(changes)
  end

  M.mark_synced = db.runner([[
    update records set synced_at = unixepoch('now', 'subsec')
    where synced_at is null or synced_at < updated_at
  ]])

  M.has_unsynced = db.getter([[
    select exists(select 1 from records where synced_at is null or synced_at < updated_at) as has_unsynced
  ]], true)

  M.get_authorization = function ()
    return get_setting("authorization")
  end

  M.set_authorization = function (auth)
    return set_setting("authorization", auth)
  end

  M.has_authorization = function ()
    return M.get_authorization() ~= nil
  end

  M.get_last_sync = function ()
    return get_setting("last_sync_at")
  end

  M.set_last_sync = function (ts)
    return set_setting("last_sync_at", ts)
  end

  M.get_auto_sync = function ()
    local result = get_setting("auto_sync")
    return result and result == "1"
  end

  M.set_auto_sync = function (enabled)
    return set_setting("auto_sync", enabled and "1" or "0")
  end

  local function compute_state (has_auth, has_unsynced, auto_sync)
    if not has_auth then
      return "error"
    elseif not has_unsynced then
      return "synced"
    elseif auto_sync then
      return "pending"
    else
      return "dirty"
    end
  end

  local function get_sync_state_data ()
    local unsynced_result = M.has_unsynced()
    local has_unsynced = unsynced_result and unsynced_result.has_unsynced == 1 or false
    local has_auth = M.has_authorization()
    local auto_sync = M.get_auto_sync()
    return {
      state = compute_state(has_auth, has_unsynced, auto_sync),
      auto_sync = auto_sync
    }
  end

  M.get_sync_status = function ()
    return tpl["sync-state"](get_sync_state_data())
  end

  M.toggle_auto_sync = function ()
    local current = M.get_auto_sync()
    M.set_auto_sync(not current)
    local data = get_sync_state_data()
    if data.auto_sync and data.state == "pending" then
      data.trigger_sync = true
    end
    return tpl["sync-state"](data)
  end

  local function get_sync_state_oob ()
    local auto_sync = M.get_auto_sync()
    return tpl["sync-state"]({
      state = auto_sync and "pending" or "dirty",
      auto_sync = auto_sync,
      oob = true,
      trigger_sync = auto_sync
    })
  end

  M.create_number_with_state = function ()
    create_number()
    return M.get_numbers(1) .. get_sync_state_oob()
  end

  M.update_number_with_state = function (id)
    local already_dirty = was_dirty(id) == 1
    local rec = format_record(update_number(id))
    if not already_dirty then
      rec.just_dirtied = true
    end
    local html = tpl["number-item"](rec)
    return html .. get_sync_state_oob()
  end

  M.delete_number_with_state = function (id, page)
    M.delete_number(id)
    page = tonumber(page) or 1
    return M.get_numbers(page) .. get_sync_state_oob()
  end

  M.get_auth_status = function ()
    return tpl["session-state"]({ has_session = M.has_authorization() })
  end

  M.delete_session = function ()
    M.set_authorization(nil)
    return tpl["session-state"]({ has_session = false })
  end

  M.save_session = function (auth)
    M.set_authorization(auth)
    return tpl["session-state"]({ has_session = true })
  end

  M.get_numbers_with_error_state = function (page)
    local numbers_html = M.get_numbers(page)
    local sync_state = tpl["sync-state"]({
      state = "error",
      auto_sync = M.get_auto_sync(),
      oob = true
    })
    return numbers_html .. sync_state
  end

  M.complete_sync = function (server_changes_json, page)
    M.apply_changes(server_changes_json)

    local dirty_set = {}
    local dirty_records = get_dirty_ids() or {}
    for i = 1, #dirty_records do
      dirty_set[dirty_records[i].id] = true
    end

    M.mark_synced()

    page = tonumber(page) or 1
    if page < 1 then page = 1 end
    local offset = (page - 1) * PAGE_SIZE
    local count_result = get_record_count()
    local total = count_result and count_result.total or 0
    local total_pages = math.max(1, math.ceil(total / PAGE_SIZE))
    if page > total_pages then page = total_pages end

    local numbers = get_records_page(PAGE_SIZE, offset) or {}
    for i = 1, #numbers do
      format_record(numbers[i])
      numbers[i].just_synced = dirty_set[numbers[i].id] == true
    end

    local numbers_html = tpl["number-items"]({
      numbers = numbers,
      page = page,
      total_pages = total_pages,
      show_pagination = total_pages > 1,
      has_prev = page > 1,
      has_next = page < total_pages,
      prev_page = page - 1,
      next_page = page + 1
    })
    local sync_state = tpl["sync-state"]({
      state = "synced",
      auto_sync = M.get_auto_sync(),
      oob = true
    })
    return numbers_html .. sync_state
  end

  return callback(true, M)

end)
