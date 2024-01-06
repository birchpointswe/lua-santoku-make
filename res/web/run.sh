#!/bin/sh

<%
  str = require("santoku.string")
  gen = require("santoku.gen")
  server = server or {}
%>

set -e

cd "$(dirname $0)"

<% return gen.pairs(server.run_env_vars or {})
  :map(function (k, v)
    return str.interp("export %1=%2", { k, str.quote(tostring(v)) })
  end):concat("\n") %>

<% template:push(environment == "test") %>
export LUACOV_CONFIG="<% return luacov_config %>"
<% template:pop() %>

<% return gen.ivals(server.run_env_scripts or {}):filter(function (env)
    return not str.isempty(env)
  end):map(function (env)
    return ". " .. env
  end):concat("\n") %>

mkdir -p logs
touch logs/access.log logs/error.log
ln -sf /dev/stdout logs/stdout

if [ "$<% return var('BACKGROUND') %>" = "1" ]; then
  openresty -p "$PWD" -c nginx-daemon.conf
else
  exec openresty -p "$PWD" -c nginx.conf
fi
