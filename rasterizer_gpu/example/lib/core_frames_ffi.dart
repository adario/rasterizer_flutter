// The core's FFI API is internal, but the example checks frames with it.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Calls [onFrame] with the entry count and the size in bytes of each frame
/// that the C++ core writes for [renderer], if it's the GPU renderer.
///
/// A core frame holds the bytes that the GPU renderer uploads for an atlas
/// page, and the entries that say how to draw them.
void watchCoreFrames(
  RasterizerRenderer renderer,
  void Function(int entries, int bytes) onFrame,
) {
  if (renderer is ra.AtlasRenderer) {
    renderer.debugFrameWritten = (page, frame) =>
        onFrame(frame.entries.length, frame.size);
  }
}
