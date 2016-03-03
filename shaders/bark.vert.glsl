#version 330 core

layout(location = 0) in vec3 vPosition;
layout(location = 1) in vec3 triColorIn;
layout(location = 2) in vec3 normalIn;

flat out vec3 triColorOut;
flat out vec3 normal;

uniform mat4 mvp;
uniform mat3 normal_xform;
uniform vec3 color;

void main() {
  gl_Position = mvp * vec4(vPosition, 1);
  triColorOut = triColorIn;
  triColorOut = vec3(0.494, 0.349, 0.204);
  triColorOut = color;
  normal      = normal_xform * normalIn;
}
