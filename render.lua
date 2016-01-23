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


-- Public methods.

-- This is expected to be called once at program startup.
function render.init()
  tree = make_tree.make()
  setup_lines()
end

-- This is expected to be called once per render cycle.
function render.draw()
  lines.draw_all()
end


return render
