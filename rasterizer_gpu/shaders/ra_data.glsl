// Readers of a frame's structs, for the GPU renderer's vertex shaders. The host uploads the frame into a data texture,
// r32g32b32a32Float, 4 words a texel & 1 << kDataWidthLog2 texels a row. The FrameInfo uniform gives the first word of each
// array of structs, where the Metal shaders had buffer offsets

#include "ra_defs.glsl"

uniform sampler2D data;

uniform FrameInfo {
  uvec4 bases;   // First words: x of this draw's entries, y of the pass's segments, z of its instances, w of the paths' data
  uvec4 counts;  // x the first word of the 16-bit points, y the path count, z the gradient strip count, w this draw's instances
  uvec4 flags;   // x the kParam flags
  vec4 size;     // xy the target's size in pixels
} frame;

uint loadWord(uint word) {
  uint texel = word >> 2u;
  vec4 t = texelFetch(data, ivec2(int(texel & ((1u << kDataWidthLog2) - 1u)), int(texel >> kDataWidthLog2)), 0);
  return floatBitsToUint(t[word & 3u]);
}

float loadFloat(uint word) {
  return uintBitsToFloat(loadWord(word));
}

// The low 16 bits of w, as a signed short
int lowShort(uint w) {
  return int(w << 16u) >> 16;
}

bool useCurves() {
  return (frame.flags.x & kParamUseCurves) != 0u;
}

struct Transform {
  float a, b, c, d, tx, ty;
};

Transform loadTransform(uint word) {
  return Transform(loadFloat(word), loadFloat(word + 1u), loadFloat(word + 2u), loadFloat(word + 3u), loadFloat(word + 4u),
                   loadFloat(word + 5u));
}

// The first word of path iz's PathData { Transform ctm, clip, texCtm; float width; uint32_t texIdx, mode; }
uint pathWord(uint iz) {
  return frame.bases.w + iz * kPathDataWords;
}

struct Cell {
  float lx, ly, ux, uy, ox, oy;
};

// A Cell, from its 6 uint16s in 3 words
Cell loadCell(uint word) {
  uint w0 = loadWord(word), w1 = loadWord(word + 1u), w2 = loadWord(word + 2u);
  return Cell(float(w0 & 0xFFFFu), float(w0 >> 16u), float(w1 & 0xFFFFu), float(w1 >> 16u), float(w2 & 0xFFFFu),
              float(w2 >> 16u));
}

struct Quadratic {
  float x0, y0, x1, y1, x2, y2;
};

Quadratic loadQuadratic(uint word) {
  return Quadratic(loadFloat(word), loadFloat(word + 1u), loadFloat(word + 2u), loadFloat(word + 3u), loadFloat(word + 4u),
                   loadFloat(word + 5u));
}

// A 16-bit point, Point16 { uint16_t x, y; }, whose x's top bit is kPoint16IsCurve
uint loadPoint16(uint index) {
  return loadWord(frame.counts.x + index);
}

