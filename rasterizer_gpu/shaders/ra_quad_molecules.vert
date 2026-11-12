#version 460 core

// Draws a molecule's quadratic, or its line as a quadratic, into the accumulation texture, as ra_fast_molecules.vert draws lines.
// The core picks these when curves are on & show. Ported from quad_molecules_vertex_main in Rasterizer's Shaders.metal

#include "ra_data.glsl"

in vec2 corner;  // The unit corners of a 4-vertex triangle strip: x is the vertex index & 1, y is the index >> 1

out vec4 v_p0;  // x0, y0, x1, y1
out vec2 v_p1;  // x2, y2

void main() {
  uint edge = frame.bases.x + uint(gl_InstanceIndex) * kEdgeWords;
  uint ic = loadWord(edge), iw = loadWord(edge + 1u);
  uint inst = frame.bases.z + (ic & kEdgeMask) * kInstanceWords;
  Transform m = loadTransform(pathWord(loadWord(inst) & kPathIndexMask));
  Cell cell = loadCell(inst + 1u);
  uint base = loadWord(inst + 5u), molsbase = loadWord(inst + 7u);
  uint p = base + ((ic & kEdgeUe0) >> 12u) + (iw & 0xFFFFu);
  uint molecule = base + (molsbase + (iw >> 16u)) * 2u;
  uint p0 = loadPoint16(p), p1 = loadPoint16(p + 1u), p2 = loadPoint16(p + 2u);
  bool isCurve = (p0 & kPoint16IsCurve) != 0u;
  float ix0 = float(p0 & kPoint16Mask), iy0 = float((p0 >> 16u) & kPoint16Mask);
  float ix1 = float(p1 & kPoint16Mask), iy1 = float((p1 >> 16u) & kPoint16Mask);
  float ix2 = float(p2 & kPoint16Mask), iy2 = float((p2 >> 16u) & kPoint16Mask);
  float x0, y0, x1, y1, x2, y2, slx, sux, sly, suy;

  x0 = ix0 * m.a + iy0 * m.c + m.tx, y0 = ix0 * m.b + iy0 * m.d + m.ty;
  x1 = ix1 * m.a + iy1 * m.c + m.tx, y1 = ix1 * m.b + iy1 * m.d + m.ty;
  if (isCurve) {
    x2 = ix2 * m.a + iy2 * m.c + m.tx, y2 = ix2 * m.b + iy2 * m.d + m.ty;
    // The middle point is the curve's own, at t = 0.5: the control point is twice it, less the ends' mean
    x1 = 2.0 * x1 - 0.5 * (x0 + x2), y1 = 2.0 * y1 - 0.5 * (y0 + y2);
  } else {
    x2 = x1, x1 = 0.5 * (x0 + x2);
    y2 = y1, y1 = 0.5 * (y0 + y2);
  }
  slx = min(x1, min(x0, x2)), sly = min(y1, min(y0, y2));
  suy = max(y1, max(y0, y2));

  // The molecule's right side, from the corner of its bounds that the transform puts rightmost, read without masking out
  // kPoint16IsCurve, as the Metal shader does
  float molx = float(loadPoint16(molecule + (m.a > 0.0 ? 1u : 0u)) & 0xFFFFu);
  float moly = float(loadPoint16(molecule + (m.c > 0.0 ? 1u : 0u)) >> 16u);
  sux = ceil(molx * m.a + moly * m.c + m.tx);

  float dx = clamp(corner.x > 0.5 ? ceil(sux) : floor(slx), cell.lx, cell.ux);
  float dy = clamp(corner.y > 0.5 ? ceil(suy) : floor(sly), cell.ly, cell.uy);
  float x = (cell.ox - cell.lx + dx) / frame.size.x * 2.0 - 1.0, offx = 0.5 - dx;
  float y = 1.0 - (cell.oy - cell.ly + dy) / frame.size.y * 2.0, offy = 0.5 - dy;
  gl_Position = vec4(x, y, 1.0, 1.0);
  v_p0 = vec4(x0 + offx, y0 + offy, x1 + offx, y1 + offy);
  v_p1 = vec2(x2 + offx, y2 + offy);
}
