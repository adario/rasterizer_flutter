// Checks RasterizerScene.drawPaths, without a GPU. From this package's folder:
//   flutter test test/draw_paths_test.dart
//
// A canvas scene draws its paths into any canvas, with no frame, as a canvas
// run draws them. So does a scene that switches to a GPU renderer later,
// while it draws with the canvas renderer. A GPU scene, or a disposed one, has
// no paths, so it throws.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/switching.dart';

const _size = 40;

final _bytes = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">'
    '<rect x="4" y="4" width="20" height="20" fill="red"/>'
    '<circle cx="24" cy="24" r="12" fill="none" stroke="blue" '
    'stroke-width="4"/></svg>',
  ),
);

/// The pixels that [draw] draws into a picture, as RGBA.
Future<Uint8List> _pixels(void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  test('a canvas scene draws its paths as a canvas run does', () async {
    for (final scene in [
      RasterizerScene.fromSvg(_bytes, backend: RasterizerBackend.canvas),
      SwitchingScene.fromSvg(_bytes, RasterizerBackend.gpu, null),
    ]) {
      final renderer = await RasterizerRenderer.create(
        slots: 1,
        backend: RasterizerBackend.canvas,
      );
      final frame = renderer.beginFrame(_size, _size);
      final run = frame.addRun()..add(scene, 1, 0, 0, 1, 0, 0, opacity: 0.5);
      frame.render();
      final expected = await _pixels(run.draw);
      final pixels = await _pixels(
        (canvas) => scene.drawPaths(canvas, opacity: 0.5),
      );
      expect(pixels.any((v) => v != 0), isTrue);
      expect(pixels, expected);
      scene.dispose();
      renderer.dispose();
    }
  });

  test('a GPU scene, or a disposed one, has none', () {
    final gpu = RasterizerScene.fromSvg(_bytes, backend: RasterizerBackend.gpu);
    final canvas = ui.Canvas(ui.PictureRecorder());
    expect(() => gpu.drawPaths(canvas), throwsStateError);
    gpu.dispose();
    final switching = SwitchingScene.fromSvg(
      _bytes,
      RasterizerBackend.gpu,
      null,
    )..dispose();
    expect(() => switching.drawPaths(canvas), throwsStateError);
  });
}
