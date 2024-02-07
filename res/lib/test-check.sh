#!/bin/sh

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

if type luacov >/dev/null 2>/dev/null && [ -f <% return luacov_stats_file %> ] && [ -f luacov.lua ]; then
  luacov -c luacov.lua
fi

if [ -f <% return luacov_report_file %> ]; then
  cat <% return luacov_report_file %> | awk '/^Summary/ { P = NR } P && NR > P + 1'
fi

echo

if type luacheck >/dev/null 2>/dev/null && [ -f luacheck.lua ]; then
<% push(wasm) %>
  luacheck --config luacheck.lua $(find lib bin bundler-pre/test/spec -maxdepth 0 2>/dev/null)
  status_chk=$?
<% pop() push(not wasm) %>
  luacheck --config luacheck.lua $(find lib bin test/spec -maxdepth 0 2>/dev/null)
  status_chk=$?
<% pop() %>
fi

echo

if [ "$status_chk" != "0" ]; then
  exit 1
else
  exit 0
fi
