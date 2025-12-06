<%
  local fs = require("santoku.fs")
  local serialize = require("santoku.serialize")
  local loader = fs.runfile(fs.join(root_dir, "res/web/template-loader.lua"))
  t_templates = serialize(loader(readfile, root_dir), true)
%>
local mch = require("santoku.mustache")
local templates = <% return t_templates %>; -- luacheck: ignore
local M = {}
for key, tpl in pairs(templates) do
  M[key] = mch(tpl, { partials = M })
end
return M
