// Checks a GPU run's paint, in the app:
//   flutter test integration_test/run_paint_test.dart -d <device>
//
// A run's parts are the rectangles of atlas pages that its entries were
// rasterized into. A run drawn with a paint draws its parts' images with
// that paint. The test compares that with the same run drawn into a layer
// with the paint, clipped to the run's parts, over a background so that
// blend modes show. It does so for a run of one part, drawn as an image, and
// a run of two, drawn as an atlas. On Linux's OpenGL ES, the run draws
// through a layer too, so both are alike.
//
// It also checks entries' color transforms, which the core applies to each
// path's color. It compares them with each entry drawn in a layer with the
// transform's filter.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

const size = 128;

/// A red square, a gradient rectangle, and a translucent blue rectangle over
/// both, with a stroke: edges, gradients and overlapping translucent paths.
const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<defs><linearGradient id="g"><stop offset="0" stop-color="#20c060"/>'
    '<stop offset="1" stop-color="#f0e020"/></linearGradient></defs>'
    '<rect x="10" y="10" width="40" height="40" fill="red"/>'
    '<rect x="10" y="60" width="40" height="30" fill="url(#g)"/>'
    '<rect x="30" y="30" width="60" height="40" fill="#2040ff" '
    'fill-opacity="0.6"/>'
    '<path d="M20,95 L90,95" stroke="#202020" stroke-width="4"/></svg>';

/// A greyscale color matrix, which applies to unpremultiplied RGBA.
const greyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
];

final paints = <String, ui.Paint>{
  'tint srcATop': ui.Paint()
    ..colorFilter = const ui.ColorFilter.mode(
      Color(0xcc00ff00),
      ui.BlendMode.srcATop,
    ),
  'modulate': ui.Paint()
    ..colorFilter = const ui.ColorFilter.mode(
      Color(0xff80c0ff),
      ui.BlendMode.modulate,
    ),
  'greyscale matrix': ui.Paint()
    ..colorFilter = const ui.ColorFilter.matrix(greyscale),
  'alpha 0.5': ui.Paint()..color = const Color(0x80000000),
  'multiply': ui.Paint()..blendMode = ui.BlendMode.multiply,
  'invertColors': ui.Paint()..invertColors = true,
  // It changes what's under the gaps between the parts, so the run draws it
  // in a layer around them.
  'srcIn': ui.Paint()..blendMode = ui.BlendMode.srcIn,
};

/// Color transforms for entries, which the core applies to each path's
/// color: a tint, a tint at about half alpha, greyscale, dimming with an
/// offset, and sepia.
///
/// Sepia's results leave the range from 0 to 1, and the core clamps them per
/// path rather than per pixel.
final colorTransforms = <String, RasterizerColorTransform>{
  'tint': RasterizerColorTransform.mode(
    const Color(0xcc00ff00),
    ui.BlendMode.srcATop,
  )!,
  'half orange': RasterizerColorTransform.mode(
    const Color(0x80ffa000),
    ui.BlendMode.srcATop,
  )!,
  'greyscale': RasterizerColorTransform.matrix(greyscale)!,
  'dim': RasterizerColorTransform.matrix(const [
    0.8, 0, 0, 0, 25, //
    0, 0.8, 0, 0, 25, //
    0, 0, 0.8, 0, 25, //
    0, 0, 0, 1, 0,
  ])!,
  'sepia': RasterizerColorTransform.matrix(const [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ])!,
};

/// Layouts of a run: its entries' scale, their positions, and how many parts
/// the run has.
const layouts = {
  'one part': (size / 100, [(0.0, 0.0)], 1),
  'two parts': (size / 200, [(0.0, 0.0), (size / 2, size / 2)], 2),
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    RasterizerGpu.allowOpenGles = true;
    runApp(const SizedBox());
    await RasterizerGpu.initialize();
  });

  testWidgets("a GPU run's paint gives a layer's pixels", (_) async {
    // Support is known once initialized: on OpenGL ES, once the self-test
    // has run.
    if (RasterizerGpu.support != RasterizerSupport.supported) {
      markTestSkipped('support ${RasterizerGpu.support.name}');
      return;
    }
    final renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.gpu,
    );
    final scene = RasterizerScene.fromSvg(
      utf8.encode(svg),
      backend: RasterizerBackend.gpu,
    );

    /// Draws the run of [layout] over a background, and reads it back as
    /// premultiplied RGBA.
    ///
    /// The run draws with [paint], or, if [layer], in a layer with [paint],
    /// bounded by its parts.
    Future<Uint8List> render(
      String layout,
      ui.Paint paint, {
      required bool layer,
    }) async {
      final (s, at, parts) = layouts[layout]!;
      final frame = renderer.beginFrame(size, size);
      final run = frame.addRun();
      for (final (x, y) in at) {
        run.add(scene, s, 0, 0, s, x, y);
      }
      frame.render();
      expect(run.parts.length, parts, reason: layout);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const Color(0xff808040), ui.BlendMode.src);
      if (layer) {
        final bounds = run.parts
            .map((part) => part.destination)
            .reduce((a, b) => a.expandToInclude(b));
        // Clip too, as Impeller takes a layer's bounds as a hint only.
        canvas
          ..save()
          ..clipRect(bounds)
          ..saveLayer(bounds, paint);
        run.draw(canvas);
        canvas
          ..restore()
          ..restore();
      } else {
        run.draw(canvas, paint: paint);
      }
      final picture = recorder.endRecording(),
          image = await picture.toImage(size, size);
      final data = await image.toByteData();
      picture.dispose();
      image.dispose();
      return Uint8List.sublistView(data!);
    }

    for (final layout in layouts.keys) {
      for (final MapEntry(key: paintName, value: paint) in paints.entries) {
        final name = '$layout, $paintName';
        final painted = await render(layout, paint, layer: false);
        final layered = await render(layout, paint, layer: true);
        var maxDiff = 0, over1 = 0, over2 = 0;
        for (var p = 0; p < painted.length; p += 4) {
          var pixel = 0;
          for (var k = 0; k < 4; k++) {
            final d = (painted[p + k] - layered[p + k]).abs();
            if (d > pixel) {
              pixel = d;
            }
          }
          if (pixel > maxDiff) {
            maxDiff = pixel;
          }
          if (pixel > 1) {
            over1++;
          }
          if (pixel > 2) {
            over2++;
          }
        }
        final line =
            '$name: max diff $maxDiff/255, $over1 pixels over 1/255, '
            '$over2 over 2/255';
        // ignore: avoid_print
        print('  $line');
        (binding.reportData ??= {})[name] = line;
        // Only rounding differs: the filter applies either to the image's
        // texels or to the layer's, which hold the same 8-bit values.
        expect(maxDiff, lessThanOrEqualTo(2), reason: name);
      }
    }
    scene.dispose();
    renderer.dispose();
  });

  testWidgets("a GPU entry's color transform gives a layer's pixels", (
    _,
  ) async {
    if (RasterizerGpu.support != RasterizerSupport.supported) {
      markTestSkipped('support ${RasterizerGpu.support.name}');
      return;
    }
    final renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.gpu,
    );
    final scene = RasterizerScene.fromSvg(
      utf8.encode(svg),
      backend: RasterizerBackend.gpu,
    );
    final (s, at, _) = layouts['two parts']!;

    /// Draws two entries over a background, and reads them back as
    /// premultiplied RGBA.
    ///
    /// The entries go in one run, with [transforms] as their color
    /// transforms. Or, if [layer], each goes in a run of its own, drawn in a
    /// layer with its transform's filter.
    Future<Uint8List> render(
      List<RasterizerColorTransform> transforms, {
      required bool layer,
    }) async {
      final frame = renderer.beginFrame(size, size);
      final runs = <RasterizerRun>[];
      for (final (i, (x, y)) in at.indexed) {
        if (layer || runs.isEmpty) {
          runs.add(frame.addRun());
        }
        runs.last.add(
          scene,
          s,
          0,
          0,
          s,
          x,
          y,
          colorTransform: layer ? null : transforms[i],
        );
      }
      frame.render();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const Color(0xff808040), ui.BlendMode.src);
      for (final (i, run) in runs.indexed) {
        if (!layer) {
          run.draw(canvas);
          continue;
        }
        final bounds = run.parts.first.destination;
        canvas
          ..save()
          ..clipRect(bounds)
          ..saveLayer(bounds, ui.Paint()..colorFilter = transforms[i].filter);
        run.draw(canvas);
        canvas
          ..restore()
          ..restore();
      }
      final picture = recorder.endRecording(),
          image = await picture.toImage(size, size);
      final data = await image.toByteData();
      picture.dispose();
      image.dispose();
      return Uint8List.sublistView(data!);
    }

    final names = colorTransforms.keys.toList();
    for (var i = 0; i < names.length; i++) {
      // Each transform on one entry, and the next one on the other entry.
      final pair = [names[i], names[(i + 1) % names.length]];
      final transforms = [for (final n in pair) colorTransforms[n]!];
      final name = 'color transforms ${pair.join(' and ')}';
      final folded = await render(transforms, layer: false);
      final layered = await render(transforms, layer: true);
      // Sepia takes the translucent blue rectangle, and what's under it, out
      // of range. The core clamps per path, and the layer per pixel, so skip
      // that rectangle, with its edges, in a sepia entry.
      final outOfRange = [
        for (final (j, (x, y)) in at.indexed)
          if (pair[j] == 'sepia')
            ui.Rect.fromLTRB(
              x + 30 * s - 1,
              y + 30 * s - 1,
              x + 90 * s + 1,
              y + 70 * s + 1,
            ),
      ];
      var maxDiff = 0, over2 = 0, maxDiffInRange = 0;
      for (var p = 0; p < folded.length; p += 4) {
        var pixel = 0;
        for (var k = 0; k < 4; k++) {
          final d = (folded[p + k] - layered[p + k]).abs();
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
        final center = Offset(p ~/ 4 % size + 0.5, p ~/ 4 ~/ size + 0.5);
        if (pixel > maxDiffInRange &&
            !outOfRange.any((rect) => rect.contains(center))) {
          maxDiffInRange = pixel;
        }
      }
      final line =
          '$name: max diff $maxDiff/255, $over2 pixels over 2/255, '
          '$maxDiffInRange/255 in range';
      // ignore: avoid_print
      print('  $line');
      (binding.reportData ??= {})[name] = line;
      // Elsewhere, only rounding differs.
      expect(maxDiffInRange, lessThanOrEqualTo(2), reason: name);
    }
    scene.dispose();
    renderer.dispose();
  });
}
