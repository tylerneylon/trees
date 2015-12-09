--[[

make_tree.lua

A module to procedurally generate the skeleton and bark of a tree.

--]]

local make_tree = {}


-- Requires.

local Vec3 = require 'Vec3'


-- Internal globals.

local max_tree_height = 10


-- Internal functions.

-- This returns a random float in the range [min, max).
local function uniform_rand(min, max)
  assert(max > min)
  return math.random() * (max - min) + min
end

local function val_near_avg(avg)
  return uniform_rand(avg * 0.85, avg * 1.15)
end

local function add_line(from, to, parent_index)
  -- TODO HERE 1/2
end

local function add_to_tree(args, tree)
  tree = tree or {}
  args.direction:normalize()
  local len = val_near_avg(args.avg_len)
  add_line(args.origin, args.origin + len * args.direction, args.parent_index)

  -- TODO HERE 2/2
end

-- Public functions.

function make_tree.make()

  local tree_add_params = {
    origin          = Vec3:new(0, 0, 0),
    direction       = Vec3:new(0, 1, 0),
    weight          = 1.0,
    avg_len         = 0.5,
    min_len         = 0.01,
    root_index      = -1,
    max_tree_height = max_tree_height
  }

  -- TEMP NOTE: The tree table can hold all the data previously held in
  --            tree_pts, tree_pt_info, and leaves. Non-top-level calls to
  --            add_to_tree can receive it as a second param.
  tree = add_to_tree(tree_add_params)

  -- Eventually:
  -- add_rings()
end


return make_tree
