// A draw's color, from the colors texture: its own texel, or its gradient's strip, sampled linearly. A linear gradient's tex.x is
// the position along the strip. A radial one's tex.x & tex.z are the point's coordinates from its center, whose distance is the
// position. The texture holds the core's BGRA bytes as r8g8b8a8, which every backend supports, so they're swizzled back here

uniform sampler2D colors;

vec4 paintColor(vec3 tex) {
  return texture(colors, vec2(tex.z == 0.0 ? tex.x : sqrt(tex.x * tex.x + tex.z * tex.z), tex.y)).bgra;
}
