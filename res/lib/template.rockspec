<%
  gen = require("santoku.gen")
  fun = require("santoku.fun")
  op = require("santoku.op")
  str = require("santoku.string")
  tbl = require("santoku.table")
  serialize = require("santoku.serialize")
%>

package = "<% return name %>"
version = "<% return version %>"
rockspec_format = "3.0"

source = {
  url = "<% return download %>",
}

description = {
  homepage = "<% return homepage %>",
  license = "<% return license or 'UNLICENSED' %>"
}

dependencies = {
  <% return gen.pack(
        dependencies,
        environment == "test" and tbl.get(test or {}, "dependencies"),
        environment == "test" and wasm and tbl.get(test or {}, "wasm", "dependencies"),
        environment == "test" and not wasm and tbl.get(test or {}, "native", "dependencies"))
      :map(fun.bindr(op["or"], {}))
      :map(gen.ivals)
      :flatten()
      :map(str.quote)
      :concat(",\n") %>
}

external_dependencies = {
  <% return gen.pack(
        tbl.get(dependencies, "external"),
        environment == "test" and tbl.get(test, "dependencies", "external"),
        environment == "test" and wasm and tbl.get(test or {}, "wasm", "dependencies", "external"),
        environment == "test" and not wasm and tbl.get(test or {}, "native", "dependencies", "external"))
      :map(fun.bindr(op["or"], {}))
      :map(serialize.serialize_table_contents)
      :filter(fun.compose(op["not"], str.isempty))
      :concat(",\n") %>
}

build = {
  type = "make",
  makefile = "Makefile",
  variables = {
    LIB_EXTENSION = "$(LIB_EXTENSION)",
  },
  build_variables = {
    CC = "$(CC)",
    CXX = "$(CXX)",
    AR = "$(AR)",
    LD = "$(LD)",
    NM = "$(NM)",
    LDSHARED = "$(LDSHARED)",
    RANLIB = "$(RANLIB)",
    CFLAGS = "$(CFLAGS)",
    LIBFLAG = "$(LIBFLAG)",
    LUA_BINDIR = "$(LUA_BINDIR)",
    LUA_INCDIR = "$(LUA_INCDIR)",
    LUA_LIBDIR = "$(LUA_LIBDIR)",
    LUA_LIBDIR = "$(LUA_LIBDIR)",
    LUA = "$(LUA)",
  },
  install_variables = {
    INST_PREFIX = "$(PREFIX)",
    INST_BINDIR = "$(BINDIR)",
    INST_LIBDIR = "$(LIBDIR)",
    INST_LUADIR = "$(LUADIR)",
    INST_CONFDIR = "$(CONFDIR)",
  }
}
