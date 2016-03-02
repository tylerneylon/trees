--[[

leaf_globs.lua

A module to build leaf globs.

--]]

local leaf_globs = {}

local Vec3 = require 'Vec3'


-- Internal functions.

-- This expects two sequence tables in `t` and `suffix.
-- It appends the contents of `suffix` to the end of `t`.
local function append(t, suffix)
  for _, val in ipairs(suffix) do
    table.insert(t, val)
  end
end

local function rand_pt_on_unit_sphere()
  -- Function r() returns a uniform random in [-1, 1).
  local function r() return math.random() * 2 - 1 end
  local pt
  repeat
    pt  = Vec3:new(r(), r(), r())
  until pt:length() <= 1
  pt:normalize()
  return pt
end

-- This function expects a sequence of Vec3 points on the unit sphere, and adds
-- another point which is linearly independent to the existing ones.
local function add_lin_indep_pt(pts)
  assert(#pts <= 2)
  local new_pt, max_dot_prod
  repeat
    new_pt = rand_pt_on_unit_sphere()
    max_dot_prod = 0
    for _, pt in pairs(pts) do
      max_dot_prod = math.max(max_dot_prod, math.abs(new_pt:dot(pt)))
    end
  until max_dot_prod < 0.9
  pts[#pts + 1] = new_pt
end

local function opposite(pt)
  assert(getmetatable(pt) == Vec3)
  return pt * -1
end

local function normal(t)
  local delta1 = t[2] - t[1]
  local delta2 = t[3] - t[2]
  return delta1:cross(delta2):normalize()
end

local function rand_pt_in_triangle(t)
  assert(#t == 3)
  for i = 1, 3 do assert(getmetatable(t[i]) == Vec3) end

  -- Choose random barycentric coordinates: y1, y2, y3.
  -- https://en.wikipedia.org/wiki/Barycentric_coordinate_system
  -- Mini-proof of correctness: this isometrically maps the triangle
  -- 0 <= x2 < x1 < 1 into the triangle 0 <= x1 <= x2 < 1, and the mapping from
  -- that last triangle onto the target of the barycentric coordinates is also
  -- uniform; for intuition consider target tri with pts (0, 0) (1, 0) & (0, 1).
  local x1, x2 = math.random(), math.random()
  if x2 < x1 then x1, x2 = x2, x1 end  -- Sort x1, x2.
  local y1, y2, y3 = x1, x2 - x1, 1 - x2

  return t[1] * y1 + t[2] * y2 + t[3] * y3
end


-- Public functions.

-- Inputs: center is a Vec3
--         radius is a number
--         triangles is an optional sequence table; new triangles
--                   will be appended to this if it is present
-- Outputs: a sequence table with a flat vertex array of triangle corners
-- The output is designed to be usable as an input to VertexArray:new.
function leaf_globs.make_glob(center, radius, out_triangles)
  assert(getmetatable(center) == Vec3)
  assert(type(radius) == 'number')
  out_triangles = out_triangles or {}

  -- This will be a sequence of Vec3 points on the unit sphere. We'll try to
  -- make the first 3 linearly independent, and choose the last so that the
  -- tetrahedron we've formed includes the origin.
  local init_pts = {}
  for i = 1, 3 do
    add_lin_indep_pt(init_pts)
  end
  local opposite_triangle = {}
  for i = 1, 3 do table.insert(opposite_triangle, opposite(init_pts[i])) end
  table.insert(init_pts, rand_pt_in_triangle(opposite_triangle):normalize())

  -- This is a sequence of triangles. Each triangle is a triple of Vec3 points,
  -- ordered counterclockwise when viewed from the outside.
  -- For now, all points are centered at the origin. We'll translate by center
  -- just before values are appended to out_triangles.
  local glob_triangles = {}

  -- Transfer the initial points to our glob_triangles sequence.
  assert(#init_pts == 4)
  for i = 1, 4 do
    -- Insert the triangle that omits init_pts[i].
    -- We have to be careful to put the points in counterclockwise order.
    local pts = init_pts  -- I like short names.
    local t = {pts[i % 4 + 1], pts[(i + 1) % 4 + 1], pts[(i + 2) % 4 + 1]}
    if normal(t):dot(t[1]) < 0 then
      -- We need to switch the order.
      t[2], t[3] = t[3], t[2]
    end
    table.insert(glob_triangles, t)
  end

  -- TODO Make the globs more interesting.

  -- Transfer the glob_triangles over to out_triangles, scaling and recentering
  -- on the way.
  for _, t in pairs(glob_triangles) do
    for i = 1, 3 do
      append(out_triangles, t[i] * radius + center)
    end
  end

  return out_triangles
end

return leaf_globs
