local env = {
  name = "santoku-make",
  version = "0.0.174-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.305-1",
    "santoku-fs >= 0.0.37-1",
    "santoku-system >= 0.0.58-1",
    "santoku-template >= 0.0.32-1",
    "santoku-mustache >= 0.0.13-1",
    "santoku-bundle >= 0.0.37-1",
  },
  rules = {
    copy = {
      "nginx%.tk%.conf$",
    }
  },
}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
