#!/bin/sh

<%
  gen = require("santoku.gen")
  str = require("santoku.string")
  tbl = require("santoku.table")
%>

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

<% return gen.pairs(tbl.get(test or {}, "env_vars") or {})
  :map(function (k, v)
    return str.interp("export %1=%2", { k, str.quote(v) })
  end):concat("\n") %>

<% return gen.ivals(tbl.get(test or {}, "env_scripts") or {}):filter(function (env)
    return not str.isempty(env)
  end):map(function (env)
    return ". " .. env
  end):concat("\n") %>

rm -f <% return luacov_stats_file %> <% return luacov_report_file %> || true

<% template:push(wasm) %>

<% template:push(single) %>
  TEST="<% return single %>"
  toku test -s -i "node --expose-gc" "${TEST%.lua}"
  status_tst=$?
<% template:pop():push(not single) %>
  toku test -s -i "node --expose-gc" test/spec
  status_tst=$?
<% template:pop() %>

<% template:pop():push(not wasm) %>

<% template:push(profile) %>
  MODS="-l luacov -l santoku.profile"
<% template:pop():push(not profile) %>
  MODS="-l luacov"
<% template:pop() %>

<% template:push(single) %>
  toku test -s -i "$LUA $MODS" "<% return single %>"
  status_tst=$?
<% template:pop():push(not single) %>
  toku test -s -i "$LUA $MODS" --match "^.*%.lua$" test/spec
  status_tst=$?
<% template:pop() %>

<% template:pop() %>

if [ "$status_tst" = "0" ] && type luacov >/dev/null 2>/dev/null && [ -f <% return luacov_stats_file %> ] && [ -f luacov.lua ]; then
  luacov -c luacov.lua
fi

if [ "$status_tst" = "0" ] && [ -f <% return luacov_report_file %> ]; then
  cat <% return luacov_report_file %> | awk '/^Summary/ { P = NR } P && NR > P + 1'
fi

echo

if type luacheck >/dev/null 2>/dev/null && [ -f luacheck.lua ]; then
<% template:push(wasm) %>
  luacheck --config luacheck.lua $(find lib bin bundler-pre/test/spec -maxdepth 0 2>/dev/null)
  status_chk=$?
<% template:pop():push(not wasm) %>
  luacheck --config luacheck.lua $(find lib bin test/spec -maxdepth 0 2>/dev/null)
  status_chk=$?
<% template:pop() %>
fi

echo

if [ "$status_tst" != "0" ] || [ "$status_chk" != "0" ]; then
  exit 1
else
  exit 0
fi
