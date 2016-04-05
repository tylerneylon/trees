--[[ Mat3.lua

A class for 3x3 matrices that may be multiplied by Vec3s.

--]]

local Mat3 = {}


-- Requires.

local Vec3 = require 'Vec3'


-- Internal functions.

local function pr(...)
  print(string.format(...))
end

local function new_Mat3()
  local m = {{}, {}, {}}
  Mat3.__index = Mat3
  return setmetatable(m, Mat3)
end


-- Public functions.

function Mat3:new_with_cols(c1, c2, c3)
  -- Store the entries by rows internally.
  local m = new_Mat3()
  local cols = {c1, c2, c3}
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = cols[j][i]
  end end
  return m
end

function Mat3:new_with_rows(r1, r2, r3)
  -- Store the entries by rows internally.
  local m = new_Mat3()
  local rows = {r1, r2, r3}
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = rows[i][j]  -- Copy so edits to r_i don't affect the new matrix.
  end end
  return m
end

function Mat3:new_zero()
  local m = new_Mat3()
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = 0
  end end
  return m
end

-- This returns a newly created Mat3 with uniformly random entries in [0, 1).
function Mat3:new_random()
  -- Store the entries by rows internally.
  local m = {{}, {}, {}}
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = math.random()  -- This is a uniform random value in [0, 1).
  end end
  self.__index = self
  return setmetatable(m, self)
end

function Mat3:det()
  return 0
         + self[1][1] * self[2][2] * self[3][3]
         + self[1][2] * self[2][3] * self[3][1]
         + self[1][3] * self[2][1] * self[3][2]
         - self[1][1] * self[2][3] * self[3][2]
         - self[1][2] * self[2][1] * self[3][3]
         - self[1][3] * self[2][2] * self[3][1]
end

function Mat3:print()
  for i = 1, 3 do
    pr('[ %7.3g %7.3g %7.3g ]', self[i][1], self[i][2], self[i][3])
  end
end

function Mat3:__mul(m)
  if getmetatable(self) ~= Mat3 then
    -- Error level 2 indicates this is the caller's fault.
    error('Expected arg to be a Mat3', 2)
  end
  local m_mt = getmetatable(m)
  if m_mt ~= Vec3 and m_mt ~= Mat3 then
    -- Error level 2 indicates this is the caller's fault.
    error('A Mat3 must multiply with a Vec3 or Mat3', 2)
  end

  -- Internally, this is always matrix multiplication.
  -- When m is a Vec3, we convert it to a matrix and then convert the output to
  -- a vector afterwards.

  -- Convert input to a matrix if needed.
  if m_mt == Vec3 then
    m = {{m[1]}, {m[2]}, {m[3]}}
  end

  -- Perform the multiplication.
  local num_cols = #m[1]
  local out = {{}, {}, {}}
  for i = 1, 3 do for j = 1, num_cols do
    out[i][j] = 0
    for k = 1, 3 do
      out[i][j] = out[i][j] + self[i][k] * m[k][j]
    end
  end end

  -- Convert output to a vector if needed.
  if m_mt == Vec3 then
    for i = 1, 3 do
      out[i] = out[i][1]
    end
  end

  -- The output has the same type as the input.
  return setmetatable(out, m_mt)
end

-- The return value of this is a unitary matrix M such that M * dir = (0, 0, 1).
function Mat3:rotate_to_z(dir)
  assert(getmetatable(dir) == Vec3, 'dir expected to be a Vec3')
  local v3 = Vec3:new(dir):normalize()

  -- Find vectors v1 and v2 so that {v1, v2, v3} are orthonormal and satisfy the
  -- right-hand rule. In other words, the matrix {v1, v2, v3} has determinant 1.

  local away_from_v3
  if math.abs(v3[1]) > math.abs(v3[2]) then
    away_from_v3 = Vec3:new(0, 1, 0)
  else
    away_from_v3 = Vec3:new(1, 0, 0)
  end
  local v1 = v3:cross(away_from_v3):normalize()  -- v1 is orthonormal with v3.
  local v2 = v3:cross(v1)                        -- v1, v2, v3 are orthonormal.

  return Mat3:new_with_rows(v1, v2, v3)
end

function Mat3:get_transpose()
  return Mat3:new_with_cols(self[1], self[2], self[3])
end

-- Mat3:rotate(angle, dir) gives a matrix that rotates inputs by `angle` radians
-- around vector dir. This rotates things counterclockwise when the viewer is
-- looking straight down dir; that is, in the opposite direction of dir.
function Mat3:rotate(angle, dir)
  assert(angle == angle)  -- Check for nan.
  if dir:has_nan() then
    -- Error level 2 indicates this is the caller's fault.
    error('dir vector has a nan value', 2)
  end
  assert(not dir:has_nan())
  -- Plan: move dir to z; rotate around z, move z back to dir by inverse.

  -- 1. Move dir to z.
  local dir_to_z = Mat3:rotate_to_z(dir)

  -- 2. Rotate about z.
  local c, s = math.cos(angle), math.sin(angle)
  local R = Mat3:new_with_rows({ c, -s, 0},
                               { s,  c, 0},
                               { 0,  0, 1})

  -- 3. Move z back to dir.
  local z_to_dir = dir_to_z:get_transpose()

  -- Return their composition; these operations are applied right-to-left.
  return z_to_dir * R * dir_to_z
end

-- This orthogonalizes the rows of self, which also effectively orthogonalizes
-- the columns.
function Mat3:orthogonalize()
  for i = 1, 3 do
    Vec3.normalize(self[i])
    for j = i + 1, 3 do
      self[j] = self[j] - self[i] * self[i]:dot(self[j])
    end
  end
  return self
end

-- This returns the Frobenius distance between self and other, which
-- is the Euclidean distance between the matrices treated as if they were
-- vectors.
function Mat3:frob_dist(other)
  if getmetatable(other) ~= Mat3 then
    -- Error level 2 indicates this is the caller's fault.
    error('Expected arg to be a Mat3', 2)
  end
  assert(other and getmetatable(other) == Mat3)
  local sum = 0
  for i = 1, 3 do for j = 1, 3 do
    sum = sum + (self[i][j] - other[i][j]) ^ 2
  end end
  return math.sqrt(sum)
end

function Mat3:col_as_vec(i)
  assert(getmetatable(self) == Mat3)
  return Vec3:new(self[1][i], self[2][i], self[3][i])
end

-- This returns Mat3s U, lambda so that
--   self = U * Lambda * U'
-- where U is unitary and Lambda is diagonal.
-- The actual returned value `lambda` is an array of the diagonal entries of
-- Lambda, and not a Mat3. The lambda values are sorted largest-first.
-- Note: For now, this won't work on singular matrices and simply expects self
--       to be nonsingular. In the future I can consider checking for this.
function Mat3:eigen_decomp()
  -- We'll use a power iteration algorithm.
  local X0 = Mat3:new_random()
  local iters_done = 0
  repeat
    local X1 = self * X0
    -- Transpose before orthogonalizing so that it happens by columns.
    -- For example, this way we preserve the direction of the first column.
    X0 = X1:get_transpose():orthogonalize():get_transpose()
    iters_done = iters_done + 1
  until X0:frob_dist(X1) < 0.01 or iters_done == 100

  local X1 = self * X0
  local lambda = {}
  for i = 1, 3 do
    local k = 1
    if math.abs(X0[2][i]) > math.abs(X0[k][i]) then k = 2 end
    if math.abs(X0[3][i]) > math.abs(X0[k][i]) then k = 3 end
    lambda[i] = X1[1][i] / X0[1][i]
  end

  return X0, lambda
end

return Mat3
