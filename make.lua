local env = {
  name = "santoku-make",
  version = "1.0.0-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 1.0.0, < 2.0.0",
    "santoku-fs >= 1.0.0, < 2.0.0",
    "santoku-web >= 1.0.0, < 2.0.0",
    "santoku-system >= 1.0.0, < 2.0.0",
    "santoku-template >= 1.0.0, < 2.0.0",
    "santoku-mustache >= 1.0.0, < 2.0.0",
    "santoku-bundle >= 1.0.0, < 2.0.0",
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
