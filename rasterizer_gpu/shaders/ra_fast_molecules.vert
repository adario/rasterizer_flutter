#version 460 core

// Draws a fill's molecule into the accumulation texture, as ra_edges.vert draws an edge. The core draws fills with few pixels per
// edge from molecules: at import, it stores each path's points once as 16-bit points within the path's bounds, & each contour's
// bounds as a molecule. Each frame, the GPU then transforms those points, rather than the CPU writing segments. Fast molecules
// draw their points as lines, up to kFastSegments an instance, as the core picks them when curves are off or too flat to show.
// Ported from fast_molecules_vertex_main in Rasterizer's Shaders.metal

#include "ra_data.glsl"

in vec2 corner;  // The unit corners of a 4-vertex triangle strip: x is the vertex index & 1, y is the index >> 1

out vec4 v_p0;  // x0, y0, x1, y1
out vec4 v_p1;  // x2, y2, x3, y3
out vec4 v_p2;  // x4, y4, & the lines' rightmost x

void main() {
  float dst[10];
  uint iid = uint(gl_InstanceIndex);
  uint edge = frame.bases.x + iid * kEdgeWords;
  uint ic = loadWord(edge), iw = loadWord(edge + 1u);
  uint inst = frame.bases.z + (ic & kEdgeMask) * kInstanceWords;
  int segcount = int(iw & 0xFFFFu), i;
  Transform m = loadTransform(pathWord(loadWord(inst) & kPathIndexMask));
  Cell cell = loadCell(inst + 1u);
  uint base = loadWord(inst + 5u), biid = loadWord(inst + 6u), molsbase = loadWord(inst + 7u);
  uint pts = base + (iid - biid) * uint(kFastSegments);
  uint molecule = base + (molsbase + (iw >> 16u)) * 2u;
  float x16, y16, slx, sux, sly, suy, x0, y0;
  bool skip = false;

  uint p = loadPoint16(pts);
  x16 = float(p & kPoint16Mask), y16 = float((p >> 16u) & kPoint16Mask), pts++;
  x0 = x16 * m.a + y16 * m.c + m.tx, y0 = x16 * m.b + y16 * m.d + m.ty;
  dst[0] = slx = sux = x0, dst[1] = sly = suy = y0;

  for (i = 0; i < kFastSegments; i++, pts++) {
    skip = skip || i >= segcount;
    p = loadPoint16(pts);
    x16 = float(p & kPoint16Mask), y16 = float((p >> 16u) & kPoint16Mask);
    x0 = skip ? x0 : x16 * m.a + y16 * m.c + m.tx, slx = min(slx, x0), sux = max(sux, x0);
    y0 = skip ? y0 : x16 * m.b + y16 * m.d + m.ty, sly = min(sly, y0), suy = max(suy, y0);
    dst[2 + i * 2] = x0, dst[3 + i * 2] = y0;
  }

  // The molecule's right side, from the corner of its bounds that the transform puts rightmost, read without masking out
  // kPoint16IsCurve, as the Metal shader does
  float molx = float(loadPoint16(molecule + (m.a > 0.0 ? 1u : 0u)) & 0xFFFFu);
  float moly = float(loadPoint16(molecule + (m.c > 0.0 ? 1u : 0u)) >> 16u);
  float ux = ceil(molx * m.a + moly * m.c + m.tx);

  float dx = clamp(corner.x > 0.5 ? ux : floor(slx), cell.lx, cell.ux);
  float dy = clamp(corner.y > 0.5 ? ceil(suy) : floor(sly), cell.ly, cell.uy);
  float x = (cell.ox - cell.lx + dx) / frame.size.x * 2.0 - 1.0, offx = 0.5 - dx;
  float y = 1.0 - (cell.oy - cell.ly + dy) / frame.size.y * 2.0, offy = 0.5 - dy;
  // w is 0, so nothing is drawn, where all the points are one
  gl_Position = vec4(x, y, 1.0, slx == sux && sly == suy ? 0.0 : 1.0);
  for (i = 0; i < kFastSegments + 1; i++)
    dst[i * 2] += offx, dst[i * 2 + 1] += offy;
  v_p0 = vec4(dst[0], dst[1], dst[2], dst[3]);
  v_p1 = vec4(dst[4], dst[5], dst[6], dst[7]);
  v_p2 = vec4(dst[8], dst[9], sux + offx, 0.0);
}
