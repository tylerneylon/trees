// triangle_strip.h
//
// A Lua-facing library for easily drawing a box.
//
// TODO Update these comments.
//
// Lua interface:
//
//   -- v_pts is a flat array of 3d vertex positions.
//   -- t_pts is a flat array of 2d texture positions in pixel coords.
//   strip = TriangleStrip.new({points     = <v_pts>,
//                              tex_coords = <t_pts>,
//                              image      = <image_filename>})
//   strip:set_texture('my_image.png')
//
//   strip:draw()
//   

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "lua/lua.h"
  
#include <OpenGL/gl3.h>

void triangle_strip__load_lib(lua_State *L);
  
// A triangle_strip__TransformCallback is a function that accepts the location
// of a shader uniform and sets a mat4 matrix value. That value may be either an
// mvp matrix or a normal tranformation matrix.
typedef void (*triangle_strip__TransformCallback)(GLint);

// TODO Are these needed?
void triangle_strip__set_mvp_callback   (triangle_strip__TransformCallback cb);
void triangle_strip__set_normal_callback(triangle_strip__TransformCallback cb);


#ifdef __cplusplus
}
#endif

