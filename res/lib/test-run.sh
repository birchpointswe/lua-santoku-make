#!/bin/sh

<%
  arr = require("santoku.array")

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

<%
  local env_lines = {}
  for k, v in pairs(get(test or {}, "env_vars") or {}) do
    env_lines[#env_lines + 1] = sformat("export %s=%s", k, squote(v))
  end
  return arr.concat(env_lines, "\n")
%>

<%
  local script_lines = {}
  local scripts = get(test or {}, "env_scripts") or {}
  for i = 1, #scripts do
    if not sisempty(scripts[i]) then
      script_lines[#script_lines + 1] = ". " .. scripts[i]
    end
  end
  return arr.concat(script_lines, "\n")
%>

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

<% push(profile) %>
MODS="$MODS -l santoku.profile"
<% pop() %>

<% push(trace) %>
MODS="$MODS -l santoku.trace"
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
