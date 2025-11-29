create table numbers (
  id integer primary key,
  number integer not null,
  created_at text default (datetime('now'))
);
