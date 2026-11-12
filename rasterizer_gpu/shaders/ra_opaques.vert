#version 460 core

// Draws the opaque parts of a frame's paths, front to back, writing depth, so the GPU skips what's behind them: the cells that a
// fill covers whole, & opaque strokes' outlines. Ported from opaques_vertex_main in Rasterizer's Shaders.metal, without images, as
// SVGs have none

#include "ra_data.glsl"

in vec2 corner;  // The unit corners of a 4-vertex triangle strip: x is the vertex index & 1, y is the index >> 1

out vec3 v_tex;

void main() {
  uint count = frame.counts.w, pathCount = frame.counts.y, texCount = frame.counts.z;
  uint word = frame.bases.x + (count - 1u - uint(gl_InstanceIndex)) * kOpaqueWords;
  uint izw = loadWord(word);
  uint iz = izw & kPathIndexMask;
  bool isGradient = (izw & kIsGradient) != 0u;
  bool isRadial = (izw & kIsRadial) != 0u;
  bool showOpaques = (frame.flags.x & kParamShowOpaques) != 0u;
  uint path = pathWord(iz);
  Transform texCtm = loadTransform(path + 12u);
  float width = frame.size.x, height = frame.size.y;
  float x, y, z = kDepthRange * float(iz + 1u) / float(pathCount);
  bool isTop = corner.y > 0.5, isRight = corner.x > 0.5;

  if ((izw & kOutlines) != 0u) {
    // A stroke's segment: the quad around it, inset by half a pixel at its sides & caps, which ra_instances.frag antialiases
    Quadratic quad = loadQuadratic(word + 1u);
    float dw = 0.5 * (loadFloat(path + 18u) - 1.0);
    float x0 = quad.x0, y0 = quad.y0, x1 = quad.x1, y1 = quad.y1, x2 = quad.x2, y2 = quad.y2;
    bool isFlat = x1 == FLT_MAX;
    bool pcap = (izw & kPCap) != 0u;
    bool ncap = (izw & kNCap) != 0u;
    bool isCap = (isTop && ncap) || (!isTop && pcap);
    bool curves = useCurves();
    float side = isRight ? -1.0 : 1.0;

    float ax, bx, cx, ay, by, cy, crs, dx, dy, ow, miterLen;
    ax = x2 - x1, bx = x1 - x0, cx = x2 - x0;
    ay = y2 - y1, by = y1 - y0, cy = y2 - y0;
    vec2 unit = normalize(vec2(
        isFlat || (isCap && !curves) ? cx : (isTop ? ax : bx),
        isFlat || (isCap && !curves) ? cy : (isTop ? ay : by)));
    crs = bx * -cy + by * cx;
    ow = isFlat || !curves || side * crs > 0.0 ? 0.0 : 0.5 * abs(crs / (cx * unit.x + cy * unit.y));
    miterLen = side * max(-dw, dw - ow);

    dx = isCap ? 0.5 * unit.x : 0.0, x = (isTop ? x2 - dx : x0 + dx) + miterLen * -unit.y;
    dy = isCap ? 0.5 * unit.y : 0.0, y = (isTop ? y2 - dy : y0 + dy) + miterLen * unit.x;
  } else {
    // A cell that a fill covers whole
    Cell cell = loadCell(word + 1u);
    x = isRight ? cell.ux : cell.lx;
    y = isTop ? cell.uy : cell.ly;
  }
  gl_Position = vec4(x / width * 2.0 - 1.0, y / height * 2.0 - 1.0, z, 1.0);

  uint tw = kColorTextureWidth, th = (pathCount + tw) / tw;
  uint tiz = showOpaques ? iz : pathCount;
  v_tex = vec3((0.5 + float(tiz % tw)) / float(tw), (0.5 + float(tiz / tw)) / float(th + texCount), 0.0);
  if (showOpaques && isGradient) {
    uint texIdx = loadWord(path + 19u);
    v_tex.x = x * texCtm.b + y * texCtm.d + texCtm.ty;
    v_tex.y = (0.5 + float(th + texIdx)) / float(th + texCount);
    v_tex.z = isRadial ? x * texCtm.a + y * texCtm.c + texCtm.tx : 0.0;
  }
}
