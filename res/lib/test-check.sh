#!/bin/sh

export LUA='<% return lua %>'
export LUA_PATH='<% return lua_path %>'
export LUA_CPATH='<% return lua_cpath %>'

echo

if type luacheck >/dev/null 2>/dev/null && [ -f luacheck.lua ]; then
<% push(is_wasm) %>
  find lib bin bundler-pre/test/spec -maxdepth 0 2>/dev/null > luacheck.in.txt
  nl="$(wc -l luacheck.in.txt | cut -d' ' -f1)"
  if [ $nl -gt 0 ]; then
    xargs -a luacheck.in.txt luacheck --config luacheck.lua
  fi
  status_chk=$?
<% pop() push(not is_wasm) %>
  find lib bin test/spec -maxdepth 0 2>/dev/null > luacheck.in.txt
  nl="$(wc -l luacheck.in.txt | cut -d' ' -f1)"
  if [ $nl -gt 0 ]; then
    xargs -a luacheck.in.txt luacheck --config luacheck.lua
  fi
  status_chk=$?
<% pop() %>
fi

echo

if [ "$status_chk" != "0" ]; then
  exit 1
else
  exit 0
fi
