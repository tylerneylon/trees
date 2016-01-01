--[[

make_tree.lua

A module to procedurally generate the skeleton and bark of a tree.

--]]

local make_tree = {}


-- Requires.

local Mat3 = require 'Mat3'
local Vec3 = require 'Vec3'


-- Internal globals.

local max_tree_height    = 10
local branch_size_factor = 0.79
local do_dbg_print       = false


-- Internal functions.

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

-- TEMP NOTES
-- Mabye the format of a tree can be:
-- tree[i] = {pt       = {x, y, z},
--            kind     = 'parent', 'child', or 'leaf',
--            parent   = index of parent}

-- parent = index of parent
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

local function add_to_tree(args, tree, max_recursion)
  tree = tree or {}
  max_recursion = max_recursion or args.max_recursion

  args.direction:normalize()
  local len = val_near_avg(args.avg_len)
  assert(args.parent) -- TEMP
  add_line(tree, args.origin, args.origin + len * args.direction, args.parent)

  if len < args.min_len or max_recursion == 0 then
    -- TODO Do we need a leaves list? Leaving out for now.
    return
  end

  local w1 = val_near_avg(0.5)
  local w2 = 1 - w1

  local avg_len = args.avg_len * branch_size_factor
  local origin  = args.origin + len * args.direction

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
  assert(getmetatable(args.direction) == Vec3)

  local turn = Mat3:rotate(turn_angle, args.direction)

  local dir1 = turn * Mat3:rotate( split_angle * w1, other_dir) * args.direction
  local dir2 = turn * Mat3:rotate(-split_angle * w2, other_dir) * args.direction

  local parent = #tree

  args.direction = dir1
  args.parent = parent
  add_to_tree(args, tree, max_recursion - 1)

  args.direction = dir2
  args.parent = parent
  add_to_tree(args, tree, max_recursion - 1)

  return tree
end

-- Public functions.

function make_tree.make()

  local tree_add_params = {
    origin        = Vec3:new(0, 0, 0),
    direction     = Vec3:new(0, 1, 0),
    weight        = 1.0,
    avg_len       = 0.5,
    min_len       = 0.01,
    parent        = -1,      -- TODO Add clarifying comment.
    max_recursion = max_tree_height
  }

  -- TEMP NOTE: The tree table can hold all the data previously held in
  --            tree_pts, tree_pt_info, and leaves. Non-top-level calls to
  --            add_to_tree can receive it as a second param.
  return add_to_tree(tree_add_params)

  -- Eventually:
  -- add_rings()
end


return make_tree
