local env = {
  name = "santoku-make",
  version = "0.0.190-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.314-1",
    "santoku-fs >= 0.0.42-1",
    "santoku-system >= 0.0.61-1",
    "santoku-template >= 0.0.33-1",
    "santoku-mustache >= 0.0.14-1",
    "santoku-bundle >= 0.0.40-1",
  },
}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
