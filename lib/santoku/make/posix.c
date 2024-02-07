#include "lua.h"
#include "lauxlib.h"

#include <errno.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

// TODO: Duplicated across various libraries, need to consolidate
void tk_make_callmod (lua_State *L, int nargs, int nret, const char *smod, const char *sfn)
{
  lua_getglobal(L, "require"); // arg req
  lua_pushstring(L, smod); // arg req smod
  lua_call(L, 1, 1); // arg mod
  lua_pushstring(L, sfn); // args mod sfn
  lua_gettable(L, -2); // args mod fn
  lua_remove(L, -2); // args fn
  lua_insert(L, - nargs - 1); // fn args
  lua_call(L, nargs, nret); // results
}

int tk_make_posix_err (lua_State *L, int err)
{
  lua_pushstring(L, strerror(errno));
  lua_pushinteger(L, err);
  tk_make_callmod(L, 2, 0, "santoku.error", "error");
  return 0;
}

int tk_make_posix_time (lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
  struct stat statbuf;
  int rc = stat(path, &statbuf);
  if (rc == -1)
    return tk_make_posix_err(L, errno);
  struct timespec *t = &statbuf.st_mtim;
  lua_pushnumber(L, t->tv_sec);
  return 1;
}

int tk_make_posix_now (lua_State *L)
{
  time_t n = time(NULL);
  if (n == ((time_t) -1))
    return tk_make_posix_err(L, errno);
  lua_pushnumber(L, n);
  return 1;
}

luaL_Reg tk_make_posix_fns[] =
{
  { "time", tk_make_posix_time },
  { "now", tk_make_posix_now },
  { NULL, NULL }
};

int luaopen_santoku_make_posix (lua_State *L)
{
  lua_newtable(L);
  luaL_register(L, NULL, tk_make_posix_fns);
  return 1;
}
