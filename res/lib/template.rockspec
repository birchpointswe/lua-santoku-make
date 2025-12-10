<%
  str = require("santoku.string")
  squote = str.quote

  tbl = require("santoku.table")
  get = tbl.get

  arr = require("santoku.array")

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
  <%
    local dep_sources = {
      dependencies or {},
      environment == "test" and get(test or {}, {"dependencies"}) or {},
      environment == "test" and wasm and get(test or {}, {"wasm", "dependencies"}) or {},
      environment == "test" and not wasm and get(test or {}, {"native", "dependencies"}) or {}
    }
    local deps = {}
    for i = 1, #dep_sources do
      local src = dep_sources[i]
      for j = 1, #src do
        deps[#deps + 1] = squote(src[j])
      end
    end
    return arr.concat(deps, ",\n")
  %>
}

external_dependencies = {
  <%
    local ext_sources = {
      get(dependencies or {}, {"external"}) or {},
      environment == "test" and get(test or {}, {"dependencies", "external"}) or {},
      environment == "test" and wasm and get(test or {}, {"wasm", "dependencies", "external"}) or {},
      environment == "test" and not wasm and get(test or {}, {"native", "dependencies", "external"}) or {}
    }
    local ext_deps = {}
    for i = 1, #ext_sources do
      local src = ext_sources[i]
      for j = 1, #src do
        ext_deps[#ext_deps + 1] = serialize_table_contents(src[j])
      end
    end
    return arr.concat(ext_deps, ",\n")
  %>
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
    CC = "$(CC)",
    INST_PREFIX = "$(PREFIX)",
    INST_BINDIR = "$(BINDIR)",
    INST_LIBDIR = "$(LIBDIR)",
    INST_LUADIR = "$(LUADIR)",
    INST_CONFDIR = "$(CONFDIR)",
  }
}
