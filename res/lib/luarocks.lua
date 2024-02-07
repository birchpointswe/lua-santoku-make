rocks_trees = {
  { name = "system",
    root = "<% return lua_modules %>"
  } }

<% push(wasm) %>

-- NOTE: Not specifying the interpreter, version, LUA, LUA_BINDIR, and LUA_DIR
-- so that the host lua is used install rocks. The other variables affect how
-- those rocks are built

-- lua_interpreter = "lua"
-- lua_version = "5.1"

variables = {

  LUALIB = "liblua.a",
  LUA_INCDIR = "<% return client_lua_dir %>/include",
  LUA_LIBDIR = "<% return client_lua_dir %>/lib",
  LUA_LIBDIR_FILE = "liblua.a",

  CFLAGS = "-I <% return client_lua_dir %>/include",
  LDFLAGS = "-L <% return client_lua_dir %>/lib",
  LIBFLAG = "-shared",

  CC = "emcc",
  CXX = "em++",
  AR = "emar",
  LD = "emcc",
  NM = "llvm-nm",
  LDSHARED = "emcc",
  RANLIB = "emranlib",

}

<% pop() %>
