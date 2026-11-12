// Checks the canvas renderer's entry opacity. From this package's folder, with
// and without Impeller:
//   flutter test test/canvas_opacity_test.dart [--enable-impeller]
//
// An entry's opacity scales each of its paths' alpha, as with the GPU
// renderers, so a scene's paths that overlap show through each other. The
// scene has a fill, a stroke over it, and a gradient over both. The test draws
// each path by hand in a layer of its own, with the opacity, and compares. The
// renderer scales a gradient's alpha by its paint's color's alpha, which Skia
// and Impeller both apply to shaders.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/canvas_renderer.dart';
import 'package:rasterizer_gpu/src/svg_paths/svg_paths.dart';

const _width = 200, _height = 160;

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
      'stroke-width="10"/>'
      '<rect x="40" y="40" width="40" height="40" fill="url(#g)"/></svg>',
    ),
  ),
);

// The entries' transforms, then their opacities. The first is scaled by 1.5,
// moved and faded. The second is turned a quarter turn, and faded less. The
// third is opaque, so it draws as a picture when pictures are on.
const _entries = [
  [1.5, 0.0, 0.0, 1.5, 10.0, 5.0, 0.5],
  [0.0, 1.0, -1.0, 0.0, 190.0, 40.0, 0.8],
  [0.5, 0.0, 0.0, 0.5, 120.0, 100.0, 1.0],
];

final _renderer = CanvasRenderer(1);

/// A new frame's run of [_entries], and of an entry whose opacity is 0.
CanvasRun _run() {
  final run = _renderer.beginFrame(_width, _height).addRun();
  for (final e in _entries) {
    run.add(_scene, e[0], e[1], e[2], e[3], e[4], e[5], opacity: e[6]);
  }
  run.add(_scene, 1, 0, 0, 1, 0, 0, opacity: 0);
  return run..place();
}

Float64List _matrix(List<double> e) => Float64List.fromList([
  e[0], e[1], 0, 0, //
  e[2], e[3], 0, 0,
  0, 0, 1, 0,
  e[4], e[5], 0, 1,
]);

/// Draws [_entries] by hand, each fill and stroke in a layer of its own with
/// its entry's opacity.
void _reference(ui.Canvas canvas) {
  canvas.clipRect(
    ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
  );
  for (final e in _entries) {
    final layer = ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, e[6]);
    canvas
      ..save()
      ..transform(_matrix(e))
      ..translate(_svg.origin.dx, _svg.origin.dy);
    for (final path in _svg.paths) {
      for (final paint in [path.paint.fill, path.paint.stroke]) {
        if (paint == null) {
          continue;
        }
        canvas
          ..saveLayer(null, layer)
          ..drawPath(path.path, paint)
          ..restore();
      }
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

void main() {
  tearDown(() => RasterizerGpu.canvasPictures = true);

  for (final pictures in [true, false]) {
    test('entries draw their paths with their opacities, '
        '${pictures ? 'with' : 'without'} pictures', () async {
      RasterizerGpu.canvasPictures = pictures;
      final run = _run();
      final actual = await _pixels(run.draw);
      final expected = await _pixels(_reference);
      final diff = _maxDiff(actual, expected);
      // ignore: avoid_print
      print('  max diff $diff/255');
      expect(diff, lessThanOrEqualTo(2));
      expect(actual.any((v) => v != 0), isTrue);
    });
  }

  test('a scene\'s paths that overlap show through each other, unlike in a '
      'layer', () async {
    final faded = await _pixels(_run().draw);
    final layered = await _pixels((canvas) {
      for (final e in _entries) {
        canvas
          ..saveLayer(
            null,
            ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, e[6]),
          )
          ..transform(_matrix(e));
        _scene.draw(canvas);
        canvas.restore();
      }
    });
    expect(_maxDiff(faded, layered), greaterThan(16));
  });

  test('an entry whose opacity is 0 isn\'t added', () {
    final run = _renderer.beginFrame(_width, _height).addRun()
      ..add(_scene, 1, 0, 0, 1, 0, 0, opacity: 0);
    expect(run.isEmpty, isTrue);
  });
}

/// [_scene]'s SVG paths.
SvgPaths get _svg => _scene.paths as SvgPaths;
