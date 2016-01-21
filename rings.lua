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
  if tree_pt.kind == 'child' then
    assert(tree_pt.up and tree_pt.up.kind)

    -- TODO NEXT This is happening. Write an integrity check that can see this
    --           issue and then isolate when in the code things are going wrong.
    if getmetatable(tree_pt.up.pt) ~= Vec3 then
      print('tree_pt.up:')
      dbg.pr_val(tree_pt.up)
      os.exit(1)
    end
    
    assert(getmetatable(tree_pt.up.pt) == Vec3)
    assert(getmetatable(tree_pt.pt) == Vec3)
    local a = tree_pt.up.pt - tree_pt.pt
    assert(getmetatable(a) == Vec3)
    return tree_pt.up.pt - tree_pt.pt
  else
    assert(tree_pt.down and tree_pt.down.kind)
    assert(getmetatable(tree_pt.pt) == Vec3)
    assert(getmetatable(tree_pt.down.pt) == Vec3)
    local a = tree_pt.pt - tree_pt.down.pt
    assert(getmetatable(a) == Vec3)
    return tree_pt.pt - tree_pt.down.pt
  end
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
  if tree_pt.ring_radius then return tree_pt.ring_radius end

  if num_pts == nil then
    num_pts = get_num_pts(tree_pt)
    angle   = 2 * math.pi / num_pts
  end

  local radius
  if tree_pt.kind == 'leaf' then
    radius = 0
  elseif tree_pt.kind == 'child' then
    local up = get_up_vec(tree_pt)
    local part_len = 0.7 * up:length() / num_pts
    radius = part_len / 2 / math.sin(angle / 2)
  else
    assert(tree_pt.kind == 'parent')
    local up_radius = 0.5 * get_ring_radius(tree_pt.kids[1]) +
                      0.5 * get_ring_radius(tree_pt.kids[2])
    local down_radius = get_ring_radius(tree_pt.down)
    radius = 0.9 * up_radius + 0.1 * down_radius
  end
  tree_pt.ring_radius = radius
  return radius
end

-- Returns `center`, `ray` for the given tree_pt.
local function get_ring_center_and_ray(tree_pt, num_pts, angle)

  if tree_pt.kind == 'leaf' then
    return tree_pt.pt, Vec3:new(0, 0, 0)
  end

  local radius = get_ring_radius(tree_pt, num_pts, angle)

  if tree_pt.kind == 'parent' or tree_pt.parent == nil then
    local up = get_up_vec(tree_pt)
    local center
    if tree_pt.parent == nil then
      center = tree_pt.pt
    else
      center = tree_pt.pt - up * 0.05
    end
    local out    = up:orthogonal_dir()
    return center, radius * out
  end

  --[[

      Mathematcal values used here:

      The two outgoing branches have angle `alpha` between them.

      Set the variable
        y = distnace from tree_pt.pt to each ring center along the branches,
      and
        x = the distance from tree_pt.pt to the shared ring part.
  
      Each ring part, opposite the ring center, forms an isosceles corner. The
      circumference side has length part_len. The radial sides have length
        r_o = outer radius,
      while the shortest distance from the center to ring part is called
        r_i = inner radius.

  --]]

  assert(tree_pt.kind == 'child')

  -- Find alpha.
  local sibling     = get_sibling(tree_pt)
  local to_self_dir = get_up_vec(tree_pt):normalize()
  local to_sib_dir  = get_up_vec(sibling):normalize()
  local alpha       = math.acos(to_self_dir:dot(to_sib_dir))
  assert(alpha == alpha)  -- Check for nan.

  -- Find r_i, r_o, part_len, x, and y.
  local r_o      = radius
  local part_len = r_o * 2 * math.sin(angle / 2)
  local r_i      = part_len / 2 / math.tan(angle / 2)
  local x        = r_i / math.sin(alpha / 2)
  local y        = r_i / math.tan(alpha / 2)
  assert(x == x and y == y and r_i == r_i and part_len == part_len and r_o == r_o)  -- TEMP TODO fix line len
  -- r_i, r_o, and (part_len / 2) are the side lengths of a right triangle.
  assert(math.abs(r_o ^ 2 - (part_len / 2) ^ 2 - r_i ^ 2) < 0.0001)

  -- Find center and mid_pt. `mid_pt` is on the ring between ring1 and ring2.
  local center     = tree_pt.pt + y * to_self_dir
  local to_mid_dir = (to_self_dir + to_sib_dir):normalize()
  local mid_pt     = tree_pt.pt + x * to_mid_dir

  assert(not center:has_nan())
  assert(not to_mid_dir:has_nan())
  assert(not mid_pt:has_nan())

  -- Find ring1.
  local ring1
  local parent = tree_pt.parent
  if parent.kids[1] == tree_pt then
    ring1 = mid_pt + parent.out * (part_len / 2)
  else
    ring1 = mid_pt - parent.out * (part_len / 2)
  end

  assert(not ring1:has_nan())

  return center, ring1 - center
end

local function add_ring_to_pt(tree_pt)
  if tree_pt.kind == 'leaf' then               -- The leaf case.
    tree_pt.ring_center = tree_pt.pt
    tree_pt.ring = {tree_pt.pt}
  else                                         -- The trunk or branch cases.
    -- TODO Drop the asserts below once this is further along.
    local num_pts = get_num_pts(tree_pt)
                    assert(num_pts <= max_ring_pts)
    -- `angle` is the angle in radius between outgoing rays from the center.
    local angle       = 2 * math.pi / num_pts
    local up          = get_up_vec(tree_pt)
                        assert(getmetatable(up) == Vec3)
    -- `ray` is the vector of the first outgoing ray from the center.
    local center, ray = get_ring_center_and_ray(tree_pt, num_pts, angle)
                        assert(getmetatable(center) == Vec3)
                        assert(getmetatable(ray) == Vec3)
    local R           = Mat3:rotate(angle, up)

    tree_pt.ring_center = center
    tree_pt.ring = {}
    for i = 1, num_pts do
      table.insert(tree_pt.ring, center + ray)
      ray = R * ray  -- Rotate the outgoing ray vector.
    end
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

