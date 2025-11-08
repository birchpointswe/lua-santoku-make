local test = require("santoku.test")
local <% return name:gsub("-", "_") %> = require("<% return name %>")

test("<% return name %>", function()

  test("should work", function()
    assert(<% return name:gsub("-", "_") %>.hello() == "Hello from <% return name %>!")
  end)

end)
