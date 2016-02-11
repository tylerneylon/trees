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
      local up_pt = tree_pt.up
      assert(#tree_pt.ring == #up_pt.ring or up_pt.kind == 'leaf')

      -- Find out which point to start with in the top ring.
      local ray = tree_pt.ring[1] - tree_pt.ring_center
      local up  = up_pt.pt - tree_pt.pt
      local out = ray:cross(up)
      -- We want the first top-ring point that's clockwise - when looking down -
      -- from our ray. A clockwise top_ray will have top_ray:dot(out) >= 0.
      local up_start               -- This will be the first index in up.ring.
      local best_dot = -math.huge  -- We'll maximize up_ray:dot(ray).
      for i = 1, #up_pt.ring do
        local top_ray = up_pt.ring[i] - up_pt.ring_center
        local d = top_ray:dot(ray)
        if top_ray:dot(out) >= 0 and d > best_dot then
          best_dot, up_start = d, i
        end
      end
      assert(best_dot >= 0)
      assert(up_start)

      -- Set up the triangle strip.
      local num_pairs = #tree_pt.ring + 1
      local bark_pts = {}  -- A flat sequence of bark points.
      for i = 0, num_pairs - 1 do
        append(bark_pts, up_pt.ring[add_mod(up_start, i, #up_pt.ring)])
        append(bark_pts, tree_pt.ring[i % #tree_pt.ring + 1])
      end
      assert(#bark_pts == 3 * 2 * num_pairs)  -- They're pairs of triples.

      tree_pt.stick_bark = VertexArray:new(bark_pts)
    end
  end
end

-- TODO Enable us to specify the drawing mode for a vertex array at the same
--      time that we provide the point data.

local function add_joint_bark(tree)
  for _, tree_pt in pairs(tree) do
    if tree_pt.kind == 'parent' then

      -- Set up top_pts with the combined points of the top rings.
      local top_pts = {}
      for _, kid in ipairs(tree_pt.kids) do
        for i = 2, #kid.ring do
          table.insert(top_pts, kid.ring[i])
        end
      end

      -- TODO Consider factoring out some code between what's next and
      --      add_stick_bark.

      -- Set up bot_pts to have the points of tree_pt.ring, but with a
      -- carefully-chosen first point.
      local top_ray = tree_pt.kids[1].ring[2] - tree_pt.kids[1].ring_meet_mid_pt
      local best_dot, bot_start = -math.huge, nil
      for i = 1, #tree_pt.ring do
        local bot_ray = tree_pt.ring[i] - tree_pt.ring_center
        local d = bot_ray:dot(top_ray)
        if d > best_dot then
          best_dot, bot_start = d, i
        end
      end
      local bot_pts, num_pts = {}, #tree_pt.ring
      for i = bot_start, bot_start + num_pts - 1 do
        bot_pts[#bot_pts + 1] = tree_pt.ring[(i - 1) % num_pts + 1]
      end

      -- Add triangles until we've covered the joint.
      local bark_pts = {}
      local top_idx, bot_idx = 1, 1
      repeat

        -- Add the first two points of the next triangle.
        append(bark_pts, top_pts[top_idx])
        append(bark_pts, bot_pts[bot_idx])

        -- Determine which index to increment.
        local top_next, bot_next = top_idx / #top_pts, bot_idx / #bot_pts

        -- Increment an index and add the third triangle point.
        if top_next < bot_next then
          top_idx = top_idx + 1
          assert(top_idx <= #top_pts)
          append(bark_pts, top_pts[top_idx])
        else
          bot_idx = bot_idx + 1
          assert(bot_idx <= #bot_pts)
          append(bark_pts, bot_pts[bot_idx])
        end
      until top_idx == #top_pts and bot_idx == #bot_pts

      -- TODO NEXT There are a few issues:
      --           1. There appear to be missing triangles. Debug.
      --           2. The normals are being computed as if this were a triangle
      --              strip, which is wrong. That needs a fix mainly within
      --              VertexArray itself.
      --           3. Rendering is inefficient in that it makes many more gl
      --              calls than necessary - likewise for triangle strips; fix.
      tree_pt.joint_bark = VertexArray:new(bark_pts)
    end
  end
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
