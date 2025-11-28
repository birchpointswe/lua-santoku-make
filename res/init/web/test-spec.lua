local test = require("santoku.test")
local str = require("santoku.string")
local common = require("<% return name %>.common")

test("<% return name %> root", function()
  str.printf("\n%s\n", common.hello())
end)
