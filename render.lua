--[[

render.lua

A master module to initiate tree generation and rendering.

--]]

local render = {}


-- Requires.

-- Expected to be preloaded:
--  lines

local make_tree = require 'make_tree'


-- Internal globals.

local tree = false


-- Internal functions.

local function setup_lines()
  lines.set_scale(1.0)

  for i = 1, #tree, 2 do
    assert(type(tree[i].pt) == 'table' and #tree[i].pt == 3)
    assert(type(tree[i + 1].pt) == 'table' and #tree[i + 1].pt == 3)
    lines.add(tree[i].pt, tree[i + 1].pt)
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
  -- TODO HERE
end


return render
