// lines.c
//
// https://github.com/tylerneylon/apanga-mac
//

#include "lines.h"

// Local includes.
#include "cstructs/cstructs.h"
#include "glhelp.h"

// Library includes.
#include "lua/lauxlib.h"

// OpenGL and standard library includes.
#include <assert.h>
#include <OpenGL/gl3.h>


// Macros.

#define for_i_3 for (int i = 0; i < 3; ++i)



// Internal types and globals.

static GLuint  program;
static GLint    vp_loc;
static GLint color_loc;

static lines__TransformCallback transform_callback = NULL;

static float line_scale = 1.0;

static Array lines = NULL;

// Our code maintains two drawing states: empty or ready. Empty means that we
// have no vao or vbo set up, and the vao value is 0. Ready means that both the
// vao and vbo have data ready to draw, and the vao is nonzero.
static GLuint vao  = 0;
static GLuint vbo  = 0;

// Names for vertex attribute indexes in our vertex shader.
enum {
  v_position,
};


// Internal: OpenGL utility code.

static void gl_init() {
  program = glhelp__load_program("solid.vert.glsl",
                                 "solid.frag.glsl");
  vp_loc    = glGetUniformLocation(program, "vp");
  color_loc = glGetUniformLocation(program, "color");

  // Set the line color to green.
  GLfloat color[4] = { 0.0, 1.0, 0.0, 1.0 };
  glUniform4fv(color_loc,  // location
               1,          // count
               color);     // uniform value
}


// Lua helper functions.

// This verifies that the narg argument on the stack is a table with three
// values, and converts those values to GLfloats in pt. If the types don't match
// up, this throws a Lua error. This expects narg > 0.
static int luaL_checkpoint(lua_State *L, int narg, GLfloat *pt) {
  assert(pt);
  if (lua_gettop(L) < narg) goto error;

  for (int i = 0; i < 3; ++i) {
    lua_pushinteger(L, i + 1);
        // stack = [.., i + 1]
    lua_gettable(L, narg);
        // stack = [.., narg[i + 1]]
    if (lua_isnil(L, -1)) goto error;
    pt[i] = lua_tonumber(L, -1);
        // stack = [.., narg[i + 1]]
    lua_pop(L, 1);
        // stack = [..]
  }
  return 0;  // This indicates success.

error:
  return luaL_argerror(L, narg, "expected an {x, y, z} point");
}

static void init_if_needed() {
  static int is_initialized = 0;
  if (is_initialized) return;
  is_initialized = 1;

  // Each item is technically a GLfloat, but we work with them in triples of
  // (x, y, z) coordinates.
  lines = array__new(32, sizeof(GLfloat));
}

static void ensure_gl_data_is_empty() {
  if (vao == 0) return;  // Stop if it's already empty.

  glDeleteVertexArrays(1, &vao);
  glDeleteBuffers(1, &vbo);

  vao = 0;
  vbo = 0;
}


static void ensure_gl_data_is_ready() {
  if (vao != 0) {
    glBindVertexArray(vao);
    return;  // Stop early if the vao already exists.
  }

  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);

  // Set up the data in the vbo.

  glBufferData(GL_ARRAY_BUFFER,                  // buffer use target
               lines->count * lines->item_size,  // size
               lines->items,                     // data
               GL_STATIC_DRAW);                  // usage hint
  glVertexAttribPointer(v_position,    // attrib index
                        3,             // num coords
                        GL_FLOAT,      // coord type
                        GL_FALSE,      // gpu should normalize
                        0,             // stride
                        (void *)(0));  // offset
  glEnableVertexAttribArray(v_position);
}


// Lua-facing functions.

// This expects two table arguments: from, and to.
// They each have the format {x, y, z}.
static int lines__add(lua_State *L) {
  init_if_needed();
  ensure_gl_data_is_empty();  // The data is made ready when draw is called.
  
  // Extract C-friendly points from the given Lua tables.
  GLfloat from[3];
  luaL_checkpoint(L, 1, from);
  GLfloat to[3];
  luaL_checkpoint(L, 2, to);

  // All these lines are being aggregated in the `lines` array, and will be
  // converted to an OpenGL vertex buffer object (vbo) on the next call to
  // lines__draw_all.
  
  // If line_scale is not 1, apply it to the line.
  if (line_scale != 1.0) {
    GLfloat mid[3];
    float s = line_scale;
    for_i_3 mid[i] = 0.5 * from[i] + 0.5 * to[i];
    for_i_3 from[i] = s * from[i] + (1 - s) * mid[i];
    for_i_3   to[i] = s *   to[i] + (1 - s) * mid[i];
  }

  for_i_3 array__new_val(lines, GLfloat) = from[i];
  for_i_3 array__new_val(lines, GLfloat) = to[i];

  return 0;  // 0 --> no Lua return values
}

static int lines__set_scale(lua_State *L) {
  line_scale = luaL_checknumber(L, 1);
  return 0;  // 0 --> no Lua return values
}

static int lines__reset(lua_State *L) {

  init_if_needed();

  ensure_gl_data_is_empty();
  array__clear(lines);

  return 0;  // 0 --> no Lua return values
}

static int lines__draw_all(lua_State *L) {
  init_if_needed();

  // Make sure our program, vao, and vbo are set up and bound in OpenGL.
  glUseProgram(program);
  ensure_gl_data_is_ready();

  // Set up the uniforms. The color has been set in gl_init().
  
  assert(transform_callback);
  transform_callback(vp_loc);
  
  // Draw the lines.
  glDrawArrays(GL_LINES,           // mode
               0,                  // start
               lines->count / 3);  // count

  return 0;  // 0 --> no Lua return values
}


// Public functions.

// This expects the GL lock to be held when it's called.
void lines__load_lib(lua_State *L) {
  // Add `lines` as a global module table with a single `draw` function.
  static const struct luaL_Reg lib[] = {
      {"add",       lines__add},
      {"draw_all",  lines__draw_all},
      {"reset",     lines__reset},
      {"set_scale", lines__set_scale},
      {NULL, NULL}};
  luaL_newlib(L, lib);        // --> stack = [.., lines]
  lua_setglobal(L, "lines");  // --> stack = [..]

  gl_init();
}

void lines__set_transform_callback(lines__TransformCallback callback) {
  transform_callback = callback;
}
