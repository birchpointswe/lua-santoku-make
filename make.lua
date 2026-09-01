local env = {
  name = "santoku-make",
  version = "5.0.11-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 2.0.0, < 3.0.0",
    "santoku-fs >= 2.1.0, < 3.0.0",
    "santoku-web >= 2.0.0, < 3.0.0",
    "santoku-system >= 2.0.0, < 3.0.0",
    "santoku-template >= 2.0.0, < 3.0.0",
    "santoku-mustache >= 2.0.0, < 3.0.0",
    "santoku-bundle >= 2.0.0, < 3.0.0",
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
