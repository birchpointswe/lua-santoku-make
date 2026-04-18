local env = {
  name = "santoku-make",
  version = "0.0.213-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 0.0.328-1",
    "santoku-fs >= 0.0.45-1",
    "santoku-web >= 0.0.498-1",
    "santoku-system >= 0.0.63-1",
    "santoku-template >= 0.0.38-1",
    "santoku-mustache >= 0.0.16-1",
    "santoku-bundle >= 0.0.45-1",
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env }
