--[[

leaf_globs.lua

A module to build leaf globs.

--]]

local leaf_globs = {}

local kmeans = require 'kmeans'

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'

-- TEMP ? maybe
local dbg = require 'dbg'


-- Parameters.

local num_custers = 11


-- Internal functions.

-- This expects two sequence tables in `t` and `suffix.
-- It appends the contents of `suffix` to the end of `t`.
local function append(t, suffix)
  if type(suffix) ~= 'table' then table.insert(t, suffix); return end
  for _, val in ipairs(suffix) do
    table.insert(t, val)
  end
end

-- This accepts an array of arrays and turns it into a flat array of the
-- indirect elements. Eg, {{1, 2}, {3}, {4, 5, 6}} -> {1, 2, 3, 4, 5, 6}.
local function flatten(array)
  if type(array) ~= 'table' then return array end

  local flat_array = {}
  for _, item in ipairs(array) do
    append(flat_array, flatten(item))
  end
  return flat_array
end

-- This replaces each Vec3 v in arr by M * v.
local function xform_flat_array(M, arr)
  for i = 1, #arr, 3 do
    local v = M * Vec3:new(arr[i], arr[i + 1], arr[i + 2])
    arr[i], arr[i + 1], arr[i + 2] = v[1], v[2], v[3]
  end
end

-- This function accepts {centroid, points} and returns
--   axes   = [Vec3] and
--   scales = [number]
-- which represent, ordered most significant to least, a basis that will
-- heuristically minimally encompass the cluster. This is based on the SVD,
-- although no complete SVD calculation ever happens.
local function find_cluster_directions(cluster)
  assert(cluster and cluster.points and cluster.centroid)

  -- Let C be the 3 x #points matrix of cluster points.
  -- Then D = C * C' is a symmetric 3x3 matrix, and we can find the eigenvalue
  -- decomposition of it.
  -- D_ij = < C_i, C_j >, where C_i is the ith row of C.
  local pts = cluster.points
  local c   = cluster.centroid
  local D   = Mat3:new_zero()
  for i = 1, 3 do for j = i, 3 do
    local sum = 0
    for k = 1, #pts do
      sum = sum + (pts[k][i] - c[i]) * (pts[k][j] - c[j])
    end
    D[i][j] = sum
    D[j][i] = sum
  end end

  local U, lambda = D:eigen_decomp()
  -- Set lambda = sqrt(lambda) as these are the true SVD's singular values.
  for i, val in pairs(lambda) do
    lambda[i] = math.sqrt(val)
  end

  -- TODO Consider: I think I may want to work with sqrt(lambda) values here.

  -- Our scales will be proportional to the values of lambda.
  -- We'll choose the smallest values that ensure the corresponding ellipsoid
  -- encompasses all the points.
  local V = U:get_transpose()
  local t_sq_max = 0
  for i = 1, #pts do
    local t_sq = 0
    local p    = V * (pts[i] - c)
    for j = 1, 3 do
      t_sq = t_sq + (p[j] / lambda[j]) ^ 2
    end
    t_sq_max = math.max(t_sq_max, t_sq)
  end
  local t = math.sqrt(t_sq_max) * 1.05  -- Properly include all points.

  local axes   = {V[1], V[2], V[3]}  -- The rows of V are the columns of U.
  local scales = {}
  for i = 1, 3 do
    scales[i] = lambda[i] * t * 0.95
  end
  -- TEMP
  print('t = ' .. t)

  return axes, scales
end

-- This function accepts {centroid, points} and returns
--   axes   = [Vec3] and
--   scales = [number]
-- which represent, ordered most significant to least, a basis that will
-- heuristically minimally encompass the cluster. This is like a poor man's SVD.
local function old_find_cluster_directions(cluster)
  assert(cluster and cluster.points and cluster.centroid)

  local axes, scales = {}, {}
  local c = cluster.centroid

  -- Find the first two axes and scales.
  for i = 1, 2 do
    print('i = ' .. i)
    local far_vec, far_d = nil, 0
    for _, pt in pairs(cluster.points) do
      local vec = pt - c
      if i == 2 then
        vec = vec - vec:dot(axes[1]) * axes[1]
      end
      local d = vec:length()
      print('d = ' .. d)
      if d >= far_d then
        far_vec, far_d = vec, d
      end
    end
    -- Take the length before we normalize so the length is correct.
    table.insert(scales, far_vec:length())
    table.insert(axes, far_vec:normalize())
  end

  -- Find the third axis.
  table.insert(axes, axes[1]:cross(axes[2]))

  -- Set up a matrix to help find the third scale.
  local A = Mat3:new_with_rows(axes[1], axes[2], axes[3])

  -- Choose 2nd and 3rd scales so the corresponding ellipsoid is just big enough
  -- to include all cluster points.
  for i = 2, 3 do
    local max_s = 0
    for _, pt in pairs(cluster.points) do
      local v = A * (pt - c)
      local x = 0
      for j = 1, i - 1 do x = x + (v[j] / scales[j]) ^ 2 end
      if math.abs(v[i]) > 0.0001 then
        max_s = math.max(max_s, math.abs(v[i]) / (1 - x))
      end
    end
    scales[i] = max_s
  end

  -- TEMP
  print('scales:')
  dbg.pr_val(scales)

  return axes, scales
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

-- This expects a tree_pt as input, and returns:
-- max_num_edges, max_distance
-- as output, where max_distance is a Euclidean distance.
local function max_dist_to_leaf(t)
  if t.max_edges_to_leaf then
    return t.max_edges_to_leaf, t.max_dist_to_leaf
  end

  if t.kind == 'leaf' then
    t.max_edges_to_leaf, t.max_dist_to_leaf = 0, 0
  elseif t.kids then
    local num_edges, distances = {}, {}
    for i = 1, 2 do
      num_edges[i], distances[i] = max_dist_to_leaf(t.kids[i])
    end

    t.max_edges_to_leaf, t.max_dist_to_leaf =
        math.max(num_edges[1], num_edges[2]),
        math.max(distances[1], distances[2])
  else
    assert(t.up)
    local num_edges, distance = max_dist_to_leaf(t.up)
    local delta = (t.up.pt - t.pt):length()
    t.max_edges_to_leaf, t.max_dist_to_leaf = num_edges + 1, distance + delta
  end

  return t.max_edges_to_leaf, t.max_dist_to_leaf
end

-- This returns all the leaf points, as a sequence, of the given tree.
local function all_leaf_points(tree)

  local function all_l_pts_leafward(tree_pt, l_pts)
    if tree_pt.kind == 'leaf' then
      table.insert(l_pts, tree_pt)
    elseif tree_pt.kids then
      all_l_pts_leafward(tree_pt.kids[1], l_pts)
      all_l_pts_leafward(tree_pt.kids[2], l_pts)
    else
      assert(tree_pt.kind == 'child')
      all_l_pts_leafward(tree_pt.up, l_pts)
    end
    return l_pts
  end

  -- This depends on the fact that the first tree point is the trunk.
  return all_l_pts_leafward(tree[1], {})
end

-- This returns tree iff all the leaf points leafward from the given tree point
-- are already marked as hit_by_glob.
local function all_leaf_pts_hit(tree_pt)
  if tree_pt.kind == 'leaf' then
    return tree_pt.hit_by_glob
  elseif tree_pt.kids then
    return all_leaf_pts_hit(tree_pt.kids[1]) and
           all_leaf_pts_hit(tree_pt.kids[2])
  else
    assert(tree_pt.kind == 'child')
    return all_leaf_pts_hit(tree_pt.up)
  end
end

-- This marks every hit leaf point as hit_by_glob, and removes any new hits from
-- the unhit_l_pts sequence.
local function update_leaf_pts_hit(unhit_l_pts, center, radius)
  local effective_r = 0.9 * radius
  local i = 1
  while i <= #unhit_l_pts do
    local l_pt = unhit_l_pts[i]
    local d    = (center - l_pt.pt):length()
    if d < effective_r then
      l_pt.hit_by_glob = true
      table.remove(unhit_l_pts, i)
    else
      i = i + 1
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

function leaf_globs.add_leaves_idea1(tree)
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

function leaf_globs.add_leaves_idea2(tree)
  local globs = {}
  for _, tree_pt in pairs(tree) do
    if not tree_pt.has_glob and tree_pt.kind == 'parent' then
      if tree_pt.kids[1].up.kind == 'leaf' and
         tree_pt.kids[2].up.kind == 'leaf' then

        -- Find a good radius for this leaf glob.
        local r = 0
        for i = 1, 2 do
          local d = (tree_pt.kids[i].up.pt - tree_pt.pt):length()
          if d > r then r = d end
        end
        r = r * 1.2

        -- Set up the glob.
        leaf_globs.make_glob(tree_pt.pt, r, 30, globs)
      end
    end
  end

  local green = {0, 0.6, 0}
  tree.leaves = VertexArray:new(globs, 'triangles', green)

  return globs
end

-- This version puts the centers of leaf globs farther down the tree.
-- Each leaf glob ends up covering multiple leaf points.
function leaf_globs.add_leaves_idea2_v2(tree)
  local globs = {}
  for _, tree_pt in pairs(tree) do
    if not tree_pt.has_glob and tree_pt.kind == 'parent' then
      local num_edges, distance = max_dist_to_leaf(tree_pt)
      if num_edges == 3 then
        local r = distance * 1.2  -- Add a small buffer distance.
        leaf_globs.make_glob(tree_pt.pt, r, 30, globs)
      end
    end
  end

  local green = {0, 0.6, 0}
  tree.leaves = VertexArray:new(globs, 'triangles', green)

  return globs
end

-- This version reduces redundancy in leaf globs by trying not to add a new leaf
-- glob if the corresponding leaf points have already incidentally been covered
-- by other globs.
function leaf_globs.add_leaves_idea2_v3(tree)

  local unhit_l_pts = all_leaf_points(tree)
  local globs = {}
  local num_globs_added = 0
  for _, tree_pt in pairs(tree) do
    if not tree_pt.has_glob and tree_pt.kind == 'parent' then
      local num_edges, distance = max_dist_to_leaf(tree_pt)
      if num_edges == 3 and not all_leaf_pts_hit(tree_pt) then
        local r = distance * 1.2  -- Add a small buffer distance.
        leaf_globs.make_glob(tree_pt.pt, r, 30, globs)
        update_leaf_pts_hit(unhit_l_pts, tree_pt.pt, r)
        num_globs_added = num_globs_added + 1
      end
    end
  end

  local green = {0, 0.6, 0}
  tree.leaves = VertexArray:new(globs, 'triangles', green)
  --tree.leaves = VertexArray:new(globs, 'points', green, 10)

  print('Used ' .. num_globs_added .. ' leaf globs.')

  return globs
end

-- TODO comment
function leaf_globs.add_leaves_idea3(tree)

  -- TEMP
  do
    tree.leaf_pts = all_leaf_points(tree)
    tree.flat_leaf_pts = {}
    for _, leaf_pt in pairs(tree.leaf_pts) do
      append(tree.flat_leaf_pts, leaf_pt.pt)
    end
    local yellow = {1, 1, 0}
    tree.leaf_pt_array = VertexArray:new(tree.flat_leaf_pts,  -- data
                                         'points',            -- draw mode
                                         yellow,              -- color
                                         10)                  -- point size
  end

  -- TEMP
  do
    local leaf_pts = {}  -- This will be a [Vec3].
    -- Convert tree_pt format to just a Vec3.
    for _, tree_leaf_pt in pairs(tree.leaf_pts) do
      table.insert(leaf_pts, tree_leaf_pt.pt)
    end
    local clusters = kmeans.find_clusters(leaf_pts, num_clusters)
    tree.cluster_arrays = {}
    local colors = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1},
                    {1, 1, 0}, {1, 0, 1}, {0, 1, 1},
                    {0.5, 0.5, 0}, {0.5, 0, 0.5}, {0, 0.5, 0.5}}
    for i, cluster in pairs(clusters) do
      local array = VertexArray:new(flatten(cluster.points),
                                    'points',
                                    {0.2, 0.6, 0.3}, -- colors[i],
                                    10)
      table.insert(tree.cluster_arrays, array)
    end

    -- Set up leaf globs and arrays based on the clusters.
    -- TODO 1. Accept a transform matrix in leaf_globs.make_glob().
    --      2. Determine & use a good transform for each cluster.
    tree.leaf_arrays = {}
    for i, cluster in pairs(clusters) do

      -- TEMP
      local axes, scales = find_cluster_directions(cluster)

      -- TEMP
      print('scales:')
      for i = 1, 3 do
        io.write((i > 1 and ', ' or '') .. scales[i])
      end
      print('')

      --local glob = leaf_globs.make_glob(cluster.centroid, 0.1, 30)

      local glob = leaf_globs.make_glob(Vec3:new(0, 0, 0), 1.0, 30)

      local U       = Mat3:new_with_cols(axes[1], axes[2], axes[3])
      local U_prime = U:get_transpose()
      local L       = Mat3:new_with_rows({scales[1], 0, 0},
                                         {0, scales[2], 0},
                                         {0, 0, scales[3]})
      local M = U * L * U_prime

      xform_flat_array(M, glob)
      ---[[
      for j = 1, #glob, 3 do
        local v = Vec3:new(glob[j], glob[j + 1], glob[j + 2]) + cluster.centroid
        glob[j], glob[j + 1], glob[j + 2] = v[1], v[2], v[3]
      end
      --]]

      table.insert(tree.leaf_arrays,
                   VertexArray:new(glob, 'triangles', {0.2, 0.6, 0.3})) -- colors[i],
    end

  end
end

function leaf_globs.add_leaves(tree)
  return leaf_globs.add_leaves_idea3(tree)
end

return leaf_globs
