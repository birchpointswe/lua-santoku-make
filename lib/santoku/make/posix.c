#include "lua.h"
#include "lauxlib.h"

#include <errno.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>

int tk_make_posix_err (lua_State *L, int err)
{
  lua_pushboolean(L, 0);
  lua_pushstring(L, strerror(errno));
  lua_pushinteger(L, err);
  return 3;
}

int tk_make_posix_time (lua_State *L)
{
	const char *path = luaL_checkstring(L, 1);
  struct stat statbuf;
  int rc = stat(path, &statbuf);
  if (rc == -1)
    return tk_make_posix_err(L, errno);
  lua_pushboolean(L, 1);
  struct timespec *t = &statbuf.st_mtim;
  lua_pushnumber(L, t->tv_sec);
  return 2;
}

int tk_make_posix_now (lua_State *L)
{
  time_t n = time(NULL);
  if (n == ((time_t) -1))
    return tk_make_posix_err(L, errno);
  lua_pushboolean(L, 1);
  lua_pushnumber(L, n);
  return 2;
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
