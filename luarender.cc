//
//  luarender.cc
//  Trees
//

#include "luarender.h"

extern "C" {

// Local includes.
#include "clua.h"
#include "file.h"
#include "lines.h"

// Library includes.
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
  
}


// Internal globals.

static lua_State *L = NULL;


// Internal functions.

static void transform_callback(GLint transform_loc) {
  // TODO HERE
}


// Public functions.

extern "C" void luarender__init() {
  L = clua__new_state();
  
  // Load the standard library.
  luaL_openlibs(L);
  
  // Load the render modules.
  char *filepath = file__get_path("render.lua");
  // stack = []
  luaL_dofile(L, filepath);
  // stack = [render]
  lua_setglobal(L, "render");
  // stack = []
  
  // Load and set up the lines module.
  lines__load_lib(L);
  // stack = []
  lines__set_transform_callback(transform_callback);
  
  // Call render.init.
  clua__call(L, "render", "init", "");  // "" --> no input, no output
}

extern "C" void luarender__draw() {
  clua__call(L, "render", "draw", "");  // "" --> no input or output
}
