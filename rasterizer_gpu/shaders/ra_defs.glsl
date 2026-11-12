// The core's constants & struct flags, from src/core's Rasterizer.h & Rasterizer.hpp, for the GPU renderer's shaders

#ifndef RA_DEFS
#define RA_DEFS

#define kPathIndexMask 0xFFFFFu
#define kColorTextureWidth 64u
#define kDepthRange 0.1
#define kFastSegments 4
#define kNullIndex 0xFFFFu
#define kQuadraticFlatness 1e-2
#define kMiterLimit -0.866025403784439
#define kCubicSolverLimit 5e-2
#define FLT_MAX 3.402823466e+38

// Instance::Flags
#define kBlend (1u << 20)
#define kRoundJoin (1u << 21)
#define kIsRadial (1u << 22)
#define kIsGradient (1u << 23)
#define kIsImage (1u << 24)
#define kIsCurve (1u << 24)
#define kMolecule (1u << 25)
#define kPCap (1u << 25)
#define kFastEdges (1u << 26)
#define kNCap (1u << 26)
#define kEdge (1u << 27)
#define kF0 (1u << 27)
#define kRoundCap (1u << 28)
#define kF1 (1u << 28)
#define kOutlines (1u << 29)
#define kSquareCap (1u << 30)
#define kEvenOdd (1u << 31)
#define kFragmentMask (kBlend | kOutlines | kSquareCap | kEvenOdd)

// Edge::Flags
#define kEdgeUe0 (0xFu << 28)
#define kEdgeUe1 (0xFu << 24)
#define kEdgeMask (~(kEdgeUe0 | kEdgeUe1))

// Point16::Flags
#define kPoint16IsCurve 0x8000u
#define kPoint16Mask 0x7FFFu

// The data texture's row width in texels, as a power of 2, which gpu_renderer.dart's dataWidthLog2 matches
#define kDataWidthLog2 12u

// Struct sizes in 32-bit words
#define kOpaqueWords 7u
#define kInstanceWords 8u
#define kEdgeWords 2u
#define kSegmentWords 4u
#define kPathDataWords 21u

// The bits of FrameInfo.flags.x
#define kParamUseCurves 1u
#define kParamShowOpaques 2u
#define kParamUseClips 4u

float clamp01(float x) {
  return clamp(x, 0.0, 1.0);
}

#endif
