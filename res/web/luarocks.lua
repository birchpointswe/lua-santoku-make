<% push(component == "server") %>

lua_interpreter = "luajit"
lua_version = "5.1"

rocks_trees = {
  { name = "system",
    root = "<% return lua_modules %>"
  } }

variables = {

  LUA = "<% return openresty_dir %>/luajit/bin/luajit",
  LUALIB = "libluajit-5.1.so",
  LUA_BINDIR = "<% return openresty_dir %>/luajit/bin",
  LUA_DIR = "<% return openresty_dir %>/luajit",
  LUA_INCDIR = "<% return openresty_dir %>/luajit/include/luajit-2.1",
  LUA_LIBDIR = "<% return openresty_dir %>/luajit/lib",

}

<% pop() push(component == "client") %>

lua_interpreter = "lua"
lua_version = "5.1"

rocks_trees = {
  { name = "system",
    root = "<% return lua_modules %>"
  } }

variables = {

  LUA = "node <% return client_lua_dir %>/bin/lua",
  LUALIB = "liblua.a",
  LUA_BINDIR = "<% return client_lua_dir %>/bin",
  LUA_DIR = "<% return client_lua_dir %>",
  LUA_INCDIR = "<% return client_lua_dir %>/include",
  LUA_LIBDIR = "<% return client_lua_dir %>/lib",

  CC = "emcc",
  CXX = "em++",
  AR = "emar",
  LD = "emcc",
  NM = "llvm-nm",
  LDSHARED = "emcc",
  RANLIB = "emranlib",

}

<% pop() %>
