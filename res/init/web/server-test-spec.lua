local test = require("santoku.test")
local str = require("santoku.string")
local app = require("<% return name %>")

test("<% return name %> server", function()
  str.printf("\n%s: %s\n", app.hello())
end)
