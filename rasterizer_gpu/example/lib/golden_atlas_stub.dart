import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'goldens.dart';

/// Returns null: without dart:ffi, there's no GPU renderer, and so no atlas
/// frames.
Future<FrameRenders>? renderAtlasFrame(
  String name,
  RasterizerFrame frame,
  RasterizerRenderer renderer,
  bool curves,
  String Function(int entry) svgOf,
  String? recordDir,
) => null;
