local js = require("santoku.web.js")
local global = js.self

local has_registration = global.registration ~= nil
local has_document = global.document ~= nil

if has_registration then
  require("<% return name %>.sw")
else
  require("<% return name %>.entry.main")
end
