// As ra_mesh.vert, for meshes with strokes. A stroke thins as its instance's transform shrinks it, down to its least half width on
// screen, frame.size.z. Thinner, 4x MSAA's samples would break it into dots, so it keeps that width. A hairline, of half width 0,
// always has it
//
// Each stroke vertex has an offset, in half widths, from the polyline point that it's built around. It's 1 long on a segment's
// sides, & longer at a miter. Fills' vertices have none, nor do the crossings of a stroke imported as its union, so that its
// overlaps don't show. Those vertices stay where they are. So the joins & caps widen around their own points, & keep their shapes

#include "ra_mesh.glsl"

const float kMaxOffset = 4.0;  // Longer offsets count as this long, as a short segment's inner miter would overshoot

in vec2 position;
in float path;  // The vertex's path index, a float, as Impeller's OpenGL ES backend has no 32-bit integer attributes
in vec2 offset;
in vec3 r0;  // Per instance: the rows of its transform into the target's pixels, a c tx, b d ty & g h i
in vec3 r1;
in vec3 r2;
in vec4 m0;  // Its color transform's rows, scaled by its opacity
in vec4 m1;
in vec4 m2;
in vec4 m3;

uniform FrameInfo {
  vec4 size;  // xy the target's size in pixels, which are device pixels, & z a stroke's least half width in them
} frame;

uniform sampler2D paints;

out vec2 v_q;  // A gradient's coordinates, an affine function of the SVG's units, so the triangles interpolate them exactly
flat out vec4 v_color;  // A color path's color, transformed
flat out vec4 v_stops;  // A gradient's first stop's texel, its stop count, 0 for a color, 1 if it's radial, & the opacity

// The vertex shader's main, for ra_mesh_stroked.vert & ra_mesh_glow.vert
void strokedVertex() {
  uint texel = 3u * uint(path);
  vec4 paint = paintTexel(paints, texel);
  vec4 stops = paintTexel(paints, texel + 2u);

  vec3 p = vec3(position, 1.0);
  float x = dot(r0, p), y = dot(r1, p), w = dot(r2, p);
  float uu = dot(offset, offset);
  if (uu > 0.0) {
    float hw = stops.w == 0.0 ? paintTexel(paints, texel + 1u).x : paint.y;
    vec3 c = vec3(position - offset * hw, 1.0);  // The polyline's point
    float cw = dot(r2, c);
    if (cw > 0.0) {
      vec2 q = vec2(dot(r0, c), dot(r1, c)) / cw;
      // The offset on screen, the projection's derivative at the point
      vec2 s = (vec2(dot(r0.xy, offset), dot(r1.xy, offset)) - q * dot(r2.xy, offset)) / cw;
      float ss = dot(s, s);
      // The half width, in the SVG's units, that's the least half width on screen along the offset. The offset's length on
      // screen over its length in units is how much the transform scales the half width there
      float t = frame.size.z * sqrt(min(uu, kMaxOffset * kMaxOffset) / ss);
      if (ss > 0.0 && t > hw) {
        x = (q.x + s.x * t) * w, y = (q.y + s.y * t) * w;
      }
    }
  }
  // Clip space's y is up, the target's down
  gl_Position = vec4(x / frame.size.x * 2.0 - w, w - y / frame.size.y * 2.0, 0.0, w);

  if (stops.w == 0.0) {
    v_color = transformColor(paint, m0, m1, m2, m3);
    v_stops = vec4(0.0);
    v_q = vec2(0.0);  // Unread, but written, so no varying is left undefined
  } else {
    v_color = vec4(0.0);  // Unread, likewise
    vec4 g = paintTexel(paints, texel + 1u);
    v_q = vec2(dot(g.xz, position) + stops.x, dot(g.yw, position) + stops.y);
    // Without a color transform, the rows are the identity's scaled by the opacity, so m3.w is the opacity
    v_stops = vec4(stops.z, stops.w, paint.x, m3.w);
  }
}
