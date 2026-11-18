#version 460 core

#include <flutter/runtime_effect.glsl>

// Tube Shooter's glow, drawn over the world with TubeGlow.
//
// Round each pixel, it sums 24 samples of the world, weighted to fade with
// their distance, on a spiral out to the halo's radius. The sum saturates
// softly with uGain, and keeps the colour of the lines near it. The radius
// is uRadius logical pixels at uRim from uCenter, the tube's middle, and less
// towards it, down to a third, as the tube's lines thin with depth. Over a
// line still opaque at the world's half resolution, a white core of uCore
// shows, so thin lines get none.
uniform vec2 uSize;
uniform float uRadius;
uniform float uGain;
uniform float uCore;
uniform vec2 uCenter;
uniform float uRim;
uniform sampler2D uTexture;

out vec4 fragColor;

const int samples = 24;

// The golden angle, in radians, which spreads the spiral's samples evenly.
const float goldenAngle = 2.3999632;

void main() {
  vec2 position = FlutterFragCoord().xy;
  vec2 uv = position / uSize;
  float depth = clamp(length(position - uCenter) / uRim, 0.33, 1.0);
  float radius = uRadius * depth;
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = 0; i < samples; i++) {
    float reach = sqrt((float(i) + 0.5) / float(samples));
    float angle = float(i) * goldenAngle;
    vec2 offset = vec2(cos(angle), sin(angle)) * reach * radius / uSize;
    float weight = 1.0 - reach;
    sum += texture(uTexture, uv + offset) * weight;
    total += weight;
  }
  float alpha = 1.0 - exp(-sum.a / total * uGain);
  vec4 glow = sum.a > 0.0 ? vec4(sum.rgb / sum.a, 1.0) * alpha : vec4(0.0);
  float core = uCore * smoothstep(0.6, 1.0, texture(uTexture, uv).a);
  fragColor = glow * (1.0 - core) + vec4(core);
}
