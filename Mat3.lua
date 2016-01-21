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


-- Public functions.

function Mat3:new_with_cols(c1, c2, c3)
  -- Store the entries by rows internally.
  local m = {{}, {}, {}}
  local cols = {c1, c2, c3}
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = cols[j][i]
  end end
  self.__index = self
  return setmetatable(m, self)
end

function Mat3:new_with_rows(r1, r2, r3)
  -- Store the entries by rows internally.
  local m = {{}, {}, {}}
  local rows = {r1, r2, r3}
  for i = 1, 3 do for j = 1, 3 do
    m[i][j] = rows[i][j]  -- Copy so edits to r_i don't affect the new matrix.
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
  local m_mt = getmetatable(m)
  assert(m_mt == Vec3 or m_mt == Mat3)

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
  -- TODO Improve the error message on this assert (and any similar ones).
  assert(getmetatable(dir) == Vec3)
  local v3 = Vec3:new(dir):normalize()

  -- Find vectors v1 and v2 so that {v1, v2, v3} are orthonormal and satisfy the
  -- right-hand rule. In other words, the matrix {v1, v2, v3} has determinant 1.

  local away_from_v3
  if v3[1] > v3[2] then
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

return Mat3
