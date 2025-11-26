local js = require("santoku.web.js")
local document = js.document

local root = document:getElementById("root")
if root then
  root.innerHTML = "<h1>Hello from <% return name %>!</h1>"
end
