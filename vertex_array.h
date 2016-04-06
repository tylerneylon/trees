// vertex_array.h
//
// A Lua-facing library for easily drawing an array of vertices.
// This uses the bark shader in bark.{vert,frag}.glsl.
//
// Lua interface:
//
//   -- Do this once for the model being drawn.
//   v_array = VertexArray:new({flat sequence of vertex points})
//
//   -- Call this for every frame where you want to draw the model.
//   -- Valid modes: 'triangle strip', 'triangles', 'points', 'lines'.
//   v_array:draw('triangle strip')
//   
//   -- There is an alternative drawing technique that's more efficient if
//   -- you're drawing many vertex arrays, assuming they share the same
//   -- underlying shader and transforms:
//   VertexArray:setup_drawing()
//   for _, v_array in pairs(v_arrays) do
//     v_array:draw_without_setup()
//   end
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include "lua/lua.h"
  
#include <OpenGL/gl3.h>

void vertex_array__load_lib(lua_State *L);
  
// A vertex_array__TransformCallback is a function that accepts the location
// of a shader uniform and sets a mat4 matrix value. That value may be either an
// mvp matrix or a normal tranformation matrix.
typedef void (*vertex_array__TransformCallback)(GLint);

void vertex_array__set_mvp_callback   (vertex_array__TransformCallback cb);
void vertex_array__set_normal_callback(vertex_array__TransformCallback cb);


#ifdef __cplusplus
}
#endif

