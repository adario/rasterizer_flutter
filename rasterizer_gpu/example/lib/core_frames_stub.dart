import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Does nothing: without dart:ffi, there's no GPU renderer, and so no core
/// frames.
void watchCoreFrames(
  RasterizerRenderer renderer,
  void Function(int entries, int bytes) onFrame,
) {}
