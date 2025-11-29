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
        "-flto",
        "-Oz",
        "-sASSERTIONS=0",
        "-sEVAL_CTORS",
        "-sMALLOC=emmalloc",
        "-sENVIRONMENT=web,worker",
        "-sTEXTDECODER=2",
        "-sABORT_ON_WASM_EXCEPTIONS=0",
        "-sNO_EXIT_RUNTIME",
      },
    }
  }
})
