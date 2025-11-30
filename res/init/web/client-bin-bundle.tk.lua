local js = require("santoku.web.js")
local global = js.self
local has_registration = global.registration ~= nil
local has_document = global.document ~= nil
if has_registration then
  return require("<% return name %>.sw")
elseif not has_document then
  return require("<% return name %>.db")
else
  return require("<% return name %>.main")
end
