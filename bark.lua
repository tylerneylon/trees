--[[

bark.lua

A module to add bark to a tree skeleton.
It is expected that the tree skeleton will
already have rings.

--]]


local bark = {}


-- Internal functions.

-- This expects two sequence tables in `t` and `suffix.
-- It appends the contents of `suffix` to the end of `t`.
local function append(t, suffix)
  for _, val in ipairs(suffix) do
    table.insert(t, val)
  end
end

-- This returns x + y mod m, except that the value 0 is returned as m.
-- This is useful for 1-indexed things - like Lua sequences!
local function add_mod(x, y, m)
  return (x + y - 1) % m + 1
end

local function add_stick_bark(tree)
  for _, tree_pt in pairs(tree) do
    if tree_pt.kind == 'child' then
      -- The two rings will have the same number of points except when the
      -- upward tree point is a leaf.
      local up = tree_pt.up
      assert(#tree_pt.ring == #up.ring or up.kind == 'leaf')

      -- Find out which point to start with in the top ring.
      local ray = tree_pt.ring[1] - tree_pt.ring_center
      local up_start               -- This will be the first index in up.ring.
      local best_dot = -math.huge  -- We'll maximize up_ray:dot(ray).
      for i = 1, #up.ring do
        local up_ray = up.ring[i] - up.ring_center
        local d = up_ray:dot(ray)
        if d > best_dot then
          best_dot, up_start = d, i
        end
      end
      assert(best_dot >= 0)
      assert(up_start)

      -- Set up the triangle strip.
      local num_pairs = #tree_pt.ring + 1
      local bark_pts = {}  -- A flat sequence of bark points.
      for i = 0, num_pairs - 1 do
        append(bark_pts, up.ring[add_mod(up_start, i, #up.ring)])
        append(bark_pts, tree_pt.ring[i % #tree_pt.ring + 1])
      end
      assert(#bark_pts = 3 * 2 * num_pairs)  -- They're pairs of triples.

      -- TODO Finish and debug.
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
