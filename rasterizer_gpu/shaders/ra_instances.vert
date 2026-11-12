#version 460 core

// Draws a frame's instances: a fill's cells, & a stroke's outlines, a quad around each segment that meets its neighbors' at a
// miter. Ported from instances_vertex_main in Rasterizer's Shaders.metal, without images, as SVGs have none

#include "ra_data.glsl"

in vec2 corner;  // The unit corners of a 4-vertex triangle strip: x is the vertex index & 1, y is the index >> 1

out vec2 v_clip;
out vec3 v_tex;
out vec3 v_uvw;  // A fill's accumulation texel in pixels, an outline's distances, or a curved outline's barycentric coordinates
flat out float v_cover;
flat out uint v_iz;

void main() {
  const float err = 1e-3;
  bool isRight = corner.x > 0.5, isTop = corner.y > 0.5;
  float side = isRight ? -1.0 : 1.0;
  uint iid = uint(gl_InstanceIndex);
  uint word = frame.bases.x + iid * kInstanceWords;
  uint izw = loadWord(word);
  uint iz = izw & kPathIndexMask, flags = izw & kFragmentMask;
  bool isGradient = (izw & kIsGradient) != 0u;
  bool isRadial = (izw & kIsRadial) != 0u;
  bool curves = useCurves();
  uint path = pathWord(iz);
  Transform clip = loadTransform(path + 6u);
  Transform texCtm = loadTransform(path + 12u);
  float width = frame.size.x, height = frame.size.y;

  float dx, dy;
  if ((izw & kOutlines) != 0u) {
    float w = loadFloat(path + 18u), cw = max(1.0, w), dw = 0.5 * (1.0 + cw);

    float x0, y0, x1, y1, x2, y2;
    bool pcap, ncap;
    bool roundCap = w > 1.0 && (izw & kRoundCap) != 0u;
    bool squareCap = (izw & kSquareCap) != 0u;
    bool roundJoin = (izw & kRoundJoin) != 0u;

    bool isCurve;
    vec2 no, m0, m1;
    float ow = 0.0;

    uint pn = loadWord(word + 7u);
    int prevIndex = lowShort(pn), nextIndex = lowShort(pn >> 16u);
    Quadratic p = loadQuadratic(uint(int(word) + prevIndex * int(kInstanceWords)) + 1u);
    Quadratic o = loadQuadratic(word + 1u);
    Quadratic n = loadQuadratic(uint(int(word) + nextIndex * int(kInstanceWords)) + 1u);
    bool pcurve = curves && p.x1 != FLT_MAX;
    bool ncurve = curves && n.x1 != FLT_MAX;

    pcap = prevIndex == 0 || p.x2 != o.x0 || p.y2 != o.y0;
    ncap = nextIndex == 0 || n.x0 != o.x2 || n.y0 != o.y2;
    x0 = o.x0, y0 = o.y0, x1 = o.x1, y1 = o.y1, x2 = o.x2, y2 = o.y2;

    float ax, bx, cx, ay, by, cy;
    ax = x1 - x2, bx = x1 - x0, cx = x2 - x0;
    ay = y1 - y2, by = y1 - y0, cy = y2 - y0;
    float cdot = cx * cx + cy * cy, rc = inversesqrt(cdot);
    float area = abs(cx * by - cy * bx);

    isCurve = curves && x1 != FLT_MAX && area > 1e-3 * cdot;
    ow = isCurve ? 0.5 * area * rc : 0.0;

    float caplimit = dw == 1.0 ? 0.0 : kMiterLimit;

    float px0, py0, pdot, nx1, ny1, ndot;
    px0 = x0 - (pcurve ? p.x1 : p.x0);
    py0 = y0 - (pcurve ? p.y1 : p.y0);
    nx1 = (ncurve ? n.x1 : n.x2) - x2;
    ny1 = (ncurve ? n.y1 : n.y2) - y2;
    pdot = px0 * px0 + py0 * py0;
    ndot = nx1 * nx1 + ny1 * ny1;

    no = vec2(cx, cy) * rc;
    vec2 prev, next, tangent;

    next = normalize(vec2((isCurve ? x1 : x2) - x0, (isCurve ? y1 : y2) - y0));
    prev = inversesqrt(pdot) * vec2(px0, py0);
    pcap = pcap || pdot < 1e-6 || dot(prev, next) < caplimit;
    tangent = pcap ? no : prev + next;
    m0 = vec2(-tangent.y, tangent.x) / abs(dot(no, tangent));

    prev = normalize(vec2(x2 - (isCurve ? x1 : x0), y2 - (isCurve ? y1 : y0)));
    next = inversesqrt(ndot) * vec2(nx1, ny1);
    ncap = ncap || ndot < 1e-6 || dot(prev, next) < caplimit;
    tangent = ncap ? no : prev + next;
    m1 = vec2(-tangent.y, tangent.x) / abs(dot(no, tangent));

    float lcap = (isCurve ? 0.41 * dw : 0.0) + (squareCap || roundCap ? dw : 0.5);

    vec2 miter0 = (dw + ow) * m0;
    vec2 miter1 = (dw + ow) * m1;

    float lp, cx0, cy0, ln, cx1, cy1, t, dt, rt;
    lp = (pcap ? lcap : 0.0) + err, cx0 = x0 - no.x * lp, cy0 = y0 - no.y * lp;
    ln = (ncap ? lcap : 0.0) + err, cx1 = x2 + no.x * ln, cy1 = y2 + no.y * ln;
    t = ((cx1 - cx0) * miter1.y - (cy1 - cy0) * miter1.x) / (miter0.x * miter1.y - miter0.y * miter1.x);
    rt = side * t, dt = side * (rt < 0.0 ? 1.0 : min(1.0, rt));
    dx = isTop ? miter1.x * dt + cx1 : miter0.x * dt + cx0;
    dy = isTop ? miter1.y * dt + cy1 : miter0.y * dt + cy0;

    if (!isCurve) {
      v_uvw.x = (dx - x0) * -no.y + (dy - y0) * no.x;
      float offset = roundCap ? 0.0 : squareCap ? dw : 0.5;
      float d0 = (dx - x0) * no.x + (dy - y0) * no.y;
      float d1 = (dx - x2) * -no.x + (dy - y2) * -no.y;
      v_uvw.y = pcap ? offset + d0 : roundJoin ? d0 : FLT_MAX;
      v_uvw.z = ncap ? offset + d1 : roundJoin ? d1 : FLT_MAX;

      flags = flags | (((pcap && roundCap) || (!pcap && roundJoin)) ? kF0 : 0u);
      flags = flags | (((ncap && roundCap) || (!ncap && roundJoin)) ? kF1 : 0u);
    } else {
      // The vertex's barycentric coordinates in the control triangle, from which the fragment recovers the control points
      float ex = dx - x2, ey = dy - y2, rdet = 1.0 / (cx * ay - ax * cy);
      v_uvw = vec3((ey * ax - ex * ay) * rdet, (ey * cx - ex * cy) * rdet, 0.0);

      flags = flags | kIsCurve;
      flags = flags | ((pcap ? !roundCap : !roundJoin) ? kF0 : 0u);
      flags = flags | ((ncap ? !roundCap : !roundJoin) ? kF1 : 0u);
    }
    // A stroke thinner than a pixel draws a pixel wide, faded by its width, which is passed negated
    v_cover = w != 0.0 && w < 1.0 ? -w : dw;
    flags = flags | (pcap ? kPCap : 0u) | (ncap ? kNCap : 0u);
  } else {
    Cell cell = loadCell(word + 1u);
    dx = isRight ? cell.ux : cell.lx;
    dy = isTop ? cell.uy : cell.ly;
    // The cell's texel in the accumulation texture, in pixels from its top left, or none for a cell that the fill covers whole.
    // Cells fill the texture from its top, so edges passes cover fewer rows
    v_uvw = vec3(cell.ox == float(kNullIndex) ? FLT_MAX : dx - (cell.lx - cell.ox), dy - (cell.ly - cell.oy), 0.0);
    v_cover = float(lowShort(loadWord(word + 4u)));
  }
  float x = dx / width * 2.0 - 1.0, y = dy / height * 2.0 - 1.0;
  float z = kDepthRange * float(iz + 1u) / float(frame.counts.y);
  gl_Position = vec4(x, y, z, 1.0);
  bool useClips = (frame.flags.x & kParamUseClips) != 0u;
  v_clip = useClips ? vec2(dx * clip.a + dy * clip.c + clip.tx, dx * clip.b + dy * clip.d + clip.ty) : vec2(0.5);
  v_iz = iz | flags;

  uint tw = kColorTextureWidth, th = (frame.counts.y + tw) / tw, texCount = frame.counts.z;
  if (isGradient) {
    uint texIdx = loadWord(path + 19u);
    v_tex.x = dx * texCtm.b + dy * texCtm.d + texCtm.ty;
    v_tex.y = (0.5 + float(th + texIdx)) / float(th + texCount);
    v_tex.z = isRadial ? dx * texCtm.a + dy * texCtm.c + texCtm.tx : 0.0;
  } else {
    v_tex = vec3((0.5 + float(iz % tw)) / float(tw), (0.5 + float(iz / tw)) / float(th + texCount), 0.0);
  }
}
