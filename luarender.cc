//
//  luarender.cc
//  Trees
//

#include "luarender.h"

// C-only includes.
extern "C" {

#include "clua.h"
#include "file.h"
#include "lines.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
  
}

// C++ friendly includes.
#include "config.h"

#include "glm.hpp"
#define GLM_FORCE_RADIANS
#include "matrix_transform.hpp"
using namespace glm;



// Internal globals.

static lua_State *L = NULL;

static float aspect_ratio;
static float angle = 0.0f;


// Internal functions.

static void transform_callback(GLint transform_loc) {
  
  // TODO Consider pulling some of this work out in case this function is called
  //      more than once within a single render cycle.
  
  mat4 projection = perspective(45.0f, aspect_ratio, 0.1f, 1000.0f);
  mat4 view  = lookAt(vec3(4.0, 4.0, 2.0), vec3(0.0), vec3(0.0, 1.0, 0.0));
  
  mat4 model = rotate(mat4(1.0), angle, vec3(0.0, 1.0, 0.0));
  model = translate(model, vec3(0, -3, 0));
  model = scale(model, vec3(zoom_scale));
  
  mat4 mvp = projection * view * model;
  
  glUniformMatrix4fv(transform_loc,  // uniform location
                     1,              // count
                     GL_FALSE,       // don't use transpose
                     &mvp[0][0]);    // src matrix

  //mat3 normal_matrix = mat3(view * model);
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

extern "C" void luarender__draw(int w, int h) {
  glViewport(0, 0, w, h);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
  aspect_ratio = (float)w / h;
  angle += 0.01;
  clua__call(L, "render", "draw", "");  // "" --> no input or output
}
