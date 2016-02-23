--[[

rings.lua

A module to add rings to a tree skeleton.
This code is meant to be called form make_tree.lua.

--]]

local rings = {}

local dbg  = require 'dbg'

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'


-- Debug functions.

local last_timestamp = false

local function checkpoint(name)
  local now = timestamp()
  if not last_timestamp then
    print('from checkpoint ' .. name)
  else
    local interval = now - last_timestamp
    print(('to checkpoint %s: %f'):format(name, interval))
  end
  last_timestamp = now
end

local function assertup(cond, msg)
  if not cond then
    error(msg, 3)  -- 3 = level; the caller reports the error from the callee.
  end
end

local function check_tree_integrity(tree)
  local fmt = 'Expected %s to be a Vec3.'
  for _, tree_pt in pairs(tree) do
    assertup(getmetatable(tree_pt.pt) == Vec3, fmt:format('tree_pt.pt'))
    if tree_pt.down then
      assertup(getmetatable(tree_pt.down.pt) == Vec3,
               fmt:format('tree_pt.down.pt'))
    elseif tree_pt.up then
      assertup(getmetatable(tree_pt.up.pt) == Vec3,
               fmt:format('tree_pt.up.pt'))
    end
  end
end


-- Internal functions.

local function get_num_pts(tree_pt)
  if tree_pt.ring_num_pts then return tree_pt.ring_num_pts end

  local num_pts
  if tree_pt.kind == 'leaf' then
    return 1
  elseif tree_pt.kind == 'child' then
    local up_pt = tree_pt.up
    if up_pt.kind == 'leaf' then
      num_pts = 3
    else
      num_pts = get_num_pts(up_pt)
    end
  else
    assert(tree_pt.kind == 'parent')
    num_pts = get_num_pts(tree_pt.kids[1]) +
              get_num_pts(tree_pt.kids[2]) - 2
  end

  num_pts = math.min(num_pts, max_ring_pts)
  tree_pt.ring_num_pts = num_pts
  return num_pts
end

local function get_up_vec(tree_pt)
  assert(getmetatable(tree_pt.pt) == Vec3)

  local up
  if tree_pt.kind == 'child' then
    assert(tree_pt.up and tree_pt.up.kind)
    assert(getmetatable(tree_pt.up.pt) == Vec3)
    up = tree_pt.up.pt - tree_pt.pt
  else
    assert(tree_pt.down and tree_pt.down.kind)
    assert(getmetatable(tree_pt.pt) == Vec3)
    assert(getmetatable(tree_pt.down.pt) == Vec3)
    up = tree_pt.pt - tree_pt.down.pt
  end
  assert(getmetatable(up) == Vec3)
  return up
end

local function get_sibling(tree_pt)
  assert(tree_pt.kind == 'child')
  local parent = tree_pt.parent
  if parent.kids[1] == tree_pt then
    return parent.kids[2]
  else
    return parent.kids[1]
  end
end

local function get_ring_radius(tree_pt, num_pts, angle)
  if tree_pt.ring_radius then
    return tree_pt.ring_radius, tree_pt.ring_num_pts, tree_pt.ring_angle
  end

  if num_pts == nil then
    num_pts = get_num_pts(tree_pt)
    angle   = 2 * math.pi / num_pts
  end

  local radius
  if tree_pt.kind == 'leaf' then
    radius = 0
  elseif tree_pt.kind == 'child' then
    --radius = get_ring_radius(tree_pt.up) + 0.001
    -- radius = math.max(get_ring_radius(tree_pt.up), 0.002) * 1.01
    radius = math.max(get_ring_radius(tree_pt.up), 0.002)  -- Formerly 0.0017
    --[[
    local up = get_up_vec(tree_pt)
    local part_len = 0.7 * up:length() / num_pts
    radius = part_len / 2 / math.sin(angle / 2)
    --]]
  else
    assert(tree_pt.kind == 'parent')
    local r = {}
    for i = 1, 2 do
      r[i] = get_ring_radius(tree_pt.kids[i])
    end
    local a = r[1]^2 + r[2]^2  -- a is proportional to the total ring area.
    radius = math.sqrt(a)
  end
  tree_pt.ring_radius  = radius
  tree_pt.ring_num_pts = num_pts
  tree_pt.ring_angle   = angle
  return radius, num_pts, angle
end

-- Returns `center`, `ray`, and a possibly adjusted `angle` for the tree_pt.
local function get_center_ray_and_angle(tree_pt, num_pts, angle)
  assert(tree_pt and num_pts and angle)

  --[[

  The easy cases here are the leaves, parent points, and the trunk.

  Leaves: the ring is a single point coinciding with the leaf point.

  Trunk and parents: the ring points all lie on a circle in a plane
    perpendicular to the point's stick. The trunk ring's center is exactly the
    trunk point, while other parent points have a ring center moved slightly
    downward to make more room for the bark around forks.

  --]]

  if tree_pt.kind == 'leaf' then
    return tree_pt.pt, Vec3:new(0, 0, 0), angle
  end

  local radius = get_ring_radius(tree_pt, num_pts, angle)

  if tree_pt.kind == 'parent' or tree_pt.parent == nil then
    local up = get_up_vec(tree_pt)
    local center
    if tree_pt.parent == nil then  -- The trunk.
      center = tree_pt.pt
    else
      center = tree_pt.pt - up * 0.05
    end
    local out    = up:orthogonal_dir()
    return center, radius * out, angle
  end

  --[[

  All that remains is the difficult case: child points.

  Every child point has a sibling. We want these two rings to share a single
  line segment that is orthogonal to both sibling's sticks. As above, each ring
  will be in a plane perpendicular to the child point's stick.

  Child points may request different radii. Because of the shared line segment,
  the actual values will be adjusted a bit. The shared line segment has the
  average length of the requested line parts for each sibling. The remaining
  ring points are evenly spaced around that shared line segment.

  Mathematically, it is not completely obvious how to derive all the needed
  values. Starting with the requested radii and

    alpha = the angle between the siblings' sticks,

  we must compute the distances from the branch point (tree_pt.pt)
  to the ring centers; we call these distances:

    to_self_r = distance from tree_pt.pt to our ring center,
    to_sib_r  = distance from tree_pt.pt to our sibling's ring center.

                     self_inner_r (aka r1)
                      A__________o mid_pt
                      |\__        \
                      |   ---___    \  sib_inner_r (aka r2)
                      |      b  ---___\
                      |               / B
           to_self_r  |             /
                      |           /
                      |         /  to_sib_r
                      |       /
                      |     /
                      |   /
                      | /
                      o tree_pt.pt

  The initial radii are out radii -- they give the distance from the ring center
  to individual ring points. In the above diagram, the radii are *inner* radii,
  meaning that they give the shortest distance from the ring center to the ring
  polygon that approximates a circle.

  The law of cosines gives us the length of b. The angles at points A and B are
  right = 90 degrees. So that quadrilateral is inscribed in a circle, and we can
  use a generalized law of sines to find the length from tree_pt.pt to mid_pt.
  Then we can use the Pythagorean theorem to find to_{self,sib}_r.

  The remaining math is less tricky, so I hope the code for it will be
  self-explanatory. I guess I'm assuming the reader has some intuition for 3d
  vectors. Sorry if that's not the case! This comment is already pretty long.

  Bye, thanks for reading!

  --]]

  -- We are in the 'child' point case.
  assert(tree_pt.kind == 'child')

  -- Find alpha, the angle between the two branch directions.
  local sibling     = get_sibling(tree_pt)
  local sib_radius  = get_ring_radius(sibling)
  local to_self_dir = get_up_vec(tree_pt):normalize()
  local to_sib_dir  = get_up_vec(sibling):normalize()
  local alpha       = math.acos(to_self_dir:dot(to_sib_dir))
  assert(alpha == alpha)  -- Check for nan.

  -- Find self_inner_r, sib_inner_r; these are inner radii.
  local part_len     = radius * 2 * math.sin(angle / 2)
  local self_inner_r = part_len / 2 / math.tan(angle / 2)
  local sib_radius, sib_num_pts, sib_angle = get_ring_radius(sibling)
  local sib_part_len = sib_radius * 2 * math.sin(sib_angle / 2)
  local sib_inner_r  = sib_part_len / 2 / math.tan(sib_angle / 2)

  -- Find to_self_r and to_sib_r, the distances to the ring centers.
  local r1, r2       = self_inner_r, sib_inner_r
  local b_squared    = r1^2 + r2^2 + 2 * r1 * r2 * math.cos(alpha)
  local sin_alpha_sq = math.sin(alpha)^2
  local to_self_r    = math.sqrt(b_squared / sin_alpha_sq - r1^2)
  local to_sib_r     = math.sqrt(b_squared / sin_alpha_sq - r2^2)

  -- Find center = our ring's center, and mid_pt, which is on both rings midway
  -- between ring1 and ring2 in each.
  local out = tree_pt.parent.out
  if tree_pt.parent.kids[2] == tree_pt then
    out = -1 * out
  end
  local center        = tree_pt.pt + to_self_r * to_self_dir
  local to_mid_pt_dir = to_self_dir:cross(out)
  local mid_pt        = center + self_inner_r * to_mid_pt_dir
  assert(not center:has_nan())
  assert(not mid_pt:has_nan())
  tree_pt.ring_meet_mid_pt = mid_pt

  -- This test could theoretically be skipped, but I feel better knowing that
  -- these values match up.
  local sib_center        = sibling.pt + to_sib_r * to_sib_dir
  local sib_to_mid_pt_dir = out:cross(to_sib_dir)
  local sib_mid_pt        = sib_center + sib_inner_r * sib_to_mid_pt_dir
  for i = 1, 3 do
    assert(math.abs(sib_mid_pt[i] - mid_pt[i]) < 0.001)
  end

  -- Find ring1, ring2, and adjusted_angle.
  -- The angle is adjusted since the shared line is avg_part_len long.
  local avg_part_len   = (part_len + sib_part_len) / 2
  local parent         = tree_pt.parent
  local big_angle      = 2 * math.atan2(avg_part_len / 2, self_inner_r)
  local adjusted_angle = (2 * math.pi - big_angle) / (num_pts - 1)
  local ring1          = mid_pt + out * (avg_part_len / 2)
  local ring2          = mid_pt - out * (avg_part_len / 2)
  tree_pt.ring         = {ring1}
  assert(not ring1:has_nan())
  assert(not ring2:has_nan())

  return center, ring2 - center, adjusted_angle
end

local function add_ring_to_pt(tree_pt)
  if tree_pt.kind == 'leaf' then               -- The leaf case.
    tree_pt.ring_center = tree_pt.pt
    tree_pt.ring = {tree_pt.pt}
  else                                         -- The trunk or branch cases.
    local num_pts     = get_num_pts(tree_pt)
                        assert(num_pts <= max_ring_pts)
    -- `angle` is the angle in radius between outgoing rays from the center.
    local angle       = 2 * math.pi / num_pts
    local up          = get_up_vec(tree_pt)
                        assert(getmetatable(up) == Vec3)
    -- `ray` is the vector of the first outgoing ray from the center.
    local center, ray, angle = get_center_ray_and_angle(tree_pt, num_pts, angle)
                               assert(getmetatable(center) == Vec3)
                               assert(getmetatable(ray) == Vec3)
    local R                  = Mat3:rotate(angle, up)

    tree_pt.ring_center = center
    tree_pt.ring = {}
    while #tree_pt.ring < num_pts do
      table.insert(tree_pt.ring, center + ray)
      ray = R * ray  -- Rotate the outgoing ray vector.
    end
    assert(#tree_pt.ring == num_pts)  -- TEMP
  end
end

local function debug_print_ring(tree_pt)
  print('')
  print('ring: ' .. dbg.val_to_str(tree_pt.ring))
  if tree_pt.kind == 'leaf' then
    print('leaf')
  else
    print('num_pts: ' .. tree_pt.ring_num_pts)
    print('radius:  ' .. tree_pt.ring_radius)
  end
end


-- Public functions.

function rings.add_rings(tree)
  -- Although branch points are represented 3 times in the tree table, we still
  -- want a separate ring for each one, as each branch point corresponds to 3
  -- rings.
  for _, tree_pt in pairs(tree) do
    add_ring_to_pt(tree_pt)

    assert(type(tree_pt.ring) == 'table' and #tree_pt.ring > 0)
    assert(tree_pt.kind == 'leaf' or tree_pt.ring_num_pts)
    assert(tree_pt.kind == 'leaf' or tree_pt.ring_radius)

    -- Uncomment this line to print some extra data for debugging.
    -- debug_print_ring(tree_pt)
  end
end

-- TEMP
print('max_ring_pts = ' .. max_ring_pts)


return rings

