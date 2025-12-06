return function(readfile, root_dir)
  local fs = require("santoku.fs")
  local str = require("santoku.string")
  local tpl_dir = fs.join(root_dir, "res/web/templates")
  local tpl = {}
  for path, tp in fs.files(tpl_dir, true) do
    if tp == "file" then
      local key = str.match(path, "^.*/res/web/templates/(.*)%.[^.]+$")
      if key then
        tpl[str.gsub(key, "/", ".")] = readfile(path)
      end
    end
  end
  return tpl
end
