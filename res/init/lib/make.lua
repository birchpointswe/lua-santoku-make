local env = {
  name = "<% return name %>",
  version = "0.0.1-1",
  license = "MIT",
  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.294-1",
  },
}

return {
  env = env,
}
