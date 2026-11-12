// Checks RasterizerColorTransform, and the canvas renderer's entries drawn
// with one. From this package's folder, with and without Impeller:
//   flutter test test/color_transform_test.dart [--enable-impeller]
//
// A color transform is a color filter that can apply to each of an entry's
// paths, with the same pixels as in a layer. The canvas renderer filters each
// path. The test draws each entry by hand in a layer with the filter, as a
// sprite would be drawn, and compares.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/canvas_renderer.dart';
import 'package:rasterizer_gpu/src/svg_paths/svg_paths.dart';

const _width = 200, _height = 160;

// A fill, a translucent stroke over it, and a gradient that fades, over both.
final _scene = CanvasScene(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
      'viewBox="0 0 100 100"><defs><linearGradient id="g">'
      '<stop offset="0" stop-color="#20c060"/>'
      '<stop offset="1" stop-color="#f0e020" stop-opacity="0.6"/>'
      '</linearGradient></defs>'
      '<rect x="20" y="20" width="40" height="30" fill="red"/>'
      '<path d="M30,80 L50,30 L70,80" fill="none" stroke="blue" '
      'stroke-width="10" stroke-opacity="0.7"/>'
      '<rect x="40" y="40" width="40" height="40" fill="url(#g)"/></svg>',
    ),
  ),
);

final _tint = RasterizerColorTransform.mode(
  const ui.Color(0xCC00FF00),
  ui.BlendMode.srcATop,
)!;
final _greyscale = RasterizerColorTransform.matrix(const [
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
])!;
// Darker, then brighter by an offset, so colors stay from 0 to 255.
final _dim = RasterizerColorTransform.matrix(const [
  0.8, 0, 0, 0, 25, //
  0, 0.8, 0, 0, 25,
  0, 0, 0.8, 0, 25,
  0, 0, 0, 1, 0,
])!;

// The entries' transforms, opacities and color transforms. The first is
// scaled by 1.5, moved and tinted. The second is turned a quarter turn, faded
// and greyscale. The third is smaller, and tinted orange at about half. The
// fourth is dimmed, and the last is plain.
final _entries = [
  ([1.5, 0.0, 0.0, 1.5, 10.0, 5.0], 1.0, _tint),
  ([0.0, 1.0, -1.0, 0.0, 190.0, 40.0], 0.8, _greyscale),
  (
    [0.5, 0.0, 0.0, 0.5, 120.0, 100.0],
    1.0,
    RasterizerColorTransform.mode(
      const ui.Color(0x80FFC040),
      ui.BlendMode.srcATop,
    ),
  ),
  ([0.4, 0.0, 0.0, 0.4, 150.0, 0.0], 1.0, _dim),
  ([0.3, 0.0, 0.0, 0.3, 0.0, 120.0], 1.0, null),
];

final _renderer = CanvasRenderer(1);

Float64List _matrix(List<double> e) => Float64List.fromList([
  e[0], e[1], 0, 0, //
  e[2], e[3], 0, 0,
  0, 0, 1, 0,
  e[4], e[5], 0, 1,
]);

/// Draws [_entries] by hand, each in a layer with its filter. Each fill and
/// stroke goes in a layer of its own with the entry's opacity.
void _reference(ui.Canvas canvas) {
  canvas.clipRect(
    ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
  );
  for (final (e, opacity, transform) in _entries) {
    final filter = transform?.filter;
    final faded = ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, opacity);
    canvas
      ..save()
      ..transform(_matrix(e))
      ..translate(_svg.origin.dx, _svg.origin.dy);
    if (filter != null) {
      canvas.saveLayer(null, ui.Paint()..colorFilter = filter);
    }
    for (final path in _svg.paths) {
      for (final paint in [path.paint.fill, path.paint.stroke]) {
        if (paint == null) {
          continue;
        }
        canvas
          ..saveLayer(null, faded)
          ..drawPath(path.path, paint)
          ..restore();
      }
    }
    if (filter != null) {
      canvas.restore();
    }
    canvas.restore();
  }
}

Future<Uint8List> _pixels(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

int _maxDiff(Uint8List a, Uint8List b) {
  var m = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > m) {
      m = d;
    }
  }
  return m;
}

/// [m], to 3 decimals, for comparing.
List<double> _rounded(Float32List m) => [
  for (final v in m) (v * 1000).roundToDouble() / 1000,
];

void main() {
  group('RasterizerColorTransform', () {
    test('mode filters, premultiplied', () {
      // Green at 0.8 alpha. srcATop keeps the alpha, and mixes in 0.8 green
      // times it.
      expect(_rounded(_tint.values), [
        0.2, 0, 0, 0, //
        0, 0.2, 0, 0.8,
        0, 0, 0.2, 0,
        0, 0, 0, 1,
      ]);
      const c = ui.Color(0x80FF8000); // Orange at about 0.5 alpha.
      List<double> m(ui.BlendMode mode) =>
          _rounded(RasterizerColorTransform.mode(c, mode)!.values);
      double r(double v) => (v * 1000).roundToDouble() / 1000;
      final t = 0x80 / 255, rt = r(t), gt = r(t * 0x80 / 255), st = r(1 - t);
      expect(m(ui.BlendMode.srcATop), [
        st, 0, 0, rt, 0, st, 0, gt, 0, 0, st, 0, 0, 0, 0, 1, //
      ]);
      expect(m(ui.BlendMode.dst), [
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, //
      ]);
      expect(m(ui.BlendMode.clear), List.filled(16, 0.0));
    });

    test("its values can't be modified", () {
      expect(() => _tint.values[0] = 1, throwsUnsupportedError);
      expect(() => _greyscale.values[0] = 1, throwsUnsupportedError);
    });

    test('apply makes a color as the filter makes its pixels', () {
      List<double> rgba(ui.Color c) =>
          _rounded(Float32List.fromList([c.r, c.g, c.b, c.a]));
      const red = ui.Color(0xFFFF0000);
      // Green at 0.8 over red, whatever red's alpha.
      expect(rgba(_tint.apply(red)), [0.2, 0.8, 0, 1]);
      expect(rgba(_tint.apply(red.withValues(alpha: 0.5))), [0.2, 0.8, 0, 0.5]);
      expect(rgba(_greyscale.apply(red)), [0.213, 0.213, 0.213, 1]);
      final clear = RasterizerColorTransform.mode(red, ui.BlendMode.clear)!;
      expect(clear.apply(red).a, 0);
    });

    test('alpha-keeping matrices, offsets scaled by alpha', () {
      expect(_rounded(_greyscale.values), [
        0.213, 0.715, 0.072, 0, //
        0.213, 0.715, 0.072, 0,
        0.213, 0.715, 0.072, 0,
        0, 0, 0, 1,
      ]);
      expect(_rounded(_dim.values), [
        0.8, 0, 0, 0.098, //
        0, 0.8, 0, 0.098,
        0, 0, 0.8, 0.098,
        0, 0, 0, 1,
      ]);
    });

    test('others are not folded', () {
      const green = ui.Color(0xCC00FF00);
      for (final mode in [
        ui.BlendMode.srcOver,
        ui.BlendMode.multiply,
        ui.BlendMode.srcOut,
        // Modes that scale alpha, which would let overlapping paths show
        // through each other.
        ui.BlendMode.modulate,
        ui.BlendMode.srcIn,
        ui.BlendMode.dstIn,
        ui.BlendMode.dstOut,
      ]) {
        expect(RasterizerColorTransform.mode(green, mode), isNull);
      }
      expect(
        RasterizerColorTransform.mode(
          const ui.Color.from(
            alpha: 1,
            red: 0,
            green: 1,
            blue: 0,
            colorSpace: ui.ColorSpace.displayP3,
          ),
          ui.BlendMode.srcATop,
        ),
        isNull,
        reason: 'not sRGB',
      );
      for (final values in <List<double>>[
        // A matrix that scales alpha, one whose colors depend on alpha, and
        // one of the wrong length.
        [1.0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0.5, 0],
        [1.0, 0, 0, 0.5, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
        [1.0, 0, 0, 0],
      ]) {
        expect(RasterizerColorTransform.matrix(values), isNull);
      }
    });

    test('of knows only the filters it made', () {
      expect(RasterizerColorTransform.of(_tint.filter), same(_tint));
      expect(_tint.filter, isA<ui.ColorFilter>());
      // An equal filter made otherwise isn't known, as profile and release
      // builds can't read it back.
      expect(
        RasterizerColorTransform.of(
          const ui.ColorFilter.mode(ui.Color(0xCC00FF00), ui.BlendMode.srcATop),
        ),
        isNull,
      );
      expect(
        RasterizerColorTransform.of(const ui.ColorFilter.linearToSrgbGamma()),
        isNull,
      );
    });
  });

  tearDown(() => RasterizerGpu.canvasPictures = true);

  for (final pictures in [true, false]) {
    test('canvas entries filter each path as a layer would, '
        '${pictures ? 'with' : 'without'} pictures', () async {
      RasterizerGpu.canvasPictures = pictures;
      final run = _renderer.beginFrame(_width, _height).addRun();
      for (final (e, opacity, transform) in _entries) {
        run.add(
          _scene,
          e[0],
          e[1],
          e[2],
          e[3],
          e[4],
          e[5],
          opacity: opacity,
          colorTransform: transform,
        );
      }
      run.place();
      final actual = await _pixels(run.draw);
      final expected = await _pixels(_reference);
      final diff = _maxDiff(actual, expected);
      // ignore: avoid_print
      print('  max diff $diff/255');
      // The reference's nested layers each round to 8 bits. So it may differ
      // by 2 on Skia, and by 3 on Impeller.
      expect(diff, lessThanOrEqualTo(3));
      expect(actual.any((v) => v != 0), isTrue);
    });
  }
}

/// [_scene]'s SVG paths.
SvgPaths get _svg => _scene.paths as SvgPaths;
