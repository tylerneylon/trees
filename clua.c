// clua.c
//

#include "clua.h"

// Local includes.
#include "file.h"

// Library includes.
#include "lauxlib.h"
#include "lualib.h"

// System includes.
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>

#define dbg__printf(...) printf(__VA_ARGS__)


// Internal functions.

void clua__print(const char *s) {
  dbg__printf("%s\n", s);
}

void clua__print_error(lua_State *L) {
  const char *err_str = lua_tostring(L, -1);
  dbg__printf("Lua error: %s\n", err_str);
  lua_pop(L, 1);
}

// Most of this function is from a similar function in the book Programming in
// Lua by Roberto Ierusalimschy, 3rd edition.
// This function does *not* accept clua__L as L.
static void call(lua_State *L, const char *mod, const char *fn,
                 const char *types, va_list args) {
  
  lua_getglobal(L, mod);
  
  if (lua_isnil(L, -1)) {
    dbg__printf("clua__call: module '%s' is nil (not loaded)\n", mod);
    lua_pop(L, 1);
    return;
  }
  
  lua_getfield(L, -1, fn);
  lua_remove(L, -2);
  
  // Parse types of and push input arguments.
  int nargs;
  for (nargs = 0; *types; ++nargs) {
    luaL_checkstack(L, 1, "too many arguments in clua__call");
    switch (*types++) {
      case 'd':  // double
        lua_pushnumber(L, va_arg(args, double));
        break;
        
      case 'i':  // int
        lua_pushinteger(L, va_arg(args, int));
        break;
        
      case 's':  // string
        lua_pushstring(L, va_arg(args, char *));
        break;
        
      case 'b': // boolean
        lua_pushboolean(L, va_arg(args, int));
        break;
        
      case '>':
        goto endargs;
        
      default:
        dbg__printf("clua__call: Unrecognized type character.\n");
    }
  }
  
endargs:;  // Semi-colon here as an empty statement so we can declare nresults.
  
  int nresults = (int)strlen(types);
  int results_left = nresults;
  int error = lua_pcall(L, nargs, nresults, 0);
  if (error) {
    char msg[512];
    snprintf(msg, 512, "Error in call to %s.%s:", mod, fn);
    clua__print(msg);
    clua__print_error(L);
  }
  const char *type_err_fmt =
      "clua__call type error: bad result type - expected type %s\n";
  
  while (*types) {
    switch (*types++) {
      case 'd': {
        if (!lua_isnumber(L, -results_left)) {
          dbg__printf(type_err_fmt, "d");
          goto alldone;
        }
        *va_arg(args, double *) = lua_tonumber(L, -results_left);
        break;
      }
        
      case 'i': {
        if (!lua_isnumber(L, -results_left)) {
          dbg__printf(type_err_fmt, "i");
          goto alldone;
        }
        *va_arg(args, int *) = (int)lua_tointeger(L, -results_left);
        break;
      }
        
      case 'b': {
        if (!lua_isboolean(L, -results_left)) {
          dbg__printf(type_err_fmt, "b");
          goto alldone;
        }
        *va_arg(args, int *) = (int)lua_toboolean(L, -results_left);
        break;
      }
        
      case 's': {
        const char *s = lua_tostring(L, -results_left);
        if (s == NULL) {
          dbg__printf(type_err_fmt, "s");
          goto alldone;
        }
        *va_arg(args, char **) = s ? strdup(s) : NULL;
        break;
      }
        
      default:
        dbg__printf("clua__call: Unrecognized type character.\n");
    }
    results_left--;
  }
  
alldone:;
  lua_pop(L, nresults);
}

static const char *clua__lua_dir() {
  static char lua_dir[512] = "";
  
  if (strlen(lua_dir) > 0) { return lua_dir; }
  
  // The call to file__get_path is mainly for win/mac; it returns NULL on linux.
  const char *land_lua_path = file__get_path("render.lua");
  
  if (land_lua_path == NULL) {
    // If land.lua isn't found, then find the closest existing <prefix>/lua
    // path, where <prefix> is a prefix subpath of the current directory.
    static char cwd[MAXPATHLEN];
    getcwd(cwd, MAXPATHLEN);
    char *last_dir_sep = cwd + strlen(cwd);
    do {
      *last_dir_sep = '\0';
      snprintf(lua_dir, 512, "%s/lua", cwd);
      if (file__exists(lua_dir)) return lua_dir;
      last_dir_sep = strrchr(cwd, '/');
    } while (last_dir_sep);
    // If we get here, there is no clear choice.
    // Our last resort is ./lua, which doesn't exist!
    dbg__printf("Warning: failed to locate an existing lua directory.\n");
    getcwd(cwd, MAXPATHLEN);
    snprintf(lua_dir, 512, "%s/lua", cwd);
  } else {
    // Extract from land_lua_path the directory of our Lua files.
    int dir_len = (int)(strrchr(land_lua_path, file__path_sep) - land_lua_path);
    snprintf(lua_dir, 512, "%.*s", dir_len, land_lua_path);
  }
  
  return lua_dir;
}


// C-public functions.

lua_State *clua__new_state() {
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  
  char new_lua_path[1024];
  snprintf(new_lua_path, 1024, "%s%c?.lua;", clua__lua_dir(), file__path_sep);
  
  lua_getglobal  (L, "package");
  // Stack = [package]
  lua_pushstring (L, new_lua_path);
  // Stack = [package, new_lua_path]
  lua_getfield   (L, -2, "path");
  // Stack = [package, new_lua_path, package.path]
  lua_concat     (L,  2);
  // Stack = [package, joined_lua_paths]
  lua_setfield   (L, -2, "path");
  // Stack = [package]
  lua_pop        (L,  1);
  // Stack = []
  
  return L;
}

// Most of this function is from a similar function in the book Programming in
// Lua by Roberto Ierusalimschy, 3rd edition.
void clua__dump_stack(lua_State *L) {
  int top = lua_gettop(L);
  for (int i = 1; i <= top; ++i) {
    int t = lua_type(L, i);
    switch(t) {
      case LUA_TSTRING:
        {
          dbg__printf("'%s'", lua_tostring(L, i));
          break;
        }
      case LUA_TBOOLEAN:
        {
          dbg__printf(lua_toboolean(L, i) ? "true" : "false");
          break;
        }
      case LUA_TNUMBER:
        {
          dbg__printf("%g", lua_tonumber(L, i));
          break;
        }
      default:
        {
          lua_getglobal(L, "tostring");
          lua_pushvalue(L, i);
          lua_call(L, 1, 1);  // 1 input, 1 output
          dbg__printf("%s", lua_tostring(L, -1));
          lua_pop(L, 1);
          break;
        }
    }
    dbg__printf("  ");  // separator
  }
  dbg__printf("\n");
}

void clua__call(lua_State *L, const char *mod,
                const char *fn, const char *types, ...) {
  va_list args;
  va_start(args, types);
  call(L, mod, fn, types, args);
  va_end(args);
}

// Debugging functions, meant to be called from an interactive C debugger.

void clua__run(lua_State *L, const char *cmd) {  
  // If the cmd has the form "=x", where x is any string, we replace it with
  // "print(x)", which makes it easier to print out values for inspection.
  
  if (cmd[0] != '=') {
    int was_err = luaL_dostring(L, cmd);
    if (was_err) clua__print_error(L);
    return;
  }
  
  size_t len = strlen(cmd) + strlen("clua__print()");
  char *new_cmd = malloc(len);
  snprintf(new_cmd, len, "clua__print(%s)", cmd + 1);
  int was_err = luaL_dostring(L, new_cmd);
  if (was_err) clua__print_error(L);
  free(new_cmd);  
}
