<%
  it = require("santoku.iter")
  str = require("santoku.string")
  tbl = require("santoku.table")
  arr = require("santoku.array")
%>

package = "<% return name .. "-" .. component .. (environment == "test" and "-test" or "") %>"
version = "<% return version %>"
rockspec_format = "3.0"

source = { url = "" }

dependencies = {
  <% return arr.concat(it.collect(it.map(str.quote, it.flatten(it.map(it.ivals, it.ivals({
      environment ~= "test" and component == "server" and tbl.get(test or {}, "dependencies") or {},
    }))))), ",\n") %>
}

<% push(environment == "run") %>

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

<% pop() %>
