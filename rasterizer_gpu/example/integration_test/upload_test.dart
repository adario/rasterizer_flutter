// Checks the GPU renderer's upload, in the app:
//   flutter test integration_test/upload_test.dart -d <device>
//
// The renderer keeps a staging buffer and a data texture for each of its
// frame slots. They grow to 4/3 of the rows that a frame needs, and shrink
// when they're over 1 MB and more than 5 times what a frame needs. The test
// renders frames that grow and shrink across those thresholds. It reads each
// one back, and compares it with the same frame from a renderer with
// debugFreshFrameBuffers, which uploads every frame through new buffers. The
// pixels must match within 1/255, as the shaders don't read the rows past a
// frame's, which hold an earlier frame's bytes.
//
// Some frames render 4 at a time, before the slots' blits can complete, so a
// slot is reused while its buffer is still being copied from. On OpenGL ES,
// as on an Android emulator built with IMPELLER_BACKEND=opengles, the test
// runs once the GPU renderer's self-test passes.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The GPU renderer's class is internal, and the test needs it to set
// debugFreshFrameBuffers.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu_example/goldens.dart';
import 'package:rasterizer_gpu_example/scenes.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;
  runApp(const SizedBox());
  await RasterizerGpu.initialize();
  if (RasterizerGpu.support != RasterizerSupport.supported) {
    test(
      'no GPU renderer here',
      () {},
      skip:
          'support ${RasterizerGpu.support.name}: '
          '${RasterizerGpu.supportDetail}',
    );
    return;
  }

  const viewport = (1000, 800), most = 1500;
  final motion = AtlasMotion(entries: most);
  late List<RasterizerScene> svgs;

  setUpAll(
    () => svgs = [
      for (final s in generatedSvgs(50))
        RasterizerScene.fromSvg(utf8.encode(s)),
    ],
  );
  tearDownAll(() {
    for (final s in svgs) {
      s.dispose();
    }
  });

  /// Renders a frame of [count] moving entries at [time] with [renderer], and
  /// returns the images of its atlas pages.
  List<ui.Image> render(ra.AtlasRenderer renderer, int count, double time) {
    final (w, h) = viewport;
    final size = ui.Size(w.toDouble(), h.toDouble());
    final frame = renderer.beginFrame(w, h);
    final run = frame.addRun();
    for (var i = 0; i < count; i++) {
      final (a, b, c, d, tx, ty) = motion.transform(i, time, size);
      run.add(svgs[motion.svg(i)], a, b, c, d, tx, ty);
    }
    frame.render();
    return {for (final part in run.parts) part.image}.toList();
  }

  /// Reads [images] back as RGBA bytes.
  Future<List<Uint8List>> read(List<ui.Image> images) async => [
    for (final image in images) Uint8List.sublistView((await readRgba(image))!),
  ];

  test('frames that grow and shrink draw as with fresh buffers', () async {
    final subject = await RasterizerRenderer.create(
      backend: RasterizerBackend.gpu,
    ) as ra.AtlasRenderer;
    final fresh = await RasterizerRenderer.create(
      backend: RasterizerBackend.gpu,
    ) as ra.AtlasRenderer;
    fresh.debugFreshFrameBuffers = true;
    final sizes = <int>[];
    subject.debugFrameWritten = (_, frame) => sizes.add(frame.size);
    // Each count lasts 3 frames, one per slot. The counts grow a little, then
    // a lot, shrink to a light frame, and grow again.
    const counts = [1, 2, 4, 30, 40, most, most, 1, 1, 200, most, 5];
    final failures = <String>[];
    try {
      var time = 0.0;
      for (final (k, count) in counts.indexed) {
        for (var f = 0; f < 3; f++, time += 0.1) {
          final at = 'count $count frame $f';
          // Render 3 frames first, so that the frame read below is the 4th in
          // a row, and reuses the first one's slot.
          if (k.isOdd && f == 0) {
            for (var i = 0; i < 3; i++) {
              render(subject, count, time);
              render(fresh, count, time);
            }
          }
          final actual = await read(render(subject, count, time));
          final expected = await read(render(fresh, count, time));
          if (actual.length != expected.length) {
            failures.add('$at: ${actual.length} pages, not ${expected.length}');
            continue;
          }
          for (var p = 0; p < actual.length; p++) {
            final a = actual[p], e = expected[p];
            var differ = 0, largest = 0, first = -1;
            for (var i = 0; i < a.length; i++) {
              final d = (a[i] - e[i]).abs();
              if (d == 0) {
                continue;
              }
              if (first < 0) {
                first = i ~/ 4;
              }
              differ++;
              if (d > largest) {
                largest = d;
              }
            }
            // On macOS, the same frame rendered twice sometimes has a few
            // pixels 1/255 apart, with the earlier upload code too.
            if (largest > 1) {
              failures.add(
                '$at: page $p differs in $differ bytes, up to $largest/255, '
                'from pixel $first of ${a.length ~/ 4}',
              );
            }
          }
          WidgetsBinding.instance.scheduleFrame();
          await WidgetsBinding.instance.endOfFrame;
        }
      }
    } finally {
      subject.dispose();
      fresh.dispose();
    }
    // Check that the frames crossed the thresholds. The largest grows the
    // buffer and the texture to over 1 MB, and to over 5 times the rows of
    // the smallest, which shrinks them back.
    const rowBytes = 16 << 12;
    final rows = [for (final s in sizes) (s + rowBytes - 1) ~/ rowBytes];
    // ignore: avoid_print
    print('  rows ${rows.toSet().toList()..sort()}');
    final least = rows.reduce((a, b) => a < b ? a : b);
    final grown = rows.reduce((a, b) => a > b ? a : b) * 4 ~/ 3;
    expect(grown * rowBytes, greaterThan(1000000));
    expect(grown ~/ least, greaterThan(5));
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
