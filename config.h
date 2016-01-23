//
//  config.h
//  Trees
//
//  A single place to keep all major configuration parameters.
//
//  Some of these constants are visible from Lua thanks to the
//  set_lua_config_constants function in luarender.cc file.
//

// This controls whether or not the rendering is controlled by the Lua scripts.
// The value is expected to be YES or NO.
#define    do_use_lua         YES

// If this is YES, tree generation is restricted to 2D. This project overall is
// focused on the 3d case, and the 2d case exists as a way to explore a
// simplified version of the algorithms used.
#define    is_tree_2d         NO

#define    max_tree_height    10

// This modifies the view transform by effectively zooming toward or away from
// the tree.
#define    zoom_scale         2.3

#define    branch_size_factor 0.79
#define    max_ring_pts       8

#define    do_draw_rings      YES

// TODO Make do_draw_rings effective in the C code.
