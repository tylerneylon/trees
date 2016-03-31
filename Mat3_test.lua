--[[ Mat3_test.lua

Tests for Mat3.lua.

--]]

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'


-- Utility functions to help with testing.

local function close(x1, x2)
  local epsilon = 1e-4
  return math.abs(x1 - x2) < epsilon
end

local function vectors_are_close(v1, v2)
  return close(v1[1], v2[1]) and close(v1[2], v2[2]) and close(v1[3], v2[3])
end


-- Test the zero constructor.

local M

M = Mat3:new_zero()
for i = 1, 3 do for j = 1, 3 do
  assert(M[i][j] == 0)
end end


-- Test element lookup based on constructors.

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


-- Test rotate_to_z.

local z

-- Check that the input is not normalized by rotate_to_z.
v = Vec3:new(1, 1, 1)
z = Vec3:new(v)
M = Mat3:rotate_to_z(v)
assert(close(M:det(), 1))
assert(v[1] == z[1] and v[2] == z[2] and v[3] == z[3])

v:normalize()
w = M * v
z = Vec3:new(0, 0, 1)
assert(vectors_are_close(w, z))

v = Vec3:new(1, 0, 0)
w = M * v
assert(close(w:length(), 1))


-- Test rotate.

local y

-- Rotation around z should be counterclockwise rotation in the x, y plane.
M = Mat3:rotate(math.pi / 2, z)
assert(close(M:det(), 1))
v = Vec3:new(1, 0, 0)
w = M * v
y = Vec3:new(0, 1, 0)
assert(vectors_are_close(w, y))

M = Mat3:rotate(math.pi / 4, y)
assert(close(M:det(), 1))
w = M * v  -- v == (1, 0, 0)
local sqrt_half = math.sqrt(0.5)
local u = Vec3:new(sqrt_half, 0, -sqrt_half)
assert(vectors_are_close(w, u))

u = Vec3:new(1, 1, 1)
M = Mat3:rotate(1, u)
assert(close(M:det(), 1))
w = M * v  -- v == (1, 0, 0)
assert(close(u:dot(v), u:dot(w)))


-- Test det.

-- When overflow is not a concern, integer-valued matrices will have an
-- integer-valued determinant without any concern about precision errors as all
-- the values involved can be represented exactly.

M = Mat3:new_with_rows({1, 2, 3},
                       {4, 5, 6},
                       {7, 8, 9})
assert(M:det() == 0)

M = Mat3:new_with_rows({1, 0, 0},
                       {0, 5, 0},
                       {0, 0, 9})
assert(M:det() == 45)

M = Mat3:new_with_rows({ 2,  3,  5},
                       { 0, 11,  7},
                       { 0,  0, 13})
assert(M:det() == 286)


-- Test get_transpose.

M = Mat3:new_with_rows({1, 2, 3},
                       {4, 5, 6},
                       {7, 8, 9})
P = M:get_transpose()
assert(M ~= P)
assert(P[1][1] == 1)
assert(P[2][1] == 2)
assert(P[1][2] == 4)
assert(M[1][2] == 2)  -- Sanity check that M remains unchanged.


-- Test orthogonalize.

-- Choose a nonsingular matrix.
repeat
  M = Mat3:new_random()
until not close(M:det(), 0)
P = M:orthogonalize()

assert(P == M)

for i = 1, 3 do
  v = Vec3:new(M[i])
  assert(close(v:length(), 1))
  for j = i + 1, 3 do
    u = Vec3:new(M[j])
    assert(close(u:dot(v), 0))
  end
end


-- Test frob_dist().

M = Mat3:new_random()
assert(M:frob_dist(M) == 0)

-- 2² + 4² + 4² = 4 + 16 + 16 = 36 = 6²
M = Mat3:new_with_rows({1, 0, 0},
                       {0, 2, 0},
                       {0, 0, 3})
P = Mat3:new_with_rows({3, 0, 0},
                       {0, 6, 0},
                       {0, 4, 3})
assert(M:frob_dist(P) == 6)



-- Test eigen_decomp().

local L

-- Returns a uniform random in the range [-1, 1).
local function rnd()
  return math.random() * 2 - 1
end

-- Choose a nonsingular matrix.
repeat
  M = Mat3:new_random()
until not close(M:det(), 0)
M:orthogonalize()  -- This way it's easy to find the inverse of M.
local lambda_in = {rnd(), rnd(), rnd()}
L = Mat3:new_with_rows({lambda_in[1], 0, 0},
                       {0, lambda_in[2], 0},
                       {0, 0, lambda_in[3]})
P = M * L * M:get_transpose()

local U, lambda_out = P:eigen_decomp()

-- Check that the lambda values approximately match.
table.sort(lambda_in)
table.sort(lambda_out)
for i = 1, 3 do
  assert(close(lambda_in[i], lambda_out[i]))
end

-- Check that the columns match, up to a permutation.
for i = 1, 3 do
  local v = U:col_as_vec(i):normalize()
  local d = 0
  for j = 1, 3 do
    local u = M:col_as_vec(j):normalize()
    d = math.max(d, math.abs(u:dot(v)))
  end
  assert(close(d, 1))
end


print('All tests passed!')
