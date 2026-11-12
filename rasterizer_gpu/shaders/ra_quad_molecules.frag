#version 460 core

// Adds the winding of a molecule's quadratic to the accumulation texture, blended additively. Ported from
// quad_molecules_fragment_main in Rasterizer's Shaders.metal

#include "ra_winding.glsl"

in vec4 v_p0;  // x0, y0, x1, y1
in vec2 v_p1;  // x2, y2

out vec4 frag_color;

void main() {
  frag_color = vec4(quadraticWinding(v_p0.x, v_p0.y, v_p0.z, v_p0.w, v_p1.x, v_p1.y));
}
