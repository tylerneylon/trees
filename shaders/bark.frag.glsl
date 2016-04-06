#version 330 core

out vec4 out_color;

flat in vec3 triColorOut;
flat in vec3 normal;

void main() {
  
  vec3 light_dir = normalize(vec3(1, 2, 2));
  
  out_color = vec4(triColorOut, 1.0);
  
  //float mult = (clamp(dot(normal, light_dir), 0.3, 1));
  
  float mult = dot(normal, light_dir) * 0.5 + 0.5;
  out_color *= mult;
}
