// glhelp.h
//
// Tools for more easily working with OpenGL.
//

#pragma once

#import <OpenGL/OpenGL.h>

// Check for any OpenGL errors up until this point. Call this like so:
//   glhelp__error_check;  // Nothing else needed; don't use parentheses.
#define glhelp__error_check glhelp__error_check_(__FILE__, __LINE__, __func__)

// A zero return value indicates an error; if an error occurs, a message will
// be printed before this returns.
GLuint glhelp__load_program(const char *v_shader_file, const char *f_shader_file);

// Implementation of the glhelp__error_check macro.
void glhelp__error_check_(const char *file, int line, const char *func);
