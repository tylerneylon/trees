--[[ Mat3_test.lua

Tests for Mat3.lua.

--]]

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'


-- Test element lookup based on constructors.

local M

M = Mat3:new_with_cols({1, 4, 7},
                       {2, 5, 8},
                       {3, 6, 9})
assert(M[1][1] == 1)
assert(M[2][1] == 4)
assert(M[1][2] == 2)
assert(#M == 3)
assert(#M[1] == 3)

M = Mat3:new_with_rows({1, 2, 3},
                       {4, 5, 6},
                       {7, 8, 9})
assert(M[1][1] == 1)
assert(M[2][1] == 4)
assert(M[1][2] == 2)
assert(#M == 3)
assert(#M[1] == 3)


-- Test matrix * vector multiplication.

local v, w

v = Vec3:new(1, 0, 0)
w = M * v

assert(getmetatable(w) == Vec3)
assert(#w == 3)
assert(w[1] == 1 and w[2] == 4 and w[3] == 7)

v = Vec3:new(1, -1, 1)
w = M * v
assert(w[1] == 2 and w[2] == 5 and w[3] == 8)


-- Test matrix * matrix multiplication.

local N, P

N = Mat3:new_with_rows({1, 0, 0},
                       {0, 1, 0},
                       {0, 0, 1})
P = M * N

assert(getmetatable(P) == Mat3)
assert(#P == 3 and #P[1] == 3)
assert(P[1][1] == 1)
assert(P[2][1] == 4)
assert(P[1][2] == 2)


-- Test get_transpose.

P = M:get_transpose()

assert(getmetatable(P) == Mat3)
assert(#P == 3 and #P[1] == 3)
assert(P[1][1] == 1)
assert(P[2][1] == 2)
assert(P[1][2] == 4)

-- TODO NEXT
-- Test rotate_to_z and rotate.


print('All tests passed!')
