#!/bin/sh

<%
  gen = require("santoku.gen")
  str = require("santoku.string")
  tbl = require("santoku.table")
%>

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

<% template:push(sanitize and not wasm) %>
LUA="env LD_PRELOAD=$(cc -print-file-name=libasan.so) $LUA"
<% template:pop() %>

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

echo

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

MODS=""

<% template:push(not skip_coverage) %>
MODS="$MODS -l luacov"
<% template:pop() %>

<% template:push(profile) %>
MODS="$MODS -l santoku.profile"
<% template:pop() %>

<% template:push(single) %>
toku test -s -i "$LUA $MODS" "<% return single %>"
status_tst=$?
<% template:pop():push(not single) %>
toku test -s -i "$LUA $MODS" --match "^.*%.lua$" test/spec
status_tst=$?
<% template:pop() %>

<% template:pop() %>

echo

if [ "$status_tst" != "0" ]; then
  exit 1
else
  exit 0
fi
