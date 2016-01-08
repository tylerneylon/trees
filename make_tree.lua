--[[

make_tree.lua

A module to procedurally generate the skeleton and bark of a tree.

Here is the format of a tree table:

   tree[i] = {pt       = Vec3 {x, y, z},
              kind     = 'parent', 'child', or 'leaf',
              parent   = index of parent}

Nonterminal points have 3 entries in this table - one as the child of the stick
it ends, and two more as the parents of the outward sticks. Terminal points have
a single entry each.

--]]

local make_tree = {}


-- Requires.

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'


-- Internal globals.

-- It is expected that the following globals be set from C before this module is
-- loaded:
local missing_global_fmt = "Expected the %s global to be set from C."
local function check_global(name)
  assert(_G[name], missing_global_fmt:format(name))
end
check_global('max_tree_height')
check_global('branch_size_factor')

local do_dbg_print = false
local no_parent    = -1  -- This is a parent index value for the root.


-- Internal utility functions.

-- This returns a random float in the range [min, max).
local function uniform_rand(min, max)
  assert(max > min)
  return math.random() * (max - min) + min
end

local function val_near_avg(avg)
  return uniform_rand(avg * 0.85, avg * 1.15)
end

local function dbg_pr(...)
  if not do_dbg_print then return end
  print(string.format(...))
end

-- Internal skeleton-building functions.

local function add_line(tree, from, to, parent)
  assert(tree)
  assert(from)
  assert(to)
  assert(parent)
  assert(tree and from and to and parent)

  -- Add the from item.
  local new_item = { pt = from, kind = 'child', parent = parent }
  tree[#tree + 1] = new_item

  -- Ensure the parent is marked as a parent and not a leaf.
  if parent > 0 then tree[parent].kind = 'parent' end

  -- Add the to item.
  -- It starts as a leaf, and becomes a parent when a child is added to it.
  new_item = { pt = to, kind = 'leaf' }
  tree[#tree + 1] = new_item
end

local function add_to_tree(args, tree)
  assert(args.parent)
  assert(getmetatable(args.direction) == Vec3)
  tree = tree or {}

  args.direction:normalize()
  local len = val_near_avg(args.avg_len)
  add_line(tree, args.origin, args.origin + len * args.direction, args.parent)

  if len < args.min_len or args.max_recursion == 0 then
    return
  end

  local w1 = val_near_avg(0.5)
  local w2 = 1 - w1

  local subtree_args = {
    min_len       = args.min_len,
    max_recursion = args.max_recursion - 1
  }

  subtree_args.avg_len = args.avg_len * branch_size_factor
  subtree_args.origin  = args.origin + len * args.direction
  subtree_args.parent  = #tree

  -- TODO Basically, I think the angle-choosing code below is not very good.
  --      I think it gives poorly distributed angles. Improve.

  -- PLAN Try two approaches:
  --  1.  For each branch point, track a unit direction vector orthogonal to the
  --      plane of the branching. At the child branch points, choose a random
  --      new orthogonal direction that averages around 90 degrees off of the
  --      parent's orthogonal direction.
  --  2.  Pick the orth dir to be truly random, but discard things close enough
  --      to the current branch dir.
  --
  --  Here's a good way to choose a random unit vector in R³:
  --  http://math.stackexchange.com/a/44691/10785

  local split_angle = val_near_avg(0.55)  -- This is in radians.
  local turn_angle  = uniform_rand(0.0, 2 * math.pi)

  -- TODO Improve this part of the process. arbit_dir is too deterministic!
  -- Find other_dir orthogonal to direction.
  local dir = args.direction
  local arbit_dir
  -- Improve stability by ensuring arbit_dir is not near-dependent on direction.
  if dir[1] > dir[2] and dir[1] > dir[3] then
    arbit_dir = Vec3:new(0, 1, 0)
  else
    arbit_dir = Vec3:new(1, 0, 0)
  end
  local other_dir = dir:cross(arbit_dir)

  -- TEMP
  dbg_pr('turn_angle=' .. turn_angle)
  dbg_pr('args.direction=' .. args.direction:as_str())

  local turn = Mat3:rotate(turn_angle, args.direction)

  local dir1 = turn * Mat3:rotate( split_angle * w1, other_dir) * args.direction
  local dir2 = turn * Mat3:rotate(-split_angle * w2, other_dir) * args.direction

  subtree_args.direction = dir1
  add_to_tree(subtree_args, tree)

  subtree_args.direction = dir2
  add_to_tree(subtree_args, tree)

  return tree
end

-- Internal ring-building functions.

local function get_up_dir(tree_pt)
  -- TODO
end

local function get_ring_center(tree_pt, up)
  -- TODO
end

local function get_ring_data(tree_pt, up, center)
  -- TODO
end

local function add_ring_to_pt(tree_pt)

  if true then return false end  -- TEMP

  if tree_pt.kind == 'leaf' then               -- The leaf case.
    -- TODO Add a single point ring.
  elseif tree_pt.parent == no_parent then      -- The trunk case.
  else                                         -- The branch case.

    -- TODO How does num_pts work?

    local num_pts = 5

    -- TODO Drop the asserts below once this is further along.

    local up                 = get_up_dir(tree_pt)
    assert(getmetatable(up) == Vec3)
    local center             = get_ring_center(tree_pt, up)
    assert(getmetatable(center) == Vec3)
    -- `angle` is the angle in radius between outgoing rays from the center.
    -- `v` is the vector of the first outgoing ray from the center.
    local v, radius, angle = get_ring_data(tree_pt, up, center)
    assert(getmetatable(v) == Vec3)
    local R                = Mat3:rotate(angle, up)

    tree_pt.ring = {}
    for i = 1, num_pts do
      table.insert(tree_pt.ring, center + v)
      v = R * v  -- Rotate the outgoing ray vector v.
    end
  end
end

local function add_rings(tree)
  for _, tree_pt in pairs(tree) do
    add_ring_to_pt(tree_pt)
  end
end


-- Public functions.

function make_tree.make()

  local tree_add_params = {
    origin        = Vec3:new(0, 0, 0),
    direction     = Vec3:new(0, 1, 0),
    avg_len       = 0.5,
    min_len       = 0.01,
    parent        = no_parent,  -- This is a special index value for the root.
    max_recursion = max_tree_height
  }

  -- TEMP NOTE: The tree table can hold all the data previously held in
  --            tree_pts, tree_pt_info, and leaves. Non-top-level calls to
  --            add_to_tree can receive it as a second param.
  local tree = add_to_tree(tree_add_params)
  add_rings(tree)
  return tree
end


-- Initialization.

-- Seed random number generation.
math.randomseed(os.time())


return make_tree
