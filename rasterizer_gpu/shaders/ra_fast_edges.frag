#version 460 core

// Adds the winding of an edge's 2 lines to the accumulation texture, blended additively. Ported from fast_edges_fragment_main in
// Rasterizer's Shaders.metal

#include "ra_winding.glsl"

in vec4 v_p0;  // x0, y0, x1, y1
in vec4 v_p1;  // x2, y2, x3, y3
in vec4 v_p2;  // x4, y4, x5, y5

out vec4 frag_color;

void main() {
  frag_color = vec4(lineWinding(v_p0.x, v_p0.y, v_p1.x, v_p1.y) + lineWinding(v_p1.z, v_p1.w, v_p2.z, v_p2.w));
}
