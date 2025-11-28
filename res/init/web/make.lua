local fs = require("santoku.fs")
local tbl = require("santoku.table")

return tbl.merge(
  fs.runfile("make.common.lua"), {
  env = {
    client = {
      ldflags = {
        "-sWASM_BIGINT",
        "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
        "--bind",
        "-O0",
        "-g",
        "-sASSERTIONS=2",
      },
      rules = {
        ["sw$"] = {
          ldflags = {
            "--pre-js", "res/pre.js",
            "-sWASM_BIGINT",
            "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE='$stringToNewUTF8'",
            "--bind",
            "-O0",
            "-g",
            "-sASSERTIONS=2",
          },
        },
      },
    }
  }
})
