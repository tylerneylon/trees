#include "glhelp.h"

#include "file.h"

#include <OpenGL/gl3.h>

#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>

#define true  1
#define false 0

void glhelp__error_check_(const char *file, int line, const char *func) {
  GLenum err;
  while ((err = glGetError()) != GL_NO_ERROR) printf("%s:%d (%s) OpenGL error: 0x%04X\n", basename((char *)file), line, func, err);
}

int load_shader(const char *filename, GLenum shader_type, GLuint program) {
  
  // Read in the file contents.
  char *path = file__get_path(filename);
  
  // TODO Use file__contents here.
  
  FILE *f = fopen(path, "r");  // TODO Will have to update this bit to be cross-platform (e.g. "rb" etc).
  fseek(f, 0, SEEK_END);
  GLint file_size = (GLint)ftell(f);  // OpenGL will expect a GLint type for this value.
  fseek(f, 0, SEEK_SET);
  char *file_contents = malloc(file_size + 1);
  fread(file_contents, 1, file_size, f);
  file_contents[file_size] = '\0';
  fclose(f);
  
  // Set up the shader.
  GLuint shader = glCreateShader(shader_type);
  glShaderSource(shader, 1 /* count */, (char const * const *)&file_contents, &file_size);
  glCompileShader(shader);
  
  GLint log_length;
  glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &log_length);
  if (log_length > 1) {
    GLchar *log = malloc(log_length + 1);
    glGetShaderInfoLog(shader, log_length, &log_length, log);
    printf("Shader compile log:\n%s\n", log);
  }
  
  // TODO If we check the log, do we still need to check the compiled flag?
  GLint compiled;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (!compiled) {
    const char *shader_type_name = "unknown";
    if (shader_type == GL_VERTEX_SHADER)   shader_type_name = "vertex";
    if (shader_type == GL_FRAGMENT_SHADER) shader_type_name = "fragment";
    printf("Shader didn't compile; type=%s.\n", shader_type_name);
    return false;
  }
  
  glAttachShader(program, shader);
  
  return true;
}

GLuint glhelp__load_program(const char *v_shader_file, const char *f_shader_file) {
  GLuint program = glCreateProgram();
  if (program == 0) {
    printf("Error from glCreateProgram.\n");
    return 0;
  }
  
  if (!load_shader(v_shader_file, GL_VERTEX_SHADER, program)) return 0;
  if (!load_shader(f_shader_file, GL_FRAGMENT_SHADER, program)) return 0;
  
  // Link the program object.
  glLinkProgram(program);
  GLint linked;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  if (!linked) {
    printf("Program didn't link.\n");
    return 0;
  }
  
  glUseProgram(program);
  return program;
}
