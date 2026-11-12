#version 460 core

// Shades an instance: its coverage times its color. A fill's coverage comes from the winding accumulated for its pixel, an
// outline's from its distances to the stroke's segment. Both fade out at the draw's clip bounds. Blended with one & one minus
// source alpha. Ported from instances_fragment_main in Rasterizer's Shaders.metal, without images, clip masks or blend modes

#include "ra_winding.glsl"
#include "ra_paint.glsl"

uniform sampler2D accumulation;

in vec2 v_clip;
in vec3 v_tex;
in vec3 v_uvw;
flat in float v_cover;
flat in uint v_iz;

out vec4 frag_color;

// A fill's coverage of a pixel in one of its edge cells, from the accumulated winding, or 1 in a cell that it covers whole. The
// texel is fetched rather than sampled, as sampling would need a clamp-to-zero address mode, which Flutter GPU's samplers lack
float fillCoverage() {
  if (v_uvw.x >= FLT_MAX * 0.5)
    return 1.0;
  ivec2 texel = ivec2(floor(v_uvw.xy)), size = textureSize(accumulation, 0);
  float winding = all(greaterThanEqual(texel, ivec2(0))) && all(lessThan(texel, size)) ? texelFetch(accumulation, texel, 0).x : 0.0;
  float cover = abs(v_cover + winding);
  return (v_iz & kEvenOdd) != 0u ? 1.0 - abs(mod(cover, 2.0) - 1.0) : min(1.0, cover);
}

void main() {
  float alpha = 1.0;
  if ((v_iz & kOutlines) != 0u) {
    bool isCurve = (v_iz & kIsCurve) != 0u;
    bool squareCap = (v_iz & kSquareCap) != 0u;
    bool pcap = (v_iz & kPCap) != 0u, ncap = (v_iz & kNCap) != 0u;
    bool f0 = (v_iz & kF0) != 0u, f1 = (v_iz & kF1) != 0u;
    float dw = max(1.0, v_cover);

    if (!isCurve) {
      float dx = v_uvw.x, dy = min(v_uvw.y, v_uvw.z), ry = min(0.0, dy);
      float rect = clamp01(dw - abs(dx)) * clamp01(dy);
      float lozenge = clamp01(dw - sqrt(dx * dx + ry * ry));
      alpha = v_uvw.y < v_uvw.z ? (f0 ? lozenge : rect) : (f1 ? lozenge : rect);
    } else {
      float x0, y0, x1, y1, x2, y2, d0, dm0, d1, dm1, sqdist, sd0, sd1, cap, cap0, cap1;

      // The barycentric coordinates are affine in screen space, so inverting their derivatives gives the control triangle's
      // edges, p0 - p2 & p1 - p2, with the fragment at the origin
      float a = dFdx(v_uvw.x), b = -dFdy(v_uvw.x), c = dFdx(v_uvw.y), d = -dFdy(v_uvw.y), rdet = 1.0 / (a * d - b * c);
      vec2 e0 = vec2(d, -c) * rdet, e1 = vec2(-b, a) * rdet, p2 = -(e0 * v_uvw.x + e1 * v_uvw.y), p0 = p2 + e0, p1 = p2 + e1;
      x0 = p0.x, y0 = p0.y, x1 = p1.x, y1 = p1.y, x2 = p2.x, y2 = p2.y;

      sqdist = sqBezier(vec2(x0, y0), vec2(x1, y1), vec2(x2, y2));
      float outline = clamp01(dw - sqrt(sqdist));

      cap = squareCap ? dw : 0.5;

      float bx = x0 - x1, by = y0 - y1, bdot = bx * bx + by * by, rb = inversesqrt(bdot);
      d0 = (x0 * bx + y0 * by) * rb, dm0 = (x0 * -by + y0 * bx) * rb;
      cap0 = (pcap ? clamp01(cap + d0) : 1.0) * clamp01(dw - abs(dm0));
      sd0 = f0 ? clamp01(d0) : 1.0;

      float ax = x2 - x1, ay = y2 - y1, adot = ax * ax + ay * ay, ra = inversesqrt(adot);
      d1 = (x2 * ax + y2 * ay) * ra, dm1 = (x2 * -ay + y2 * ax) * ra;
      cap1 = (ncap ? clamp01(cap + d1) : 1.0) * clamp01(dw - abs(dm1));
      sd1 = f1 ? clamp01(d1) : 1.0;

      alpha = cap0 * (1.0 - sd0) + cap1 * (1.0 - sd1) + (sd0 + sd1 - 1.0) * outline;
    }
    alpha *= v_cover < 0.0 ? -v_cover : 1.0;
  } else {
    alpha = fillCoverage();
  }
  // Fades the instance out over a pixel at its clip bounds. Clips are always on (core.dart's Params): without them, v_clip would
  // be constant, & inversesqrt(0) is undefined
  float clx = v_clip.x, cly = v_clip.y, a = dFdx(clx), b = dFdy(clx), c = dFdx(cly), d = dFdy(cly);
  float sx = inversesqrt(a * a + b * b), sy = inversesqrt(c * c + d * d);
  float clip = clamp01(0.5 + clx * sx) * clamp01(0.5 + (1.0 - clx) * sx) * clamp01(0.5 + cly * sy) * clamp01(0.5 + (1.0 - cly) * sy);

  frag_color = alpha * clip * paintColor(v_tex);
}
