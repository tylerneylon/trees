--[[

make_tree.lua

A module to procedurally generate the skeleton and bark of a tree.

Here is the format of a tree table:

   tree[i] = {
              pt       = Vec3 {x, y, z},
              kind     = 'parent', 'child', or 'leaf',
              parent   = parent_item,

              -- Parent items also have:
              kids     = {child_item1, child_item2},
              down     = downward_item (downward = trunkward),
              out      = Vec3 outward direction,

              -- Child items also have:
              up       = upward_item (upward = leafward)
             }

Nonterminal points have 3 entries in this table - one as the child of the stick
it ends, and two more as the parents of the outward sticks. Terminal points have
a single entry each.

--]]

local make_tree = {}


-- Requires.

local rings = require 'rings'

local Mat3  = require 'Mat3'
local Vec3  = require 'Vec3'


-- Internal globals.

-- It is expected that the following globals be set from C before this module is
-- loaded:
local missing_global_fmt = "Expected the %s global to be set from C."
local function check_global(name)
  assert(_G[name], missing_global_fmt:format(name))
end
check_global('max_tree_height')
check_global('branch_size_factor')
check_global('max_ring_pts')

local do_dbg_print = false


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
  assert(from and getmetatable(from) == Vec3)
  assert(to   and getmetatable(to)   == Vec3)
  assert(parent == nil or type(parent) == 'table')

  -- Add the from item.
  local from_item = { pt = from, kind = 'child', parent = parent }
  tree[#tree + 1] = from_item

  -- Ensure the parent is marked as a parent and not a leaf.
  if parent then
    parent.kind = 'parent'
    if parent.kids == nil then parent.kids = {} end
    table.insert(parent.kids, from_item)
  end

  -- Add the to item.
  -- It starts as a leaf, and becomes a parent when a child is added to it.
  local to_item = { pt = to, kind = 'leaf' }
  tree[#tree + 1] = to_item

  from_item.up = to_item
  to_item.down = from_item
end

local function add_to_tree(args, tree)
  -- We expect to have a parent unless this is the top-level call, in which case
  -- we expect to have no tree and no parent.
  assert((args.parent and tree) or (tree == nil and args.parent == nil))
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
  subtree_args.parent  = tree[#tree]

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
  local out_dir = dir:cross(arbit_dir):normalize()

  -- TEMP
  dbg_pr('turn_angle=' .. turn_angle)
  dbg_pr('args.direction=' .. args.direction:as_str())

  out_dir = Mat3:rotate(turn_angle, args.direction) * out_dir

  local dir1 = Mat3:rotate( split_angle * w1, out_dir) * args.direction
  local dir2 = Mat3:rotate(-split_angle * w2, out_dir) * args.direction
  tree[#tree].out = out_dir

  subtree_args.direction = dir1
  add_to_tree(subtree_args, tree)

  subtree_args.direction = dir2
  add_to_tree(subtree_args, tree)

  return tree
end


-- Public functions.

function make_tree.make()

  local tree_add_params = {
    origin        = Vec3:new(0, 0, 0),
    direction     = Vec3:new(0, 1, 0),
    avg_len       = 0.5,
    min_len       = 0.01,
    max_recursion = max_tree_height
  }

  -- TEMP NOTE: The tree table can hold all the data previously held in
  --            tree_pts, tree_pt_info, and leaves. Non-top-level calls to
  --            add_to_tree can receive it as a second param.
  local tree = add_to_tree(tree_add_params)
  rings.add_rings(tree)
  return tree
end


-- Initialization.

-- Seed random number generation.
math.randomseed(os.time())


return make_tree
