#version 460 core

// Covers the whole target at the far depth, so drawing it clears the target to a color. Flutter GPU crashes when it loads a bundle
// with a vertex shader that has no inputs, so this one takes the renderer's unit quad corners
in vec2 corner;

uniform ClearInfo {
  vec4 color;
} clear_info;

out vec4 v_color;

void main() {
  gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
  v_color = clear_info.color;
}
