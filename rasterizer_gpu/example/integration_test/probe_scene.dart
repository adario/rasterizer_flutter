// The format probe's scene, for format_probe_test.dart and defer_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:rasterizer_gpu/rasterizer_gpu.dart';
// The probe's SVG and its check are internal.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/format_probe.dart';
import 'package:rasterizer_gpu_example/goldens.dart';

export 'package:rasterizer_gpu/src/format_probe.dart' show probeSize, probeSvg;

/// Returns the probe's scene, parsed for [gpu] with the renderer [backend].
RasterizerScene probeScene({
  RasterizerBackend? backend,
  RasterizerBackend gpu = RasterizerBackend.gpu,
}) => RasterizerScene.fromSvg(
  utf8.encode(probeSvg),
  backend: backend,
  gpu: gpu,
  maxSize: gpu == RasterizerBackend.mesh ? probeSize.toDouble() : null,
);

/// Renders [scene] in a frame of [renderer] the probe's size, and returns
/// the run.
RasterizerRun renderProbe(RasterizerRenderer renderer, RasterizerScene scene) {
  final frame = renderer.beginFrame(probeSize, probeSize);
  final run = frame.addRun()..add(scene, 1, 0, 0, 1, 0, 0);
  frame.render();
  return run;
}

/// Reads [run]'s pixels back, and returns how they differ from the probe's
/// expected colours, or null if they don't.
Future<String?> checkProbe(RasterizerRun run) async {
  if (run.parts.isEmpty) {
    return 'nothing rendered';
  }
  final part = run.parts.first, image = part.image;
  final data = await readRgba(image);
  final s = part.source, d = part.destination;
  return checkProbePixels(
    Uint8List.sublistView(data!),
    4 * image.width,
    s.left.toInt(),
    s.top.toInt(),
    (
      left: d.left.toInt(),
      top: d.top.toInt(),
      width: d.width.toInt(),
      height: d.height.toInt(),
    ),
  );
}
