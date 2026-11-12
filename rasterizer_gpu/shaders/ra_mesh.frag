#version 460 core

// The mesh renderer's fragment shader, for instances without a color transform. It draws a path's color, or its gradient's at the
// fragment, premultiplied & scaled by the instance's opacity. The triangles cover exactly the path, & multisampling antialiases
// their edges. Blended with one & one minus source alpha, unless the mesh & its instance are opaque
//
// Instances with a color transform use ra_mesh_transformed.frag, which reads the transform from a uniform. Reading it from 16 flat
// inputs in every fragment, even on a branch not taken, made gradients several times slower on Apple GPUs

#include "ra_mesh.glsl"

uniform sampler2D paints;

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
  // What transformColor does with rows that only scale by the opacity: a premultiplied color's rgb is never above its alpha, so
  // the clamps change nothing
  frag_color = vec4(c.rgb * c.a, c.a) * v_stops.w;
}
