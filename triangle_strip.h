// triangle_strip.h
//
// A Lua-facing library for easily drawing a triangle strip.
// This uses the bark shader in bark.{vert,frag}.glsl.
//
// Lua interface:
//
//   -- Do this once for the model being drawn.
//   strip = TriangleStrip:new({flat sequence of vertex points})
//
//   -- Call this for every frame where you want to draw the model.
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

