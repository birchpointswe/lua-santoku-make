rocks_trees = {
  { name = "system",
    root = "<% return lua_modules %>"
  } }

lua_version = "5.1"
rocks_provided = { lua = "5.1" }

<% push(is_wasm) %>

variables = {

  LUALIB = "liblua.a",
  LUA_INCDIR = "<% return client_lua_dir %>/include",
  LUA_LIBDIR = "<% return client_lua_dir %>/lib",
  LUA_LIBDIR_FILE = "liblua.a",

  CFLAGS = "-I <% return client_lua_dir %>/include",
  LDFLAGS = "-L <% return client_lua_dir %>/lib",
  LIBFLAG = "-shared -Wno-linkflags",

  CC = "emcc",
  CXX = "em++",
  AR = "emar",
  LD = "emcc",
  NM = "llvm-nm",
  LDSHARED = "emcc",
  RANLIB = "emranlib",

}

<% pop() %>
