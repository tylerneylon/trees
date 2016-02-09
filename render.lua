--[[

render.lua

A master module to initiate tree generation and rendering.

--]]

local render = {}


-- Requires.

-- Expected to be preloaded:
--  lines

local make_tree
if is_tree_2d then
  make_tree = require 'make_tree_2d'
else
  make_tree = require 'make_tree'
end


-- Internal globals.

local tree = false


-- Internal functions.

local function setup_lines()
  lines.set_scale(1.0)

  -- Draw trunk and branch lines.
  for i = 1, #tree, 2 do
    assert(type(tree[i].pt) == 'table' and #tree[i].pt == 3)
    assert(type(tree[i + 1].pt) == 'table' and #tree[i + 1].pt == 3)
    lines.add(tree[i].pt, tree[i + 1].pt)
  end

  if do_draw_rings then
    -- Draw the rings.
    for _, tree_pt in pairs(tree) do
      local r = tree_pt.ring
      for i = 1, #r do
        lines.add(r[i], r[i % #r + 1])
      end
    end
  end
end

-- These next two functions are not meant to be called during normal use.
-- They're here as a way to help test/debug the TriangleStrip class.

local function test_triangles_init()
  strip = TriangleStrip:new({0,   0, 0,
                             1,   0, 0,
                             0.5, 0, 1,
                             0.5, 1, 0.5,
                             0,   0, 0,
                             1,   0, 0})
end

local function test_triangles_draw()
  strip:draw()
end


-- Public methods.

-- This is expected to be called once at program startup.
function render.init()
  tree = make_tree.make()
  setup_lines()
end

-- This is expected to be called once per render cycle.
function render.draw()
  lines.draw_all()

  for _, tree_pt in pairs(tree) do
    -- TODO When bark generation is done, assert that every non-leaf point has
    --      a bark_strip.
    if tree_pt.bark_strip then
      tree_pt.bark_strip:draw('triangle strip')
    end
  end
end


return render
