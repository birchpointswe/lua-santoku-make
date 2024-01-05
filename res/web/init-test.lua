require("luacov")
require("luacov.tick")

local fs = require("santoku.fs")
local err = require("santoku.err")

<% template:push(server.init) %>
err.check(fs.loadfile("scripts/<% return server.init %>"))()
<% template:pop() %>
