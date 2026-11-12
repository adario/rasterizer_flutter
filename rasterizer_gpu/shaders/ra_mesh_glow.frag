#version 460 core

// The fragment shader for meshes with a glow, whose paths are all colors. It shades the interpolated glow value with one profile,
// a neon tube's. The glow goes from 0 at a halo's outer edge, through 1 at the path's edge, to 2 down the middle of a core. Always
// blended with one & one minus source alpha, as in ra_mesh.frag
//
// A halo's alpha is kHaloAlpha times the glow squared. It rises to 1 over the halo's last kHaloEdge, so the path's edge is no step
// for 4x MSAA to quantize
//
// Past 1, the color goes to near white, its strongest channel's value, so a tint to black darkens the core too. A core so thin
// that its bright middle would hop between pixels keeps its color instead. The glow's gradient tells which: lines under about 2.7
// pixels keep it

#define kHaloAlpha 0.6
#define kHaloEdge 0.2
#define kHotGlow 0.85
#define kHotWhite 0.9
#define kThinGradient 0.75
#define kThinnestGradient 1.6

// The same as ra_mesh_glow.vert's outputs, in the same order, even those not read here, as their locations follow that order
in vec2 v_q;
flat in vec4 v_color;
flat in vec4 v_stops;
in float v_glow;

out vec4 frag_color;

void main() {
  vec3 color = v_color.rgb;
  float halo = min(v_glow, 1.0);
  float alpha = mix(kHaloAlpha * halo * halo, 1.0, smoothstep(1.0 - kHaloEdge, 1.0, halo));
  float hot = smoothstep(0.0, kHotGlow, max(v_glow - 1.0, 0.0));
  hot *= 1.0 - smoothstep(kThinGradient, kThinnestGradient, length(vec2(dFdx(v_glow), dFdy(v_glow))));
  frag_color = vec4(mix(color, vec3(max(color.r, max(color.g, color.b))), hot * kHotWhite), v_color.a) * alpha;
}
