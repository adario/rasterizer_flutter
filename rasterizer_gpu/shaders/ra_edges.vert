#version 460 core

// Draws an edge into the accumulation texture, where the winding of a fill's cells adds up per pixel. An edge has up to 2 segments,
// lines or quadratics, which this passes on in its cell's pixel coordinates. It covers the part of the cell right of them & between
// their heights, which their winding reaches. The texture's rows count from the top, as in Metal, where clip space's +y is a
// texture's first row. Ported from edges_vertex_main in Rasterizer's Shaders.metal

#include "ra_data.glsl"

in vec2 corner;  // The unit corners of a 4-vertex triangle strip: x is the vertex index & 1, y is the index >> 1

out vec4 v_p0;  // x0, y0, x1, y1
out vec4 v_p1;  // x2, y2, x3, y3
out vec4 v_p2;  // x4, y4, x5, y5

void main() {
  float dst[12];
  uint edge = frame.bases.x + uint(gl_InstanceIndex) * kEdgeWords;
  uint ic = loadWord(edge), iw = loadWord(edge + 1u);
  uint inst = frame.bases.z + (ic & kEdgeMask) * kInstanceWords;
  Cell cell = loadCell(inst + 1u);
  uint base = loadWord(inst + 5u);
  uint ids[2] = uint[2](((ic & kEdgeUe0) >> 12u) + (iw & 0xFFFFu), ((ic & kEdgeUe1) >> 8u) + (iw >> 16u));
  float slx = cell.ux, sly = FLT_MAX, suy = -FLT_MAX;
  float x0, y0, x1, y1, x2, y2;

  for (int i = 0; i < 2; i++) {
    if (ids[i] != 0xFFFFFu) {
      uint s = frame.bases.y + (base + ids[i]) * kSegmentWords;
      uint ix0 = loadWord(s);
      x0 = uintBitsToFloat(ix0), y0 = loadFloat(s + 1u);
      bool curve = useCurves() && (ix0 & 1u) != 0u;
      if (curve) {
        uint n = s + kSegmentWords;
        x2 = loadFloat(n + 2u), y2 = loadFloat(n + 3u);
        x1 = loadFloat(s + 2u), y1 = loadFloat(s + 3u);
        dst[i * 6 + 0] = x0, dst[i * 6 + 1] = y0;
        dst[i * 6 + 2] = x1, dst[i * 6 + 3] = y1;
        dst[i * 6 + 4] = x2, dst[i * 6 + 5] = y2;

        float ay, by, cy, ax, bx, d, r, t0, t1;
        ax = x2 - x1, bx = x1 - x0, ax -= bx, bx *= 2.0;
        ay = y2 - y1, by = y1 - y0, ay -= by, by *= 2.0;
        cy = y0 - cell.ly, d = by * by - 4.0 * ay * cy, r = sqrt(max(0.0, d));
        t0 = clamp01(abs(ay) < kQuadraticFlatness ? -cy / by : (-by + (y2 - y0 < 0.0 ? -r : r)) / ay * 0.5);
        cy = y0 - cell.uy, d = by * by - 4.0 * ay * cy, r = sqrt(max(0.0, d));
        t1 = clamp01(abs(ay) < kQuadraticFlatness ? -cy / by : (-by + (y2 - y0 < 0.0 ? -r : r)) / ay * 0.5);
        if (t0 != t1)
          slx = min(slx, min((ax * t0 + bx) * t0 + x0, (ax * t1 + bx) * t1 + x0));
      } else {
        x2 = loadFloat(s + 2u), y2 = loadFloat(s + 3u);
        dst[i * 6 + 0] = x0, dst[i * 6 + 1] = y0;
        dst[i * 6 + 2] = 0.5 * (x0 + x2), dst[i * 6 + 3] = 0.5 * (y0 + y2);
        dst[i * 6 + 4] = x2, dst[i * 6 + 5] = y2;

        float m = (x2 - x0) / (y2 - y0), c = x0 - m * y0;
        slx = min(slx, max(min(x0, x2), min(m * clamp(y0, cell.ly, cell.uy) + c, m * clamp(y2, cell.ly, cell.uy) + c)));
      }
      sly = min(sly, min(y0, y2)), suy = max(suy, max(y0, y2));
    } else {
      for (int j = 0; j < 6; j++)
        dst[i * 6 + j] = 0.0;
    }
  }
  float dx = corner.x > 0.5 ? cell.ux : max(floor(slx), cell.lx);
  float dy = corner.y > 0.5 ? min(ceil(suy), cell.uy) : max(floor(sly), cell.ly);
  float x = (cell.ox - cell.lx + dx) / frame.size.x * 2.0 - 1.0;
  float y = 1.0 - (cell.oy - cell.ly + dy) / frame.size.y * 2.0;
  gl_Position = vec4(x, y, 1.0, 1.0);

  for (int i = 0; i < 12; i += 2)
    dst[i] += 0.5 - dx, dst[i + 1] += 0.5 - dy;
  v_p0 = vec4(dst[0], dst[1], dst[2], dst[3]);
  v_p1 = vec4(dst[4], dst[5], dst[6], dst[7]);
  v_p2 = vec4(dst[8], dst[9], dst[10], dst[11]);
}
