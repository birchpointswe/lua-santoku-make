local err = require("santoku.error")
local str = require("santoku.string")
local vdt = require("santoku.validate")

local function incdir (name)
  err.assert(vdt.isstring(name), "rock name must be a string")
  err.assert(str.match(name, "^[%w][%w%.%-_]*$"), "invalid rock name", name)
  return str.format("$(call TK_ROCK_INCDIR,%s)", name)
end

local function include (name)
  return "-I" .. incdir(name)
end

return {
  incdir = incdir,
  include = include,
}
