// Checks each renderer's entry opacity, in the app:
//   flutter test integration_test/opacity_test.dart -d <device>
//
// Two overlapping scenes, each faded, draw in one run: one batch of entries
// that draws as one image. The result must match each scene drawn opaque on
// its own, then composited by hand. Opacity scales each path's alpha, so the
// faded top scene must draw over the faded bottom one. Opaque, its whole
// cells would draw first instead, in the core's pass for opaque cells.
// Neither scene's paths overlap each other, so fading per path and per scene
// give the same result here.
//
// Each GPU renderer runs where it's supported: on OpenGL ES, once its
// self-test has passed.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'web_test.dart';

const size = 128;

/// A red square and a gradient rectangle below it.
const bottomSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<defs><linearGradient id="g"><stop offset="0" stop-color="#20c060"/>'
    '<stop offset="1" stop-color="#f0e020"/></linearGradient></defs>'
    '<rect x="10" y="10" width="40" height="40" fill="red"/>'
    '<rect x="10" y="60" width="40" height="30" fill="url(#g)"/></svg>';

/// A blue rectangle over both of the bottom's paths, and a stroke beneath it.
///
/// The rectangle is wide enough to cover whole cells of the core's grid,
/// which the core treats as opaque.
const topSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<rect x="30" y="30" width="60" height="40" fill="#2040ff"/>'
    '<path d="M20,95 L90,95" stroke="#202020" stroke-width="4"/></svg>';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    RasterizerGpu.allowOpenGles = true;
    runApp(const SizedBox());
    await RasterizerGpu.initialize();
    await RasterizerGpu.of(RasterizerBackend.mesh).initialize();
  });

  for (final backend in RasterizerBackend.values) {
    webTest(
      "${backend.name}: an entry's opacity scales its paths' alpha",
      () async {
        // Support is known once initialized: on OpenGL ES, once the
        // renderer's self-test has run.
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
        RasterizerScene scene(String svg) {
          final scene = RasterizerScene.fromSvg(
            utf8.encode(svg),
            backend: backend,
            maxSize: size.toDouble(),
          );
          addTearDown(scene.dispose);
          return scene;
        }

        final bottom = scene(bottomSvg), top = scene(topSvg);

        /// Renders [entries] as the frame's only run. Returns its pixels, as
        /// premultiplied RGBA, and the frame's entry count.
        Future<(Uint8List, int)> render(
          List<(RasterizerScene, double)> entries,
        ) async {
          final frame = renderer.beginFrame(size, size);
          final run = frame.addRun();
          const s = size / 100;
          for (final (scene, opacity) in entries) {
            run.add(scene, s, 0, 0, s, 0, 0, opacity: opacity);
          }
          frame.render();
          final recorder = ui.PictureRecorder();
          run.draw(ui.Canvas(recorder));
          final picture = recorder.endRecording(),
              image = await picture.toImage(size, size);
          final data = await image.toByteData();
          picture.dispose();
          image.dispose();
          return (Uint8List.sublistView(data!), frame.entryCount);
        }

        final (b, _) = await render([(bottom, 1)]);
        final (t, _) = await render([(top, 1)]);
        for (final (ob, ot) in [(1.0, 1.0), (0.5, 0.8), (0.3, 0.3)]) {
          final (faded, count) = await render([
            (bottom, ob),
            (top, ot),
            (top, 0),
          ]);
          expect(count, 2, reason: "an entry whose opacity is 0 isn't added");
          var maxDiff = 0, over2 = 0;
          for (var p = 0; p < faded.length; p += 4) {
            final ta = t[p + 3] * ot / 255;
            var pixel = 0;
            for (var k = 0; k < 4; k++) {
              final expected = t[p + k] * ot + b[p + k] * ob * (1 - ta);
              final d = (faded[p + k] - expected).abs().round();
              if (d > pixel) {
                pixel = d;
              }
            }
            if (pixel > maxDiff) {
              maxDiff = pixel;
            }
            if (pixel > 2) {
              over2++;
            }
          }
          final line =
              '${backend.name}, bottom at $ob, top at $ot: max diff '
              '$maxDiff/255, $over2 pixels over 2/255';
          // ignore: avoid_print
          print('  $line');
          // On the web, prints go to the browser's console, so the line goes
          // to flutter drive's response data too.
          (binding.reportData ??= {})['${backend.name} $ob $ot'] = line;
          // Where both scenes' edges cross a pixel, multisampling, as on
          // Android, blends their samples together, which compositing
          // afterwards can't do. So 1 pixel in 1000 may differ.
          expect(
            over2,
            lessThanOrEqualTo(size * size ~/ 1000),
            reason: 'bottom at $ob, top at $ot',
          );
        }
      },
    );
  }
}
