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
  if tree.bark == nil then tree.bark = {} end
  if tree.bark.pts == nil then tree.bark.pts = {} end
  local bark_pts = tree.bark.pts

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

      -- Set up the triangles.
      for i = 0, #tree_pt.ring - 1 do
        -- Triangle 1.
        append(bark_pts, up_pt.ring[add_mod(up_start, i, #up_pt.ring)])
        append(bark_pts, tree_pt.ring[i % #tree_pt.ring + 1])
        append(bark_pts, up_pt.ring[add_mod(up_start, i + 1, #up_pt.ring)])

        -- Triangle 2.
        append(bark_pts, up_pt.ring[add_mod(up_start, i + 1, #up_pt.ring)])
        append(bark_pts, tree_pt.ring[i % #tree_pt.ring + 1])
        append(bark_pts, tree_pt.ring[(i + 1) % #tree_pt.ring + 1])
      end

      --[[
      -- Set up the triangle strip.
      local num_pairs = #tree_pt.ring + 1
      local bark_pts = {}  -- A flat sequence of bark points.
      for i = 0, num_pairs - 1 do
        append(bark_pts, up_pt.ring[add_mod(up_start, i, #up_pt.ring)])
        append(bark_pts, tree_pt.ring[i % #tree_pt.ring + 1])
      end
      assert(#bark_pts == 3 * 2 * num_pairs)  -- They're pairs of triples.

      tree_pt.stick_bark = VertexArray:new(bark_pts, 'triangle strip')
      --]]
    end
  end
end

local function add_joint_piece(tree, tree_pt,
                               top_pts, top_first, top_last,
                               bot_pts, bot_first, bot_last)

  if tree.bark == nil then tree.bark = {} end
  if tree.bark.pts == nil then tree.bark.pts = {} end
  local bark_pts = tree.bark.pts

  -- TODO NEXT Implement.
end

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

      -- Set up bot_pts to have the points of tree_pt.ring, but with a
      -- carefully-chosen first point.
      local mid_pt = tree_pt.kids[1].ring_meet_mid_pt
      local bot_idx = {}
      for i = 1, 2 do
        local top_ray = tree_pt.kids[i].ring[2] - mid_pt
        local best_dot, bot_start = -math.huge, nil
        for i = 1, #tree_pt.ring do
          local bot_ray = tree_pt.ring[i] - tree_pt.ring_center
          local d = bot_ray:dot(top_ray)
          if d > best_dot then
            best_dot, bot_start = d, i
          end
        end
        bot_idx[i] = bot_start
      end
      local bot_pts = {}
      local num_pts = #tree_pt.ring
      for i = bot_idx[1], bot_idx[1] + num_pts - 1 do
        bot_pts[#bot_pts + 1] = tree_pt.ring[(i - 1) % num_pts + 1]
      end

      -- The letter k indicates the halfway-around index within {top,bot}_pts.
      local bot_k = (bot_idx[2] - bot_idx[1]) % num_pts + 1
      local top_k = #tree_pt.kids[1].ring

      -- Augment both top_pts and bot_pts with a repeat of their first point.
      top_pts[#top_pts + 1] = top_pts[1]
      bot_pts[#bot_pts + 1] = bot_pts[1]

      -- Add triangles in two pieces: one for each of the top rings.
      local k = #tree_pt.kids[1].ring
      add_joint_piece(tree, tree_pt, top_pts, 1, top_k, bot_pts, 1, bot_k)
      add_joint_piece(tree, tree_pt,
                      top_pts, top_k, #top_pts,
                      bot_pts, bot_k, #bot_pts)
    end
  end
end

-- TODO Consider removing this.
local function old_add_joint_bark(tree)
  if tree.bark == nil then tree.bark = {} end
  if tree.bark.pts == nil then tree.bark.pts = {} end
  local bark_pts = tree.bark.pts

  for _, tree_pt in pairs(tree) do
    if tree_pt.kind == 'parent' then

      -- Set up top_pts with the combined points of the top rings.
      local top_pts = {}
      for _, kid in ipairs(tree_pt.kids) do
        for i = 2, #kid.ring do
          table.insert(top_pts, kid.ring[i])
        end
      end

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

      -- Augment both top_pts and bot_pts with a repeat of their first point.
      top_pts[#top_pts + 1] = top_pts[1]
      bot_pts[#bot_pts + 1] = bot_pts[1]

      -- Add triangles until we've covered the joint.
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

      -- tree_pt.joint_bark = VertexArray:new(bark_pts, 'triangles')
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
  tree.bark.v_array = VertexArray:new(tree.bark.pts, 'triangles')
end


return bark
