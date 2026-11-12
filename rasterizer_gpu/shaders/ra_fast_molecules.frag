#version 460 core

// Adds the winding of a molecule's 4 lines to the accumulation texture. Where they're all left of the pixel, that's the height they
// span in it. Ported from fast_molecules_fragment_main in Rasterizer's Shaders.metal

#include "ra_winding.glsl"

in vec4 v_p0;  // x0, y0, x1, y1
in vec4 v_p1;  // x2, y2, x3, y3
in vec4 v_p2;  // x4, y4, & the lines' rightmost x

out vec4 frag_color;

void main() {
  if (v_p2.z <= 0.0) {
    frag_color = vec4(clamp01(v_p2.y) - clamp01(v_p0.y));
    return;
  }
  frag_color = vec4(lineWinding(v_p0.x, v_p0.y, v_p0.z, v_p0.w)
      + lineWinding(v_p0.z, v_p0.w, v_p1.x, v_p1.y)
      + lineWinding(v_p1.x, v_p1.y, v_p1.z, v_p1.w)
      + lineWinding(v_p1.z, v_p1.w, v_p2.x, v_p2.y));
}
