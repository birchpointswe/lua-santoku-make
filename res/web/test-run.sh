#!/bin/sh

<%
  fs = require("santoku.fs")
  gen = require("santoku.gen")
  str = require("santoku.string")
  tbl = require("santoku.table")
%>

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

<% return gen.pairs(tbl.get(server or {}, "test", "env_vars") or {})
  :map(function (k, v)
    return str.interp("export %1=%2", { k, str.quote(v) })
  end):concat("\n") %>

<% return gen.ivals(tbl.get(server or {}, "test", "env_scripts") or {})
  :filter(function (env)
    return not str.isempty(env)
  end):map(function (env)
    return ". " .. env
  end):concat("\n") %>

rm -f luacov.stats.out luacov.report.out || true

<% template:push(profile) %>
  MODS="-l santoku.profile"
<% template:pop():push(not profile) %>
  MODS=""
<% template:pop() %>

<% template:push(single) %>
  toku test -s -i "$LUA" "<% return single %>"
  status_tst=$?
<% template:pop():push(not single) %>
  toku test -s -i "$LUA" --match "^.*%.lua$" server/test/spec
  status_tst=$?
<% template:pop() %>

if [ "$status_tst" = "0" ] && type luacov >/dev/null 2>/dev/null && [ -f luacov.stats.out ] && [ -f luacov.lua ]; then
  luacov -c luacov.lua
fi

if [ "$status_tst" = "0" ] && [ -f luacov.report.out ]; then
  cat luacov.report.out | awk '/^Summary/ { P = NR } P && NR > P + 1'
fi

echo

if type luacheck >/dev/null 2>/dev/null && [ -f luacheck.lua ]; then
  luacheck --config luacheck.lua $(find <% return fs.join(server_dir, "scripts") %> <% return fs.join(server_dir, "lib") %> server/test/spec -maxdepth 0 2>/dev/null)
  status_chk=$?
fi

echo

if [ "$status_tst" != "0" ] || [ "$status_chk" != "0" ]; then
  exit 1
else
  exit 0
fi
