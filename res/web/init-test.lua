<%
  fs = require("santoku.fs")
  str = require("santoku.string")
  senv = require("santoku.env")
  err = require("santoku.error")
  init = server.init
%>

<% push(init) %>
local fs = require("santoku.fs")
local init_file = <% if showing() then
  local path = err.checknil(senv.searchpath(init, fs.join(dist_dir, "lua_modules/share/lua/5.1/?.lua")))
  return str.quote(str.stripprefix(path, dist_dir .. "/"))
end %>
fs.runfile(init_file)
<% pop() %>
