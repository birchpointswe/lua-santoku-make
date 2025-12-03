local mch = require("santoku.mustache")
local templates = <%
  local serialize = require("santoku.serialize")
  local fs = require("santoku.fs")
  local str = require("santoku.string")
  local tpl = {}
  local tpl_dir = fs.join(root_dir, "res/web/templates")
  for path, tp in fs.files(tpl_dir, true) do
    if tp == "file" then
      local key = str.match(path, "^.*/res/web/templates/(.*).html$")
      if key then
        tpl[key] = readfile(path)
      end
    end
  end
  return serialize(tpl, true)
%>; -- luacheck: ignore
local M = {}
for key, tpl in pairs(templates) do
  M[key] = mch(tpl, { partials = M })
end
return M
