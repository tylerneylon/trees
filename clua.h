// clua.h
//
// A module to help integrate C and embedded Lua.
//
// This is a vastly simplified version of the Apanga module of the same name.
//

#pragma once

#include "lua.h"

// C-public functions.

void        clua__call(lua_State *L, const char *mod,
                       const char *fn, const char *types, ...);
void        clua__run          (lua_State *L, const char *cmd);
void        clua__dump_stack(lua_State *L);
