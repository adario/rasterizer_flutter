#version 460 core

// As ra_mesh_stroked.vert, for meshes with a glow. It also passes on each vertex's glow value, 1 on the path's own outline, as
// ra_mesh.hpp's Ribbon describes. A halo is light, so it hides what's under it only as much as its color's strongest channel,
// which is its alpha here. So a halo tinted to black leaves nothing

#include "ra_mesh_stroked.glsl"

in float glow;

out float v_glow;

void main() {
  strokedVertex();
  v_glow = glow;
  if (paintTexel(paints, 3u * uint(path) + 1u).y != 0.0) {
    v_color.a = max(v_color.r, max(v_color.g, v_color.b));
  }
}
