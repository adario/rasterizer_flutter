#version 460 core

// Draws an opaque part in its color. Ported from opaques_fragment_main in Rasterizer's Shaders.metal, without images

#include "ra_paint.glsl"

in vec3 v_tex;

out vec4 frag_color;

void main() {
  frag_color = paintColor(v_tex);
}
