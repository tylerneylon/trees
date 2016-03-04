--[[

leaf_globs.lua

A module to build leaf globs.

--]]

local leaf_globs = {}

local Vec3 = require 'Vec3'

-- TEMP
local dbg = require 'dbg'

-- Internal functions.

-- This expects two sequence tables in `t` and `suffix.
-- It appends the contents of `suffix` to the end of `t`.
local function append(t, suffix)
  for _, val in ipairs(suffix) do
    table.insert(t, val)
  end
end

local function tri_area(t)

  dbg.pr_val(t)

  assert(type(t) == 'table')
  assert(#t == 3)
  assert(getmetatable(t[1]) == Vec3)

  --assert(type(t) == 'table' and #t == 3 and type(t[1]) == 'number')

  -- Calculate the area using Heron's formula.

  -- Find the side lengths.
  local s = {}
  for i = 1, 3 do
    s[i] = (t[i] - t[i % 3 + 1]):length()
  end

  -- Find the semiperimeter.
  local sp = (s[1] + s[2] + s[3]) / 2

  return math.sqrt(sp * (sp - s[1]) * (sp - s[2]) * (sp - s[3]))
end

-- This expects two triangles as input, and returns true when
-- area(t1) < area(t2).
local function sort_by_area(t1, t2)
  assert(type(t1) == 'table' and type(t2) == 'table')
  return tri_area(t1) < tri_area(t2)
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

  -- TEMP
  y1, y2, y3 = 0.3333, 0.3333, 0.3333
  print('y1, y2, y3 = ' .. y1 .. ', ' .. y2 .. ', ' .. y3)

  print('t values:')
  for i = 1, 3 do
    dbg.pr_val(t[i])
  end
  print('final val:')
  dbg.pr_val(t[1] * y1 + t[2] * y2 + t[3] * y3)

  return t[1] * y1 + t[2] * y2 + t[3] * y3
end

-- This expects a sequence of spheric triangles as input, and replaces the last
-- one with a randomly partitioned version of itself.
local function replace_last_triangle(triangles)

  -- TEMP
  print('replace_last_triangle')
  print('input size = ' .. #triangles)

  assert(type(triangles) == 'table')
  assert(type(triangles[#triangles]) == 'table')

  local n      = #triangles
  local old_t  = triangles[n]
  local new_pt = rand_pt_in_triangle(old_t)
  new_pt:normalize()
  -- TEMP
  triangles[n] = nil
  for i = 1, 3 do
    triangles[n] = {old_t[i], old_t[i % 3 + 1], new_pt}
    n = n + 1
  end

  print('output size = ' .. #triangles)
end

local function check_all_unit_vecs(triangles)
  for _, t in pairs(triangles) do
    for i = 1, 3 do
      local len = t[i]:length()
      assert(math.abs(len - 1) < 0.0001)
    end
  end
end


-- Public functions.

-- Inputs: center is a Vec3
--         radius is a number
--         num_pts is the number of corner points of the glob, expected >= 4
--         triangles is an optional sequence table; new triangles
--                   will be appended to this if it is present
-- Outputs: a sequence table with a flat vertex array of triangle corners
-- The output is designed to be usable as an input to VertexArray:new.
function leaf_globs.make_glob(center, radius, num_pts, out_triangles)
  assert(getmetatable(center) == Vec3)
  assert(type(radius) == 'number')
  assert(type(num_pts) == 'number')
  assert(num_pts == math.floor(num_pts))
  assert(num_pts >= 4)
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

  -- Break down the triangles if needed.
  local n = (#glob_triangles - 4) / 2 + 4
  while n < num_pts do
    table.sort(glob_triangles, sort_by_area)
    replace_last_triangle(glob_triangles)
    n = n + 1
  end

  -- TEMP
  --check_all_unit_vecs(glob_triangles)

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
