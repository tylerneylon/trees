--[[

make_tree.lua

A module to procedurally generate the skeleton and bark of a tree.

Here is the format of a tree table:

   tree[i] = {
              pt       = Vec3 {x, y, z},
              kind     = 'parent', 'child', or 'leaf',

              -- Parent items also have:
              kids     = {child_item1, child_item2},
              down     = downward_item (downward = trunkward),
              out      = Vec3 outward direction,

              -- Child items also have:
              parent   = parent_item,
              up       = upward_item (upward = leafward)
             }

Nonterminal points have 3 entries in this table - one as the child of the stick
it ends, and two more as the parents of the outward sticks. Terminal points have
a single entry each; this means the trunk point and all leaf points. The trunk
point has kind == 'child', which is consistent with it being the bottom point of
a stick in the tree skeleton. All top points are 'leaf' or 'parent' points and
all bottom points are 'child' points.

--]]

local make_tree = {}


-- Requires.

local bark       = require 'bark'
local leaf_globs = require 'leaf_globs'
local rings      = require 'rings'

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

-- This expects two sequence tables in `t` and `suffix.
-- It appends the contents of `suffix` to the end of `t`.
local function append(t, suffix)
  for _, val in ipairs(suffix) do
    table.insert(t, val)
  end
end

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
  assert(getmetatable(from) == Vec3)
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
    avg_len       = args.avg_len * branch_size_factor,
    origin        = args.origin + len * args.direction,
    parent        = tree[#tree],
    max_recursion = args.max_recursion - 1,
    min_recursion = args.min_recursion - 1
  }

  -- Allow early cutoffs based on min_recursion.
  if args.min_recursion <= 0 and math.random() < 0.3 then
    return
  end

  -- It's not obvious that the code below does a good job choosing random branch
  -- directions. The seemingly weak point is that arbit_dir and the first value
  -- of out_dir are not truly random. However, once out_dir is rotated by
  -- turn_angle, it is at least pseudorandom.
  --
  -- In investigating alternative designs here, I came across this method of
  -- choosing a random unit vector in R³, which may be useful in the future:
  --
  --     http://math.stackexchange.com/a/44691/10785

  local split_angle = val_near_avg(0.55)  -- This is in radians.
  local turn_angle  = uniform_rand(0.0, 2 * math.pi)

  if args.max_recursion % 2 ~= 0 then
    turn_angle = math.pi / 2
  else
    turn_angle = 0
  end
  turn_angle = turn_angle + uniform_rand(-0.7, 0.7)

  -- Find out_dir orthogonal to direction.
  local out_dir = args.out
  if out_dir == nil then
    local dir = args.direction
    local arbit_dir
    -- Improve stability by ensuring arbit_dir is not near-dependent on direction.
    if math.abs(dir[1]) > math.abs(dir[2]) then
      arbit_dir = Vec3:new(0, 1, 0)
    else
      arbit_dir = Vec3:new(1, 0, 0)
    end
    out_dir = dir:cross(arbit_dir):normalize()
  end

  out_dir = Mat3:rotate(turn_angle, args.direction) * out_dir

  local dir1 = Mat3:rotate( split_angle * w1, out_dir) * args.direction
  assert(not dir1:has_nan())
  local dir2 = Mat3:rotate(-split_angle * w2, out_dir) * args.direction
  assert(not dir2:has_nan())

  subtree_args.out = out_dir
  tree[#tree].out  = out_dir

  -- Maintain a flat array of vertex positions for lines to illustrate the out
  -- directions at each branching point.
  if tree.out_dir_pts == nil then tree.out_dir_pts = {} end
  append(tree.out_dir_pts, tree[#tree].pt)
  append(tree.out_dir_pts, tree[#tree].pt + out_dir * 0.1)

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
    max_recursion = max_tree_height,
    min_recursion = min_tree_height
  }

  -- TEMP NOTE: The tree table can hold all the data previously held in
  --            tree_pts, tree_pt_info, and leaves. Non-top-level calls to
  --            add_to_tree can receive it as a second param.
  local tree = add_to_tree(tree_add_params)
  rings.add_rings(tree)
  bark.add_bark(tree)
  -- TEMP
  leaf_globs.add_leaves(tree)

  print('Lua: num_pts=' .. #tree)

  return tree
end


-- Initialization.

-- Seed random number generation.
-- TEMP
local seed = os.time()
print('random seed = ' .. seed)
math.randomseed(seed)
--math.randomseed(9)  


return make_tree
