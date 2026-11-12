#version 460 core

// As ra_mesh.frag, for instances with a color transform, which this applies to each fragment of a gradient. A color path's color
// was transformed per vertex. A draw's instances share one color transform, scaled by their opacity, in a uniform

#include "ra_mesh.glsl"

uniform sampler2D paints;

uniform TransformInfo {
  vec4 m0;
  vec4 m1;
  vec4 m2;
  vec4 m3;
} colorTransform;

// The same as ra_mesh.vert's outputs, in the same order
in vec2 v_q;
flat in vec4 v_color;
flat in vec4 v_stops;

out vec4 frag_color;

void main() {
  if (v_stops.y == 0.0) {
    frag_color = v_color;
    return;
  }
  vec4 c = gradient(paints, v_stops.z != 0.0 ? length(v_q) : v_q.y, uint(v_stops.x), uint(v_stops.y));
  frag_color = transformColor(vec4(c.rgb * c.a, c.a), colorTransform.m0, colorTransform.m1, colorTransform.m2,
                              colorTransform.m3);
}
