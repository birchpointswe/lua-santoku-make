create table sessions (
  id integer primary key,
  session_id text unique not null,
  created_at text default (datetime('now'))
);

create table numbers (
  id integer primary key,
  session_id integer not null references sessions(id),
  number integer not null,
  created_at text default (datetime('now'))
);

create index idx_numbers_session on numbers(session_id);
