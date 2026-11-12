#version 460 core

// The mesh renderer's vertex shader, for meshes without strokes. It draws a mesh's vertices, in its SVG's units, once per instance,
// under the instance's transform, which may have perspective, into its run's target. A color path's color is computed here, a
// gradient's in the fragment shader

#include "ra_mesh.glsl"

in vec2 position;
in float path;  // The vertex's path index, a float, as Impeller's OpenGL ES backend has no 32-bit integer attributes
in vec3 r0;  // Per instance: the rows of its transform into the target's pixels, a c tx, b d ty & g h i
in vec3 r1;
in vec3 r2;
in vec4 m0;  // Its color transform's rows, scaled by its opacity
in vec4 m1;
in vec4 m2;
in vec4 m3;

uniform FrameInfo {
  vec4 size;  // xy the target's size in pixels
} frame;

uniform sampler2D paints;

out vec2 v_q;  // A gradient's coordinates, an affine function of the SVG's units, so the triangles interpolate them exactly
flat out vec4 v_color;  // A color path's color, transformed
flat out vec4 v_stops;  // A gradient's first stop's texel, its stop count, 0 for a color, 1 if it's radial, & the opacity

void main() {
  vec3 p = vec3(position, 1.0);
  float x = dot(r0, p), y = dot(r1, p), w = dot(r2, p);
  // Clip space's y is up, the target's down
  gl_Position = vec4(x / frame.size.x * 2.0 - w, w - y / frame.size.y * 2.0, 0.0, w);

  uint texel = 3u * uint(path);
  vec4 paint = paintTexel(paints, texel);
  vec4 stops = paintTexel(paints, texel + 2u);
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
