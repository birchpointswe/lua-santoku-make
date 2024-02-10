<%
  str = require("santoku.string")
  squote = str.quote

  tbl = require("santoku.table")
  get = tbl.get

  arr = require("santoku.array")
  concat = arr.concat

  iter = require("santoku.iter")
  map = iter.map
  flatten = iter.flatten
  ivals = iter.ivals
  collect = iter.collect

  serialize = require("santoku.serialize")
  serialize_table_contents = serialize.serialize_table_contents
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
  <% return concat(collect(map(squote, flatten(map(ivals, ivals({
      dependencies or {},
      environment == "test" and get(test or {}, "dependencies") or {},
      environment == "test" and wasm and get(test or {}, "wasm", "dependencies") or {},
      environment == "test" and not wasm and get(test or {}, "native", "dependencies") or {}
    }))))), ",\n") %>
}

external_dependencies = {
  <% return concat(collect(map(serialize_table_contents, flatten(map(ivals, ivals({
      get(dependencies or {}, "external") or {},
      environment == "test" and get(test or {}, "dependencies", "external") or {},
      environment == "test" and wasm and get(test or {}, "wasm", "dependencies", "external") or {},
      environment == "test" and not wasm and get(test or {}, "native", "dependencies", "external") or {}
    }))))), ",\n") %>
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
