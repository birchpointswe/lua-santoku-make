#!/bin/sh

<%
  str = require("santoku.string")
  arr = require("santoku.array")
%>

set -e

cd "$(dirname $0)"

<%
  local env_lines = {}
  for k, v in pairs(run_env_vars or {}) do
    env_lines[#env_lines + 1] = str.interp("export %1=%2", { k, str.quote(tostring(v)) })
  end
  return arr.concat(env_lines, "\n")
%>

<%
  local script_lines = {}
  local scripts = run_env_scripts or {}
  for i = 1, #scripts do
    if not str.isempty(scripts[i]) then
      script_lines[#script_lines + 1] = ". " .. scripts[i]
    end
  end
  return arr.concat(script_lines, "\n")
%>

mkdir -p logs
touch logs/access.log logs/error.log

if [ "$1" = "--fg" ]; then
  exec openresty -p "$PWD" -c nginx-fg.conf
else
  exec openresty -p "$PWD" -c nginx.conf
fi
