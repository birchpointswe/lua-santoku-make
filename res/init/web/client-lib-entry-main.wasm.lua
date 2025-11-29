local app = require("santoku.web.pwa.app")
local db = require("<% return name %>.db")

app.init({
  name = "<% return name %>",
  db = db,
  main = function ()
    -- App initialization code here
  end
})
