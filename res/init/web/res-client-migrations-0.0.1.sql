create table records (
  id integer primary key,
  data,
  created_at real not null default (unixepoch('now', 'subsec')),
  updated_at real not null default (unixepoch('now', 'subsec')),
  deleted boolean not null default false,
  synced_at real,
  hlc real not null default (unixepoch('now', 'subsec'))
);

create table settings (
  key text primary key,
  value text
);
