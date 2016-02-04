--[[

bark.lua

A module to add bark to a tree skeleton.
It is expected that the tree skeleton will
already have rings.

--]]


local bark = {}


-- Internal functions.

local function add_stick_bark(tree)
  for _, tree_pt in pairs(tree) do
    if tree_pt.kind == 'child' then
      -- TODO Implement. Start:
      --      When may we have a differing number of ring points?
      --      How to handle those cases?
      --      Also need to think carefully about start points.
    end
  end
end

local function add_joint_bark(tree)
  -- TODO Implement.
end


-- Public functions.

function bark.add_bark(tree)
  -- Sanity check.
  for _, tree_pt in pairs(tree) do
    assert(tree_pt.ring, 'Expected that all tree pts would have a ring.')
  end

  -- Add the bark.
  add_stick_bark(tree)
  add_joint_bark(tree)
end


return bark
