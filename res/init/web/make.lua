return {
  type = "web",
  env = {
    name = "<% return name %>",
    version = "0.0.1-1",

    dependencies = {
      "lua >= 5.1",
      "santoku >= 0.0.297-1",
    },

    server = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
      },
      domain = "localhost",
      port = "8080",
      workers = "auto",
      ssl = false,
      init = "<% return name %>.init",
      routes = {}
    },

    client = {
      dependencies = {
        "lua == 5.1",
        "santoku >= 0.0.297-1",
        "santoku-web >= 0.0.253-1"
      },
      ldflags = {
        "-sWASM_BIGINT",
        "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "--bind"
      }
    }
  }
}
