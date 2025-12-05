<%
  local fs = require("santoku.fs")
  local str = require("santoku.string")
  local serialize = require("santoku.serialize")
  local tpl_dir = fs.join(root_dir, "res/web/templates")
  local tpl = {}
  for path, tp in fs.files(tpl_dir, true) do
    if tp == "file" then
      local key = str.match(path, "^.*/res/web/templates/(.*)%.[^.]+$")
      if key then
        tpl[str.gsub(key, "/", ".")] = readfile(path)
      end
    end
  end
  t_templates = serialize(tpl, true)
%>
local mch = require("santoku.mustache")
local templates = <% return t_templates %>; -- luacheck: ignore
local M = {}
for key, tpl in pairs(templates) do
  M[key] = mch(tpl, { partials = M })
end
return M
