// lines.h
//
// https://github.com/tylerneylon/apanga-mac
//
// A Lua-facing library for easily drawing lines.
// The interface is split up to allow for a moderately efficient separation of
// data updating and drawing; often a data update is slower than a draw call, so
// it's nice if updates happen less than every frame.
//
// The current version of this library is not super-powerful, and is set up for
// limited debug-oriented use.
//
// Lua interface:
//
//   function init()
//     lines.set_scale(0.7)  -- Each line is scaled around its center.
//   end
//
//   function data_update()  -- Expected to be called < every frame.
//     lines.reset()
//     -- from and to are tables with {x, y, z} data.
//     lines.add(from, to)  -- Do this as many times as you like.
//   end
//
//   function draw()  -- Expected to be called every frame.
//     lines.draw_all()
//   end
//

#pragma once

#include "lua/lua.h"

void lines__load_lib(lua_State *L);
