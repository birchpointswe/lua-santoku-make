create table sessions (
  id integer primary key,
  session_id text unique not null,
  created_at real not null default (unixepoch('now', 'subsec'))
);

create table records (
  id integer not null,
  session_id integer not null references sessions(id),
  data,
  created_at real not null default (unixepoch('now', 'subsec')),
  updated_at real not null default (unixepoch('now', 'subsec')),
  deleted boolean not null default false,
  hlc real not null default (unixepoch('now', 'subsec')),
  primary key (id, session_id)
);

create index idx_records_session on records(session_id);
