// Checks radial gradients on the pixel column through their centers, with
// each GPU renderer, in flutter_tester on macOS:
//   flutter test --enable-impeller --enable-flutter-gpu test/radial_test.dart
//
// On that column, the GPU renderer's shaders once read a radial gradient as
// linear, and the pixels on one side of the center took the first stop's
// color. That happened where the GPU interpolated the gradient's x to exactly
// 0, which depends on the shape's size and place. The test draws translucent
// gradients, which the instances pass paints, and opaque ones, whose inner
// cells the opaques pass paints, where flutter_tester on an Apple M1 showed
// the bug. Each column pixel must match its neighbors. The app on macOS
// didn't show it for any shape tried, so this isn't an integration test.
//
// The canvas renderer draws with Flutter's gradients, which Impeller
// dithers, so neighboring pixels differ there.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// The frame's size in pixels.
const width = 1024, height = 512;

/// The gradients' radius, and their rectangles' height.
const radius = 100, rectHeight = 240;

/// Where each gradient's rectangle goes, its width, odd so that its center is
/// a pixel's center, and its opacity.
const rects = [
  (x: 143, y: 8, width: 129, opacity: 0.6),
  (x: 279, y: 8, width: 257, opacity: 0.6),
  (x: 143, y: 264, width: 129, opacity: 1.0),
  (x: 279, y: 264, width: 257, opacity: 1.0),
];

/// An SVG of a rectangle [w] wide, filled with a radial gradient of
/// [opacity] centered on a pixel's center at its middle.
String svg(int w, double opacity) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="$w" '
    'height="$rectHeight" viewBox="0 0 $w $rectHeight"><defs>'
    '<radialGradient id="g" gradientUnits="userSpaceOnUse" cx="${w / 2}" '
    'cy="${rectHeight / 2 + 0.5}" r="$radius">'
    '<stop offset="0" stop-color="#ff0000" stop-opacity="$opacity"/>'
    '<stop offset="1" stop-color="#0000ff" stop-opacity="$opacity"/>'
    '</radialGradient></defs>'
    '<rect width="$w" height="$rectHeight" fill="url(#g)"/></svg>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final backend in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
    test('${backend.name}: radial gradients are round on the column '
        'through their centers', () async {
      final support = RasterizerGpu.of(backend).support;
      if (support != RasterizerSupport.supported) {
        markTestSkipped('support ${support.name}');
        return;
      }
      final renderer = await RasterizerRenderer.create(
        slots: 1,
        backend: backend,
      );
      addTearDown(renderer.dispose);
      final frame = renderer.beginFrame(width, height);
      final run = frame.addRun();
      for (final rect in rects) {
        final scene = RasterizerScene.fromSvg(
          utf8.encode(svg(rect.width, rect.opacity)),
          backend: backend,
          maxSize: math.max(rect.width, rectHeight).toDouble(),
        );
        addTearDown(scene.dispose);
        run.add(scene, 1, 0, 0, 1, rect.x.toDouble(), rect.y.toDouble());
      }
      frame.render();
      final recorder = ui.PictureRecorder();
      run.draw(ui.Canvas(recorder));
      final picture = recorder.endRecording(),
          image = await picture.toImage(width, height);
      final data = await image.toByteData();
      picture.dispose();
      image.dispose();
      final pixels = Uint8List.sublistView(data!);

      for (final rect in rects) {
        final column = rect.x + rect.width ~/ 2;
        final row = rect.y + rectHeight ~/ 2;

        /// The largest difference between a channel of the column's pixel
        /// in row [y] and the mean of its neighbors' on either side, which
        /// are as far from the center.
        int difference(int y) {
          var most = 0;
          for (var channel = 0; channel < 4; channel++) {
            int at(int x) => pixels[(y * width + x) * 4 + channel];
            final mean = (at(column - 1) + at(column + 1)) / 2;
            final d = (at(column) - mean).abs().round();
            most = d > most ? d : most;
          }
          return most;
        }

        // The rows from 10 pixels off the center to 10 inside the radius, on
        // both sides. There, the column's pixels are under 0.05 pixels
        // nearer the center than their neighbors.
        final wrong = [
          for (var d = 10; d < radius - 10; d++)
            for (final y in [row - d, row + d])
              if (difference(y) > 2) y,
        ];
        expect(
          wrong,
          isEmpty,
          reason: '${rect.width} wide, opacity ${rect.opacity}, wrong rows',
        );
      }
    });
  }
}
