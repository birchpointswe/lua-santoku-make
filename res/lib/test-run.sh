#!/bin/sh

<%
  iter = require("santoku.iter")
  collect = iter.collect
  map = iter.map
  pairs = iter.pairs
  ivals = iter.ivals
  filter = iter.filter

  arr = require("santoku.array")
  concat = arr.concat

  str = require("santoku.string")
  sisempty = str.isempty
  squote = str.quote
  sformat = string.format

  tbl = require("santoku.table")
  get = tbl.get
%>

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

<% push(sanitize and not wasm) %>
LUA="env LD_PRELOAD=$(cc -print-file-name=libasan.so) $LUA"
<% pop() %>

<% return concat(collect(map(function (k, v)
    return sformat("export %s=%s", k, squote(v))
  end, pairs(get(test or {}, "env_vars") or {}))), "\n") %>

<% return concat(collect(map(function (env)
    return ". " .. env
  end, filter(function (e)
    return not sisempty(env)
  end, ivals(get(test or {}, "env_scripts") or {})))), "\n") %>

rm -f <% return luacov_stats_file %> <% return luacov_report_file %> || true

echo

<% push(wasm) %>

<% push(single) %>
TEST="<% return single %>"
toku test -s -i "node --expose-gc" "${TEST%.lua}"
status_tst=$?
<% pop() push(not single) %>
toku test -s -i "node --expose-gc" test/spec
status_tst=$?
<% pop() %>

<% pop() push(not wasm) %>

MODS=""

<% push(not skip_coverage) %>
MODS="$MODS -l luacov"
<% pop() %>

<% push(profile) %>
MODS="$MODS -l santoku.profile"
<% pop() %>

<% push(single) %>
toku test -s -i "$LUA $MODS" "<% return single %>"
status_tst=$?
<% pop() push(not single) %>
toku test -s -i "$LUA $MODS" --match "^.*%.lua$" test/spec
status_tst=$?
<% pop() %>

<% pop() %>

echo

if [ "$status_tst" != "0" ]; then
  exit 1
else
  exit 0
fi
