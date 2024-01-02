#!/bin/sh

<%
  gen = require("santoku.gen")
  tbl = require("santoku.table")
%>

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

<% return gen.ivals(tbl.get(test or {}, "envs") or {}):map(function (env)
  return ". " .. env
end):concat("\n") %>

if [ -n "$TEST_CMD" ]; then

  set -x
  cd "$ROOT_DIR"
  $TEST_CMD

else

  rm -f luacov.stats.out luacov.report.out || true

  <% template:push(wasm) %>

  <% template:push(single) %>
    TEST="<% return single %>"
    toku test -s -i "node --expose-gc" "${TEST%.lua}"
    status=$?
  <% template:pop():push(not single) %>
    toku test -s -i "node --expose-gc" test/spec
    status=$?
  <% template:pop() %>

  <% template:pop():push(not wasm) %>

  <% template:push(profile) %>
    MODS="-l luacov -l santoku.profile"
  <% template:pop():push(not profile) %>
    MODS="-l luacov"
  <% template:pop() %>

  <% template:push(single) %>
    toku test -s -i "$LUA $MODS" "<% return single %>"
    status=$?
  <% template:pop():push(not single) %>
    toku test -s -i "$LUA $MODS" --match "^.*%.lua$" test/spec
    status=$?
  <% template:pop() %>

  <% template:pop() %>

  if [ "$status" = "0" ] && type luacov >/dev/null 2>/dev/null && [ -f luacov.stats.out ] && [ -f luacov.lua ]; then
    luacov -c luacov.lua
  fi

  if [ "$status" = "0" ] && [ -f luacov.report.out ]; then
    cat luacov.report.out | awk '/^Summary/ { P = NR } P && NR > P + 1'
  fi

  echo

  if type luacheck >/dev/null 2>/dev/null && [ -f luacheck.lua ]; then
  <% template:push(wasm) %>
    luacheck --config luacheck.lua $(find lib bin bundler-pre/test/spec -maxdepth 0 2>/dev/null)
  <% template:pop():push(not wasm) %>
    luacheck --config luacheck.lua $(find lib bin test/spec -maxdepth 0 2>/dev/null)
  <% template:pop() %>
  fi

  echo

fi
