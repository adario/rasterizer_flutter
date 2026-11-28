// A draw's color, from the colors texture: its own texel, or its gradient's strip, sampled linearly. A linear gradient's tex.x is
// the position along the strip. A radial one's tex.x and tex.z are the point's coordinates from its center, and their distance from
// the center is the position. The caller says which it is, as tex.z can't: a radial gradient's tex.z is 0 on the line through its
// center, where its tex.x is negative on one side. The texture holds the core's BGRA bytes as r8g8b8a8, which every backend
// supports, so they're swizzled back here.

uniform sampler2D colors;

vec4 paintColor(vec3 tex, bool isRadial) {
  return texture(colors, vec2(isRadial ? sqrt(tex.x * tex.x + tex.z * tex.z) : tex.x, tex.y)).bgra;
}
