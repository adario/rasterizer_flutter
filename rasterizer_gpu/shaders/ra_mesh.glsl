// The mesh renderer's paints texture, which the host uploads once per mesh: r32g32b32a32Float, 1 << kPaintWidthLog2 texels a row.
// Each path has 3 texels, & each gradient stop 2: its offset, then its unpremultiplied color. A path's texels are:
// - For a color: its premultiplied color; its stroke's half width, & 1 if it's a glow's halo, which is always a color; & 0s
// - For a gradient: 1 if it's radial, & its stroke's half width; its transform's a b c d from the SVG's units; & its tx ty, its
//   first stop's texel & its stop count
// A stroke's half width is 0 for a hairline or a fill

const uint kPaintWidthLog2 = 10u;

vec4 paintTexel(sampler2D paints, uint texel) {
  return texelFetch(paints, ivec2(int(texel & ((1u << kPaintWidthLog2) - 1u)), int(texel >> kPaintWidthLog2)), 0);
}

// The unpremultiplied color at t of the count stops from texel first, interpolated unpremultiplied, as SVG does. Before the first
// stop & after the last, it's their color
vec4 gradient(sampler2D paints, float t, uint first, uint count) {
  float o0 = paintTexel(paints, first).x;
  vec4 c0 = paintTexel(paints, first + 1u);
  if (t <= o0)
    return c0;
  for (uint i = 1u; i < count; i++) {
    float o1 = paintTexel(paints, first + 2u * i).x;
    vec4 c1 = paintTexel(paints, first + 2u * i + 1u);
    if (t <= o1)
      return mix(c0, c1, (t - o0) / max(o1 - o0, 1e-9));
    o0 = o1, c0 = c1;
  }
  return c0;
}

// A premultiplied color transformed by a color transform's rows, already scaled by the instance's opacity, then clamped from 0
// to its alpha, as the core's Ra::ColorMatrix::transform does
vec4 transformColor(vec4 c, vec4 m0, vec4 m1, vec4 m2, vec4 m3) {
  float a = clamp(dot(m3, c), 0.0, 1.0);
  return vec4(clamp(vec3(dot(m0, c), dot(m1, c), dot(m2, c)), vec3(0.0), vec3(a)), a);
}
