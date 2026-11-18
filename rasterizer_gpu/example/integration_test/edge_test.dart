// Checks that each renderer draws the entries near a run's edges, in the app:
//   flutter test integration_test/edge_test.dart -d <device>
//
// As in apps, the run draws in logical pixels, in a picture that a layer
// scales by the device pixel ratio, offset as a game in a larger app. On the
// web, CanvasKit dropped the canvas renderer's scenes near the run's clip,
// such as the last glyph of each of Tube Shooter's HUD lines.
//
// It also checks a run drawn by a RasterizerCanvas under a clip, as a
// letterboxed game's: entries near the clip's edges draw, and the GPU
// renderers render only within the clip, not the entries off it.
//
// Each GPU renderer runs where it's supported.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'web_test.dart';

/// The frame's size in device pixels, and the device pixel ratio.
const width = 1724, height = 1218, ratio = 2.0;

/// Where the game sits in the app, in logical pixels.
const offset = ui.Offset(402, 56);

/// A Y, as Tube Shooter's font draws it, in a 4 by 6 box.
const glyphSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 6">'
    '<path d="M0,0 L2,3 L4,0 M2,3 L2,6" fill="none" stroke="#fff" '
    'stroke-width="0.75" stroke-linecap="square"/></svg>';

/// The glyph's scale, in device pixels.
const scale = 4.0;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    runApp(const SizedBox());
  });

  for (final backend in RasterizerBackend.values) {
    webTest('${backend.name}: entries near the edges draw', () async {
      if (backend != RasterizerBackend.canvas) {
        final support = RasterizerGpu.of(backend).support;
        if (support != RasterizerSupport.supported) {
          markTestSkipped('support ${support.name}');
          return;
        }
      }
      final renderer = await RasterizerRenderer.create(
        slots: 1,
        backend: backend,
      );
      addTearDown(renderer.dispose);
      final glyph = RasterizerScene.fromSvg(
        utf8.encode(glyphSvg),
        backend: backend,
        maxSize: 6 * scale,
      );
      addTearDown(glyph.dispose);

      // Rows along the right edge and columns along the bottom one, at
      // fractional positions, the last of each crossing the edge.
      final positions = [
        for (var k = 0; k < 8; k++) ...[
          (width - 20.8 - 24 * k, 600.0),
          (width - 8.8 - 24 * k, 640.0),
          (800.0, height - 30.8 - 36 * k),
          (840.0, height - 12.8 - 36 * k),
        ],
      ];
      final frame = renderer.beginFrame(width, height);
      final run = frame.addRun();
      for (final (tx, ty) in positions) {
        run.add(glyph, scale, 0, 0, scale, tx, ty);
      }
      frame.render();
      final recorder = ui.PictureRecorder();
      run.draw(
        ui.Canvas(recorder)..translate(offset.dx, offset.dy),
        scale: ratio,
      );
      final picture = recorder.endRecording();
      final builder = ui.SceneBuilder()
        ..pushTransform(
          Float64List.fromList([
            ratio, 0, 0, 0, //
            0, ratio, 0, 0, //
            0, 0, 1, 0, //
            -offset.dx * ratio, -offset.dy * ratio, 0, 1,
          ]),
        )
        ..addPicture(ui.Offset.zero, picture)
        ..pop();
      final scene = builder.build();
      final image = await scene.toImage(width, height);
      final data = await image.toByteData();
      scene.dispose();
      picture.dispose();
      image.dispose();
      final pixels = Uint8List.sublistView(data!);

      /// Whether any pixel of the glyph at [tx], [ty] is drawn.
      bool drawn(double tx, double ty) {
        for (var y = ty.floor(); y < ty + 6 * scale && y < height; y++) {
          for (var x = tx.floor(); x < tx + 4 * scale && x < width; x++) {
            if (pixels[(y * width + x) * 4 + 3] > 0) {
              return true;
            }
          }
        }
        return false;
      }

      final missing = [
        for (final (tx, ty) in positions)
          if (!drawn(tx, ty)) '($tx, $ty)',
      ];
      final line = '${backend.name}: missing $missing';
      // ignore: avoid_print
      print('  $line');
      // On the web, prints go to the browser's console, so the line goes to
      // flutter drive's response data too.
      (binding.reportData ??= {})[backend.name] = line;
      expect(missing, isEmpty);
    });

    webTest("${backend.name}: entries near a clip's edges draw, and the run "
        'renders within the clip', () async {
      if (backend != RasterizerBackend.canvas) {
        final support = RasterizerGpu.of(backend).support;
        if (support != RasterizerSupport.supported) {
          markTestSkipped('support ${support.name}');
          return;
        }
      }
      final renderer = await RasterizerRenderer.create(
        slots: 1,
        backend: backend,
      );
      addTearDown(renderer.dispose);
      final glyph = RasterizerScene.fromSvg(
        utf8.encode(glyphSvg),
        backend: backend,
        maxSize: 6 * scale,
      );
      addTearDown(glyph.dispose);

      // A letterbox's clip, in logical pixels, and in device pixels.
      const clip = ui.Rect.fromLTRB(100.3, 80.6, 700.4, 500.7);
      final device = ui.Rect.fromLTRB(
        clip.left * ratio,
        clip.top * ratio,
        clip.right * ratio,
        clip.bottom * ratio,
      );
      // Rows along the clip's right edge and columns along its bottom one,
      // at fractional positions, the last of each crossing the edge. Then
      // entries off the clip, in the letterbox's bars.
      final positions = [
        for (var k = 0; k < 8; k++) ...[
          (device.right - 20.8 - 24 * k, 600.0),
          (device.right - 8.8 - 24 * k, 640.0),
          (800.0, device.bottom - 30.8 - 36 * k),
          (840.0, device.bottom - 12.8 - 36 * k),
        ],
      ];
      final outside = [(1500.0, 600.0), (800.0, 1100.0), (100.0, 600.0)];
      final frame = renderer.beginFrame(width, height);
      final recorder = ui.PictureRecorder();
      final canvas = RasterizerCanvas()
        ..begin(
          ui.Canvas(recorder)..translate(offset.dx, offset.dy),
          frame,
          ratio,
        )
        ..clipRect(clip);
      for (final (tx, ty) in [...positions, ...outside]) {
        const s = scale / ratio;
        canvas.drawScene(glyph, s, 0, 0, s, tx / ratio, ty / ratio);
      }
      canvas.end();
      frame.render();
      final picture = recorder.endRecording();
      final builder = ui.SceneBuilder()
        ..pushTransform(
          Float64List.fromList([
            ratio, 0, 0, 0, //
            0, ratio, 0, 0, //
            0, 0, 1, 0, //
            -offset.dx * ratio, -offset.dy * ratio, 0, 1,
          ]),
        )
        ..addPicture(ui.Offset.zero, picture)
        ..pop();
      final scene = builder.build();
      final image = await scene.toImage(width, height);
      final data = await image.toByteData();
      scene.dispose();
      picture.dispose();
      image.dispose();
      final pixels = Uint8List.sublistView(data!);

      /// Whether any pixel of the glyph at [tx], [ty] is drawn in the clip.
      bool drawn(double tx, double ty) {
        final bottom = device.bottom.ceil(), right = device.right.ceil();
        for (var y = ty.floor(); y < ty + 6 * scale && y < bottom; y++) {
          for (var x = tx.floor(); x < tx + 4 * scale && x < right; x++) {
            if (pixels[(y * width + x) * 4 + 3] > 0) {
              return true;
            }
          }
        }
        return false;
      }

      final missing = [
        for (final (tx, ty) in positions)
          if (!drawn(tx, ty)) '($tx, $ty)',
      ];
      // The GPU renderers render within 2 pixels of the clip's bounds, which
      // the canvas rounds out to whole logical pixels.
      final within = ui.Rect.fromLTRB(
        clip.left.floor() * ratio - 2,
        clip.top.floor() * ratio - 2,
        clip.right.ceil() * ratio + 2,
        clip.bottom.ceil() * ratio + 2,
      );
      final beyond = [
        for (final run in frame.runs)
          for (final part in run.parts)
            if (within.expandToInclude(part.destination) != within)
              '${part.destination}',
      ];
      final line = '${backend.name}: missing $missing, beyond $beyond';
      // ignore: avoid_print
      print('  $line');
      (binding.reportData ??= {})['${backend.name} clip'] = line;
      expect(missing, isEmpty);
      expect(beyond, isEmpty);
    });
  }
}
