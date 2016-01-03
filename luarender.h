//
//  luarender.h
//  Trees
//
// This module is used by BNLOpenGLView when Lua is on.
//
// This is a separate module so that this one can be C++ while BNLOpenGLView is
// Objective-C, and we don't need to mix the two in a single file.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void luarender__init();
void luarender__draw();

#ifdef __cplusplus
}
#endif