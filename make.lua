local env = {

  name = "santoku-make",
  version = "0.0.105-1",
  variable_prefix = "TK_MAKE",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.239-1",
    "santoku-fs >= 0.0.32-1",
    "santoku-system >= 0.0.33-1",
    "santoku-template >= 0.0.26-1",
    "santoku-bundle >= 0.0.30-1",
  },

  test = {
    dependencies = {
      "luacov >= 0.15.0-1",
    },
  }

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}
