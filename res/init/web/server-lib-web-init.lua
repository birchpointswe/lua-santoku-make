local env = require("santoku.env")
local db_file = env.var("DB_FILE") or "<% return name %>.db"
package.loaded["<% return name %>.db.loaded"] = require("<% return name %>.db")(db_file)
