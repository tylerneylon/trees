-- TEMP TODO REMOVE
--
-- This is a temporary file to help test some stuff in Vec3.lua.
--


local Vec3 = require 'Vec3'

local v = Vec3:new(1, 2, 3)

assert(getmetatable(v) == Vec3)

local w = v + 3 * v

print(w[1], w[2], w[3])


