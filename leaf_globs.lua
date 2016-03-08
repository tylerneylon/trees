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
  -- y1, y2, y3 = 0.3333, 0.3333, 0.3333
  print('y1, y2, y3 = ' .. y1 .. ', ' .. y2 .. ', ' .. y3)

  print('t values:')
  for i = 1, 3 do
    dbg.pr_val(t[i])
  end
  print('final val:')
  dbg.pr_val(t[1] * y1 + t[2] * y2 + t[3] * y3)

  return t[1] * y1 + t[2] * y2 + t[3] * y3
end

-- TODO Remove the function below once the replacement is done.

-- This expects a sequence of spheric triangles as input, and replaces the last
-- one with a randomly partitioned version of itself.
local function replace_last_triangle(triangles)

  assert(false) -- TEMP to ensure this function isn't called anymore
  -- It was a good function. Well, mostly.

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

  -- TEMP
  local function pr_val(name, val)
    print(name .. ':')
    dbg.pr_val(val)
  end
  if d <= 0 then
    -- Note: I found the issue that some triangles appear to not be oriented
    -- properly.
    print('d <= 0 in pt_is_outside_trinagle')
    pr_val('pt', pt)
    pr_val('t', t)
    pr_val('side1', side1)
    pr_val('side2', side2)
    pr_val('normal', normal)
    pr_val('d', d)
    os.exit(0)
  end

  assert(d > 0)  -- Verify that it points away from the origin.

  -- At this point, every point x inside the triangle's half-space obeys the
  -- equation <x, normal> <= d.
  return pt:dot(normal) > d
end

local function sort_counterclockwise_with_up_vec(center, up)
  assert(getmetatable(center) == Vec3)
  assert(getmetatable(up) == Vec3)

  -- TEMP
  local convert
  do
    local out = Vec3:new(1, 0, 0)
    if math.abs(up[1]) > math.abs(up[2]) then out = Vec3:new(0, 1, 0) end
    local axis1 = out:cross(up):normalize()
    local axis2 = up:cross(axis1):normalize()

    -- This converts the input into a 2d version of the new coord system.
    -- The return value has the format {x, y}.
    convert = function (p)
      return {axis1:dot(p), axis2:dot(p)}
    end
  end

  -- Choose an out vector that is far from linearly dependent with up.
  local out = Vec3:new(1, 0, 0)
  if math.abs(up[1]) > math.abs(up[2]) then
    out = Vec3:new(0, 1, 0)
  end

  --[[
  print('out:')
  dbg.pr_val(out)
  print('convert(out) = ' .. dbg.val_to_str(convert(out)))
  --]]

  local function is_left_of(x1, x2, print)
    local v1, v2 = x1 - center, x2 - center
    --return v1:cross(up):dot(v2) > 0
    local x = v1:cross(up):dot(v2) > 0
    print('is_left_of(' .. dbg.val_to_str(x1) .. ', ' ..
          dbg.val_to_str(x2) .. ') will return ' .. tostring(x))
    return x
  end

  -- This is a closure which is a comparison function between points in R^3.
  local function cmp(x1, x2, is_subcall)

    -- Interestingly, even if there is no redundancy in the table being sorted,
    -- I've seen calls to cmp with x1 == x2. So it seems good to make sure the
    -- code correctly handles that case.

    local normal_print = print
    local num_calls_made = 0
    local function print(s, is_last_call)
      do return end
      local prefix = (is_subcall and '    ' or '')
      if num_calls_made == 0 then
        prefix = prefix .. '/ '
      elseif is_last_call then
        prefix = prefix .. '\\ '
      else
        prefix = prefix .. '| '
      end
      normal_print(prefix .. s)
      num_calls_made = num_calls_made + 1
    end

    print('Running cmp(' .. dbg.val_to_str(x1) .. ', ' ..
          dbg.val_to_str(x2) .. ', ' .. tostring(not not is_subcall) .. ')')
    print('  converted, those pts are ' .. dbg.val_to_str(convert(x1)) ..
          ', ' .. dbg.val_to_str(convert(x2)))

    print('Calling is_left_of(x1, x2)')
    if not is_left_of(x1, x2, print) then
      -- If both is_left_of(x1, x2) and is_left_of(x2, x1) are false, we must
      -- have x1 equivalent to x2; then the subcall should return true so that
      -- the top-level cmp call returns false.
      if is_subcall then return true end
      assert(not is_subcall)  -- Verify shallow-only recursion.
      print('Making a subcall')
      return not cmp(x2, x1, true)
    end
    -- TEMP
    assert(is_left_of(x1, x2, print))
    print('Evaling is_left_of(x1, out) and is_left_of(out, x2)')
    local bdry_cross = is_left_of(x1, out, print) and is_left_of(out, x2, print)
    print('Returning ' .. tostring(not bdry_cross), true)
    return bdry_cross
  end

  return cmp
end

-- This function expects the input to be a sequence of triangles describing a
-- convex hull with corners on the unit sphere. It further expects that all
-- shared corner points are represented by the same Lua table. It adds a new
-- somewhat random point to the convex hull.
local function add_new_point(triangles)

  --print('[[0]]')

  --[[
  -- TEMP
  print('')
  print('add_new_point')
  print('')
  --]]

  -- Choose the largest triangle to help us generate a useful new point.
  table.sort(triangles, sort_by_area)
  local big_t = triangles[#triangles]

  --print('[[1]]')

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

  --print('[[2]]')

  -- Sort the pts to reattach in counterclockwise order.
  local reattach_pts = {}
  for p in pairs(pts_to_reattach) do table.insert(reattach_pts, p) end

  --[[
  -- TEMP
  print('')
  print('#reattach_pts = ' .. #reattach_pts)
  print('values:')
  dbg.pr_val(reattach_pts)
  print('')
  --]]

  table.sort(reattach_pts, sort_counterclockwise_with_up_vec(pt, pt))

  --print('[[3]]')

  --[[
  -- TEMP
  do
    local out = Vec3:new(1, 0, 0)
    if math.abs(pt[1]) > math.abs(pt[2]) then out = Vec3:new(0, 1, 0) end
    local axis1 = out:cross(pt):normalize()
    local axis2 = pt:cross(axis1):normalize()

    -- This converts the input into a 2d version of the new coord system.
    -- The return value has the format {x, y}.
    local function convert(p)
      return {axis1:dot(p), axis2:dot(p)}
    end

    print('')
    print('reattach_pts, in order:')
    for _, p in ipairs(reattach_pts) do
      local a = dbg.val_to_str(p)
      local b = dbg.val_to_str(convert(p))
      print(a .. ' -> ' .. b)
      --dbg.pr_val(convert(p))
    end
  end
  --]]

  -- Set up new triangles using the sorted reattachment points.
  local n = #reattach_pts
  for i = 1, n do
    local t = {reattach_pts[i], reattach_pts[i % n + 1], pt}

    -- TEMP
    -- TODO NEXT Debug that this ever happens.
    if not triangle_is_counterclockwise(t) then
      print('Error: created a non-counterclockwise triangle!')
      os.exit(0)
    end

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

  -- TEMP
  assert(num_pts_in_triangles(glob_triangles) == 4)

  -- Break down the triangles if needed.
  -- I could have used a for loop here, but I believe this code is clearer.
  local n = 4
  while n < num_pts do
    add_new_point(glob_triangles)
    n = n + 1
    -- TEMP
    assert(num_pts_in_triangles(glob_triangles) == n)
  end

  --[[
  local n = 4
  while n < num_pts do
    --table.sort(glob_triangles, sort_by_area)
    add_new_point(glob_triangles)
    --replace_last_triangle(glob_triangles)
    n = n + 1
  end
  --]]

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
