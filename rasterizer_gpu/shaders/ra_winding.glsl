// The winding functions, which the edges' & molecules' fragment shaders add up per pixel, & sqBezier, for the curved outlines of
// ra_instances.frag

#include "ra_defs.glsl"

// The squared distance from the origin to the quadratic p0, p1, p2, from https://www.shadertoy.com/view/4dsfRS
float sqBezier(vec2 p0, vec2 p1, vec2 p2) {
  // Moves p1 at least kCubicSolverLimit off the line from p0 to p2, as a flat curve would make kk infinite. Then it solves the
  // cubic whose roots are the t of the nearest points: one root if d >= 0, else the nearer of two
  vec2 vb = p1 - p0, va, vc = vec2(p0.y - p2.y, p2.x - p0.x), rp1;
  float t = dot(vc, vb) / dot(vc, vc);
  float dt = kCubicSolverLimit - min(kCubicSolverLimit, abs(t));
  rp1 = p1 + dt * sign(t) * vc;
  vb = rp1 - p0, va = p2 - rp1, va -= vb;
  float kk = 1.0 / dot(va, va);
  float a = kk * dot(vb, va), b = kk * (2.0 * dot(vb, vb) + dot(p0, va)), c = kk * dot(p0, vb);
  float p = b - 3.0 * a * a, p3 = p * p * p;
  float q = a * (2.0 * a * a - b) + c;
  float d = q * q + 4.0 * p3 / 27.0;
  float third = 1.0 / 3.0;
  vb = p1 - p0, va = p2 - p1, va -= vb, vb *= 2.0;
  if (d >= 0.0) {
    float z = sqrt(d);
    vec2 x = 0.5 * (vec2(z, -z) - q);
    vec2 uv = sign(x) * pow(abs(x), vec2(third));
    float t = clamp01(uv.x + uv.y - a);
    vec2 pt = (va * t + vb) * t + p0;
    return dot(pt, pt);
  }
  float r = sqrt(-p * third);
  // Within -1 to 1, as d < 0, but clamped, as rounding past them would make acos NaN
  float v = acos(clamp(-0.5 * q / (r * r * r), -1.0, 1.0)) * third;
  float m = cos(v), n = sin(v) * 1.732050808;
  vec2 ts = clamp(vec2(m + m, -n - m) * r - a, 0.0, 1.0);
  vec2 pt0 = (va * ts.x + vb) * ts.x + p0;
  vec2 pt1 = (va * ts.y + vb) * ts.y + p0;
  return min(dot(pt0, pt0), dot(pt1, pt1));
}

// The winding of the line from (x0, y0) to (x1, y1) in a pixel, in pixel coordinates from 0 to 1, over its rows from w0 to w1. An
// inverse lerp of the signed area from the line to the pixel's corner gives the coverage t: 1, full coverage, at the nearest
// corner, & 0 at the furthest. f then evens out t for the line's slope, which sets how far apart the corners are across the line
float awinding(float x0, float y0, float x1, float y1, float w0, float w1) {
  float dx, dy, a0, t, b, f, cover = w1 - w0;
  dx = x1 - x0, dy = y1 - y0, a0 = dx * ((dx > 0.0 ? w0 : w1) - y0) - dy * (1.0 - x0);
  dx = abs(dx), t = -a0 / (dx * cover + dy), dy = abs(dy);
  b = max(dx, dy), f = b / (b - min(dx, dy) * 0.4142135624);
  // With no cover, as for a line of no length, t or f is 0 / 0, & clamp's result for a NaN is undefined: so 0, by a select rather
  // than a branch
  return cover == 0.0 ? 0.0 : clamp01((t - 0.5) * f + 0.5) * cover;
}

// The winding of the line from (x0, y0) to (x1, y1), over the pixel's rows that it spans
float lineWinding(float x0, float y0, float x1, float y1) {
  return awinding(x0, y0, x1, y1, clamp01(y0), clamp01(y1));
}

// The winding of a quadratic monotonic in y, from (x0, y0) through the control point (x1, y1) to (x2, y2). Left of the pixel, it
// winds the whole band it spans. Else it's the winding of its tangent where it crosses the middle of that band
float monotoneQuadraticWinding(float x0, float y0, float x1, float y1, float x2, float y2) {
  float w0 = clamp01(y0), w1 = clamp01(y2), w = w1 - w0, ay, by, cy, t, s;
  if (max(x0, x2) <= 0.0 || w == 0.0)
    return w;
  ay = y2 - y1, by = y1 - y0, ay -= by, by *= 2.0, cy = y0 - 0.5 * (w0 + w1);
  t = abs(ay) < kQuadraticFlatness ? -cy / by : (-by + sign(w) * sqrt(max(0.0, by * by - 4.0 * ay * cy))) / ay * 0.5;
  s = 1.0 - t;
  return awinding(s * x0 + t * x1, s * y0 + t * y1, s * x1 + t * x2, s * y1 + t * y2, w0, w1);
}

// The winding of any quadratic: the sum of its 2 halves' windings, split where it turns back in y
float quadraticWinding(float x0, float y0, float x1, float y1, float x2, float y2) {
  float w0 = clamp01(y0), w2 = clamp01(y2);
  if (max(x0, max(x1, x2)) <= 0.0)
    return w2 - w0;
  float w = 0.0, ay = y2 - y1, by = y1 - y0, cy, t, s, w1;
  // The height where it turns back, or its end's if it's monotonic
  w1 = clamp01(ay * by >= 0.0 ? y2 : y0 - by * by / (ay - by)), ay -= by, by *= 2.0;
  if (w0 != w1) {
    // The t where the first half crosses the middle of its band
    cy = y0 - 0.5 * (w0 + w1);
    t = abs(ay) < kQuadraticFlatness ? -cy / by : (-by + sign(w1 - w0) * sqrt(max(0.0, by * by - 4.0 * ay * cy))) / ay * 0.5;
    // & the winding of its tangent there
    s = 1.0 - t, w += awinding(s * x0 + t * x1, s * y0 + t * y1, s * x1 + t * x2, s * y1 + t * y2, w0, w1);
  }
  if (w1 != w2) {
    cy = y0 - 0.5 * (w1 + w2);
    t = abs(ay) < kQuadraticFlatness ? -cy / by : (-by + sign(w2 - w1) * sqrt(max(0.0, by * by - 4.0 * ay * cy))) / ay * 0.5;
    s = 1.0 - t, w += awinding(s * x0 + t * x1, s * y0 + t * y1, s * x1 + t * x2, s * y1 + t * y2, w1, w2);
  }
  return w;
}
