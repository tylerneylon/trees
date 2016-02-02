// triangle_strip.cpp
//
// To generalize:
//  * Remove dependence on bark.*.glsl
//  * Support texturing.
//
// To be honest, it would make more sense to generalize the version in Apanga
// than this one.
//

#include "triangle_strip.h"

extern "C" {
#include "cstructs/cstructs.h"
#include "file.h"
#include "glhelp.h"
#include "lua/lauxlib.h"
}

#include "glm/glm.hpp"
#define GLM_FORCE_RADIANS
#include "glm/gtc/matrix_transform.hpp"
using namespace glm;

#define for_i_3 for(int i = 0; i < 3; ++i)

#define triangle_strip_metatable "Apanga.TriangleStrip"


// Internal types and globals.

// State shared across all TriangleStrip instances.
static GLuint            program;
static GLint             mvp_loc;
static GLint    normal_xform_loc;
static triangle_strip__TransformCallback          mvp_callback = NULL;
static triangle_strip__TransformCallback normal_xform_callback = NULL;

// State owned by any single TriangleStrip instance.
typedef struct {
  GLuint vao;
  GLuint vertices_vbo;
  GLuint normals_vbo;
  int    num_pts;
} TriangleStrip;

// Names for vertex attribute indexes in our vertex shader.
enum {
  v_position,
  color,
  normal
};



// Internal: OpenGL utility code.

// Initialize data that's constant across all instances.
// This function is expected to be called only once.
static void gl_init() {
  program = glhelp__load_program("bark.vert.glsl",
                                 "bark.frag.glsl");

  mvp_loc            = glGetUniformLocation(program, "mvp");
  normal_xform_loc   = glGetUniformLocation(program, "normal_xform");
}

// Note: This functionality overlaps heavily with copy_array_to_gl_buffer in
//       land_draw.c.
static void set_array_as_buffer_data(Array array) {
  glBufferData(GL_ARRAY_BUFFER,                  // buffer use target
               array->count * array->item_size,  // size
               array->items,                     // data
               GL_STATIC_DRAW);                  // usage hint
}

static void gl_setup_new_triangle_strip(TriangleStrip *strip,
                                        Array v_pts) {

  // Compute the normals of each triangle.
  Array n_vecs = array__new(v_pts->count, sizeof(GLfloat));
  float sign = 1;
  array__for(GLfloat *, pt, v_pts, j) {
    if (j % 3) continue;  // Only use pt when it is 3-aligned.
    if (j < 6) {
      // The first two normals can be all-zero.
      for_i_3 array__new_val(n_vecs, GLfloat) = 0.0f;
      continue;
    }

    vec3 pt0 = vec3(pt[-6], pt[-5], pt[-4]);
    vec3 pt1 = vec3(pt[-3], pt[-2], pt[-1]);
    vec3 pt2 = vec3(pt[0],  pt[1],  pt[2]);

    vec3 n = sign * normalize(cross(pt1 - pt0, pt2 - pt1));
    for_i_3 array__new_val(n_vecs, GLfloat) = n[i];

    sign *= -1;
  }

  // Set up and bind the vao.
  glGenVertexArrays(1, &strip->vao);
  glBindVertexArray(strip->vao);

  // Set up the vertex position vbo.
  glGenBuffers(1, &strip->vertices_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, strip->vertices_vbo);
  set_array_as_buffer_data(v_pts);
  glEnableVertexAttribArray(v_position);
  glVertexAttribPointer(v_position,    // attrib index
                        3,             // num coords
                        GL_FLOAT,      // coord type
                        GL_FALSE,      // gpu should normalize
                        0,             // stride
                        (void *)(0));  // offset

  // Set up num_pts.
  strip->num_pts = v_pts->count / 3;

  // Set up the normal vectors vbo.
  glGenBuffers(1, &strip->normals_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, strip->normals_vbo);
  set_array_as_buffer_data(n_vecs);
  glEnableVertexAttribArray(normal);
  glVertexAttribPointer(normal,        // attrib index
                        3,             // num coords
                        GL_FLOAT,      // coord type
                        GL_FALSE,      // gpu should normalize
                        0,             // stride
                        (void *)(0));  // offset

  glhelp__error_check;
}


// Internal: Lua C functions.

// This creates an Array of GLfloats from what is expected to be a Lua array at
// the given index on L's stack. The caller is responsible for calling
// array__delete on the returned Array. L's stack is preserved.
static Array c_array_from_lua_array(lua_State *L, int index) {

  int arr_len = (int)lua_rawlen(L, index);

  Array arr = array__new(arr_len, sizeof(GLfloat));
  for (int i = 1;; lua_pop(L, 1), ++i) {
      // stack = [.. lua_arr ..]
    lua_rawgeti(L, index, i);
      // stack = [.. lua_arr .. lua_arr[i]]
    if (lua_isnil(L, -1)) break;
    array__new_val(arr, GLfloat) = lua_tonumber(L, -1);
  }
      // stack = [.. lua_arr .. nil]
  lua_pop(L, 1);
      // stack = [.. lua_arr ..]
  return arr;
}

static void luaL_checkindexable(lua_State *L, int narg) {
  if (lua_istable(L, narg)) return;  // tables are indexable.
  if (!luaL_getmetafield(L, narg, "__index")) {
    // This function will show the user narg and the Lua-visible function name.
    luaL_argerror(L, narg, "expected an indexable value such as a table");
  }
  lua_pop(L, 1);  // Pop the value of getmetable(narg).__index.
}

// Lua C function.
// Expected parameters: a {points table}.
static int triangle_strip__new(lua_State *L) {
  
  // Expect the 1st value to be table-like.
  luaL_checkindexable(L, 2);
      // stack = [self, v_pts, ..]

  // Collect v_pts.
  Array v_pts = c_array_from_lua_array(L, 2);
  lua_settop(L, 0);
      // stack = []

  // Create a triangle_strip instance and set its metatable.
  TriangleStrip *strip =
      (TriangleStrip *)lua_newuserdata(L, sizeof(TriangleStrip));
      // stack = [strip]
  luaL_getmetatable(L, triangle_strip_metatable);
      // stack = [strip, mt]
  lua_setmetatable(L, 1);
      // stack = [strip]

  // Set up the C data.
  gl_setup_new_triangle_strip(strip, v_pts);

  glhelp__error_check;

  array__delete(v_pts);

  return 1;  // --> 1 Lua return value
}

// Lua C function.
// Expected parameters:
//   self      = a TriangleStrip instance.
//   [opts]    = a table with optional values:
//     offset  = {x, y, z} point.
//     look_at = {x, y, z} point.
static int triangle_strip__draw(lua_State *L) {
  TriangleStrip *strip =
      (TriangleStrip *)luaL_checkudata(L, 1, triangle_strip_metatable);

  int has_offset = 0, has_look_at = 0;
  vec3 offset, look_at;

  // Parse the opts table if it's present.
  if (lua_gettop(L) > 1) {
    // stack = [self, opts]
    const char *opt_names[] = {    "offset",     "look_at"};
    int *has_bits[]         = {&has_offset,  &has_look_at};
    vec3 *vectors[]         = {    &offset,      &look_at};
    for (int i = 0; i < 2; ++i) {
      lua_getfield(L, 2, opt_names[i]);
      // stack = [self, opts, <opt_value or nil>]
      if (lua_isnil(L, 3)) {
        lua_pop(L, 1);
        continue;
      }
      *has_bits[i] = 1;
      // stack = [self, opts, opt_value]
      for (int j = 1; j <= 3; ++j) {
        lua_pushinteger(L, j);
          // stack = [self, opts, opt_value, j]
        lua_gettable(L, 3);
          // stack = [self, opts, opt_value, opt_value[j]]
        (*vectors[i])[j - 1] = lua_tonumber(L, 4);
          // stack = [self, opts, opt_value, opt_value[j]]
        lua_pop(L, 1);
          // stack = [self, opts, opt_value]
      }
      lua_pop(L, 1);
      // stack = [self, opts]
    }
  }

  // Prepare for and execute OpenGL drawing.
  glUseProgram(program);
  glBindVertexArray(strip->vao);
  mvp_callback(mvp_loc);
  normal_xform_callback(normal_xform_loc);
  glDrawArrays(GL_TRIANGLE_STRIP,  // mode
               0,                  // start
               strip->num_pts);    // count

  return 0;  // --> 0 Lua return values
}

// TODO Add and test/debug a gc function.


// Public functions.

#define add_fn(fn, name)        \
    lua_pushcfunction(L, fn);   \
    lua_setfield(L, -2, name);

extern "C" void triangle_strip__load_lib(lua_State *L) {

  // If this metatable already exists, the library is already loaded.
  if (!luaL_newmetatable(L, triangle_strip_metatable)) return;

  // metatable.__index = metatable
  lua_pushvalue(L, -1);            // --> stack = [.., mt, mt]
  lua_setfield(L, -2, "__index");  // --> stack = [.., mt]

  add_fn(triangle_strip__draw, "draw");

  lua_pop(L, 1);  // --> stack = [..]

  // Add `TriangleStrip` as a global module table with a single `new` function.
  static const struct luaL_Reg lib[] = {
    {"new", triangle_strip__new},
    {NULL, NULL}};
  luaL_newlib(L, lib);                // --> stack = [.., TriangleStrip]
  lua_setglobal(L, "TriangleStrip");  // --> stack = [..]

  gl_init();
}

void triangle_strip__set_mvp_callback(triangle_strip__TransformCallback cb) {
  mvp_callback = cb;
}

void triangle_strip__set_normal_callback(triangle_strip__TransformCallback cb) {
  normal_xform_callback = cb;
}
