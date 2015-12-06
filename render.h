// render.h
//
// C header file for rendering hooks.
//
// The actual code is C++, but the functions
// declared here support C-style linking.
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif
  
  // Drawing functions.
  void render__init();
  void render__draw(int w, int h);
  
  // Input functions.
  void render__mouse_moved(int x, int y, double dx, double dy);
  void render__mouse_down(int x, int y);
  
#ifdef __cplusplus
}
#endif