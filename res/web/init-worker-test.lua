<%
  fs = require("santoku.fs")
  compat = require("santoku.compat")
  str = require("santoku.string")
%>

<% template:push(not skip_coverage) %>
require("luacov")
<% template:pop():push(profile) %>
require("santoku.profile")
<% template:pop() %>

local fs = require("santoku.fs")
local err = require("santoku.err")

<% template:push(server.init_worker) %>
local init_file = <% if template:showing() then
  local path = check:exists(compat.searchpath(server.init_worker, fs.join(dist_dir, "lua_modules/share/lua/5.1/?.lua")))
  return str.quote(str.stripprefix(path, dist_dir .. "/"))
end %>
err.check(fs.loadfile(init_file))()
<% template:pop() %>
