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

local function tri_area(t)

  assert(type(t) == 'table')
  assert(#t == 3)
  assert(getmetatable(t[1]) == Vec3)

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

local function part_of_pt_orth_to_basis(p, basis)
  assert(getmetatable(p) == Vec3)
  assert(type(basis) == 'table')
  for _, basis_pt in pairs(basis) do
    assert(getmetatable(basis_pt) == Vec3)
  end

  for _, basis_pt in pairs(basis) do
    -- Create a local copy of basis_pt so we don't change the original.
    local b = Vec3:new(basis_pt):normalize()
    p = p - b * p:dot(b)
  end

  return p
end

-- This function expects a sequence of Vec3 points on the unit sphere, and adds
-- another point which is linearly independent to the existing ones.
local function add_lin_indep_pt(pts)
  assert(#pts <= 2)

  local new_pt
  repeat
    new_pt = rand_pt_on_unit_sphere()
    local x = part_of_pt_orth_to_basis(new_pt, pts)
  until math.abs(x:length()) > 0.5
  -- Use the following to guarantee that the points are actually fairly close to
  -- being *dependent*. Possibly useful for testing.
  --until #pts == 0 or math.abs(x:length()) < 0.4

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

  -- Bias the barycentric coordinates toward the middle.
  local a = (math.max(y1, y2, y3) - 0.3) / 0.7  -- a is in [0, 1].
  local w = a * a  -- w is in [0, 1], but more likely to be small.
  y1, y2, y3 = w * y1 + (1 - w) * 0.3,
               w * y2 + (1 - w) * 0.3,
               w * y3 + (1 - w) * 0.3

  -- Uncomment the following line to always choose the center point.
  --y1, y2, y3 = 0.3333, 0.3333, 0.3333
  --y1, y2, y3 = 0.1, 0.1, 0.8

  return t[1] * y1 + t[2] * y2 + t[3] * y3
end

local function triangle_is_counterclockwise(t)
  assert(type(t) == 'table' and #t == 3 and getmetatable(t[1]) == Vec3)

  -- Find the normal of t.
  local side1, side2 = t[2] - t[1], t[3] - t[2]
  local normal       = side1:cross(side2):normalize()

  -- The triangle is oriented counterclockwise, as seen from a viewing looking
  -- toward the origin, when <normal, t[1]> > 0.
  return normal:dot(t[1]) > 0
end

-- This function expects a Vec3 pt and a sequence of 3 Vec3s representing a
-- triangle. It returns true iff t is not included in the half-space delineated
-- by the plane of t that includes the origin.
-- (I'm not considering edge cases carefully here as I don't expect them as
-- valid inputs.)
local function pt_is_outside_triangle(pt, t)
  assert(getmetatable(pt) == Vec3)
  assert(type(t) == 'table' and #t == 3 and getmetatable(t[1]) == Vec3)

  -- Find the normal of t that points away from the origin.
  local side1, side2 = t[2] - t[1], t[3] - t[2]
  local normal       = side1:cross(side2):normalize()
  local d            = normal:dot(t[1])
  assert(d > 0)  -- Verify that it points away from the origin.

  -- At this point, every point x inside the triangle's half-space obeys the
  -- equation <x, normal> <= d.
  return pt:dot(normal) > d
end

local function sort_counterclockwise_with_up_vec(center, up)
  assert(getmetatable(center) == Vec3)
  assert(getmetatable(up) == Vec3)

  -- Choose an out vector that is far from linearly dependent with up.
  local out = Vec3:new(1, 0, 0)
  if math.abs(up[1]) > math.abs(up[2]) then
    out = Vec3:new(0, 1, 0)
  end

  local function is_left_of(x1, x2, print)
    local v1, v2 = x1 - center, x2 - center
    return v1:cross(up):dot(v2) > 0
  end

  -- This is a closure which is a comparison function between points in R^3.
  local function cmp(x1, x2, is_subcall)

    -- Interestingly, even if there is no redundancy in the table being sorted,
    -- I've seen calls to cmp with x1 == x2. So it seems good to make sure the
    -- code correctly handles that case.

    if not is_left_of(x1, x2) then
      -- If both is_left_of(x1, x2) and is_left_of(x2, x1) are false, we must
      -- have x1 equivalent to x2; then the subcall should return true so that
      -- the top-level cmp call returns false.
      if is_subcall then return true end
      return not cmp(x2, x1, true)
    end

    assert(is_left_of(x1, x2))
    local bdry_cross = is_left_of(x1, out, print) and is_left_of(out, x2, print)
    return bdry_cross
  end

  return cmp
end

-- This function expects the input to be a sequence of triangles describing a
-- convex hull with corners on the unit sphere. It further expects that all
-- shared corner points are represented by the same Lua table. It adds a new
-- somewhat random point to the convex hull.
local function add_new_point(triangles)

  -- Choose the largest triangle to help us generate a useful new point.
  table.sort(triangles, sort_by_area)
  local big_t = triangles[#triangles]

  -- Choose a new point. This is guaranteed to be outside the current convex
  -- hull as it, and all old corners, are unit vectors.
  local pt = rand_pt_in_triangle(big_t):normalize()

  -- Remove the triangles which are no longer in the convex hull, and track the
  -- points which will need to be re-attached.
  local pts_to_reattach = {}  -- This is a key set.
  local i = 1
  while i <= #triangles do
    local t = triangles[i]
    if pt_is_outside_triangle(pt, t) then
      for j = 1, 3 do pts_to_reattach[t[j]] = true end
      table.remove(triangles, i)
    else
      i = i + 1
    end
  end

  -- Sort the pts to reattach in counterclockwise order.
  local reattach_pts = {}
  for p in pairs(pts_to_reattach) do table.insert(reattach_pts, p) end
  table.sort(reattach_pts, sort_counterclockwise_with_up_vec(pt, pt))

  -- Set up new triangles using the sorted reattachment points.
  local n = #reattach_pts
  for i = 1, n do
    local t = {reattach_pts[i], reattach_pts[i % n + 1], pt}
    assert(triangle_is_counterclockwise(t))
    table.insert(triangles, t)
  end
end

local function check_all_unit_vecs(triangles)
  for _, t in pairs(triangles) do
    for i = 1, 3 do
      local len = t[i]:length()
      assert(math.abs(len - 1) < 0.0001)
    end
  end
end

local function num_pts_in_triangles(triangles)
  local pt_set = {}
  for _, t in pairs(triangles) do
    for i = 1, 3 do
      pt_set[t[i]] = true
    end
  end
  local pt_seq = {}
  for pt in pairs(pt_set) do
    pt_seq[#pt_seq + 1] = pt
  end
  return #pt_seq
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

  assert(num_pts_in_triangles(glob_triangles) == 4)

  -- Break down the triangles if needed.
  -- I could have used a for loop here, but I believe this code is clearer.
  local n = 4
  while n < num_pts do
    add_new_point(glob_triangles)
    n = n + 1
    assert(num_pts_in_triangles(glob_triangles) == n)
  end

  -- Transfer the glob_triangles over to out_triangles, scaling and recentering
  -- on the way.
  for _, t in pairs(glob_triangles) do
    for i = 1, 3 do
      append(out_triangles, t[i] * radius + center)
    end
  end

  return out_triangles
end

function leaf_globs.add_leaves(tree)
  local globs = {}

  for _, tree_pt in pairs(tree) do
    if tree_pt.kind == 'leaf' then
      if math.random() < 0.4 then
        leaf_globs.make_glob(tree_pt.pt, 0.11, 25, globs)
      end
    end
  end

  local green = {0, 0.6, 0}
  tree.leaves = VertexArray:new(globs, 'triangles', green)

  return globs
end

return leaf_globs
