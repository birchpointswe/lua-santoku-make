<%
  gen = require("santoku.gen")
  fun = require("santoku.fun")
  op = require("santoku.op")
  str = require("santoku.string")
  tbl = require("santoku.table")
%>

package = "<% return name .. "-" .. component .. (environment == "test" and "-test" or "") %>"
version = "<% return version %>"
rockspec_format = "3.0"

source = { url = "" }

dependencies = {
  <% return gen.pack(
        environment ~= "test" and component == "server" and tbl.get(server or {}, "dependencies"),
        environment == "test" and component == "server" and tbl.get(server or {}, "test", "spec_dependencies"))
      :map(fun.bindr(op["or"], {}))
      :map(gen.ivals)
      :flatten()
      :map(str.quote)
      :concat(",\n") %>
}

<% template:push(environment == "run") %>

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

<% template:pop() %>
