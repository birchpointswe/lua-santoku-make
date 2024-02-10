#!/bin/sh

<%
  str = require("santoku.string")
  it = require("santoku.iter")
  arr = require("santoku.array")
  server = server or {}
%>

set -e

cd "$(dirname $0)"

<% return arr.concat(it.collect(it.map(function (k, v)
  return str.interp("export %1=%2", { k, str.quote(tostring(v)) })
end, it.pairs(server.run_env_vars or {}))), "\n") %>

<% push(environment == "test") %>
export LUACOV_CONFIG="<% return luacov_config %>"
<% pop() %>

<% return arr.concat(it.collect(it.map(function (env)
  return ". " .. env
end, it.filter(function (env)
  return not str.isempty(env)
end, it.ivals(server.run_env_scripts or {})))), "\n") %>

mkdir -p logs
touch logs/access.log logs/error.log
ln -sf /dev/stdout logs/stdout

if [ "$<% return var('BACKGROUND') %>" = "1" ]; then
  openresty -p "$PWD" -c nginx-daemon.conf
else
  exec openresty -p "$PWD" -c nginx.conf
fi
