local test = require("santoku.test")
local str = require("santoku.string")
local app = require("<% return name %>")

test("<% return name %> client", function()
  print(app.hello())
  str.printf("\n%s: %s\n", app.hello())
end)
