// Checks the layer that the canvas renderer draws a painted run in. From this
// package's folder, with and without Impeller:
//   flutter test test/canvas_layer_test.dart [--enable-impeller]
//
// A layer costs its area, so the run's entries bound it. Paints with an image
// or a mask filter get an unbounded layer, as those filters can draw outside
// the content. The bounds only drop empty area, so the output matches an
// unbounded layer's. The layer is in the canvas's units, as the GPU
// renderer's image is drawn, so a blur's sigma is the same with both
// renderers. That holds on Skia, and on Impeller, which applies a layer's
// filters with the transform at its restore.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/canvas_renderer.dart';

const _width = 200, _height = 160;

final _scene = CanvasScene(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
      'viewBox="0 0 100 100"><rect x="20" y="20" width="40" height="30" '
      'fill="red"/><path d="M30,80 L50,60 L70,80" fill="none" stroke="blue" '
      'stroke-width="10"/></svg>',
    ),
  ),
);

// The entries' transforms: the first is scaled by 1.5 and moved, the second
// turned a quarter turn.
const _entries = [
  [1.5, 0.0, 0.0, 1.5, 10.0, 5.0],
  [0.0, 1.0, -1.0, 0.0, 190.0, 40.0],
];

final _renderer = CanvasRenderer(1);

/// A new frame's run of [_entries].
CanvasRun _run() {
  final run = _renderer.beginFrame(_width, _height).addRun();
  for (final e in _entries) {
    run.add(_scene, e[0], e[1], e[2], e[3], e[4], e[5]);
  }
  return run..place();
}

/// Draws [_entries] by hand, in an unbounded layer with [paint].
///
/// The layer is in the canvas's units, which are 2 device pixels, as the
/// scale is undone inside it, before its restore.
void _reference(ui.Canvas canvas, ui.Paint paint) {
  canvas
    ..saveLayer(null, paint)
    ..save()
    ..scale(1 / 2)
    ..clipRect(ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()));
  for (final e in _entries) {
    canvas
      ..save()
      ..transform(
        Float64List.fromList([
          e[0], e[1], 0, 0, //
          e[2], e[3], 0, 0,
          0, 0, 1, 0,
          e[4], e[5], 0, 1,
        ]),
      );
    _scene.draw(canvas);
    canvas.restore();
  }
  canvas
    ..restore()
    ..restore();
}

Future<Uint8List> _pixels(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A canvas that records the bounds of each saveLayer call, and passes the
/// calls a run makes on to [_inner].
class _LayerSpy(final ui.Canvas _inner) implements ui.Canvas {
  final List<ui.Rect?> layers = [];

  @override
  void save() => _inner.save();
  @override
  void restore() => _inner.restore();
  @override
  void scale(double sx, [double? sy]) => _inner.scale(sx, sy);
  @override
  void transform(Float64List matrix4) => _inner.transform(matrix4);
  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    layers.add(bounds);
    _inner.saveLayer(bounds, paint);
  }

  @override
  void drawPicture(ui.Picture picture) => _inner.drawPicture(picture);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final faded = ui.Paint()..color = const ui.Color(0x80ffffff);
  final tinted = ui.Paint()
    ..colorFilter = const ui.ColorFilter.mode(
      ui.Color(0xff00ff00),
      ui.BlendMode.srcATop,
    );
  final blurred = ui.Paint()
    ..imageFilter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6);
  final masked = ui.Paint()
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);

  for (final (name, paint) in [
    ('faded', faded),
    ('tinted', tinted),
    ('blurred', blurred),
    ('mask-filtered', masked),
  ]) {
    test('a $name run draws as in an unbounded layer', () async {
      final actual = await _pixels(
        (canvas) => _run().draw(canvas, scale: 2, paint: paint),
      );
      final expected = await _pixels((canvas) => _reference(canvas, paint));
      expect(actual, expected);
      expect(actual.any((v) => v != 0), isTrue);
    });
  }

  test('a painted run\'s layer is bounded by its entries\' paint', () {
    final spy = _LayerSpy(ui.Canvas(ui.PictureRecorder()));
    _run().draw(spy, paint: faded);
    // The scene paints from 10, 20 to 90, 100: its rect, and its stroke's path
    // grown by twice the stroke's width, 10, which allows for miter joins.
    // The first entry scales and moves that to 25, 35 to 145, 155. The second
    // turns it to 90, 50 to 170, 130. The layer adds a pixel for antialiasing.
    expect(spy.layers, hasLength(1));
    final bounds = spy.layers.single!;
    expect(bounds.left, closeTo(24, 1e-9));
    expect(bounds.top, closeTo(34, 1e-9));
    expect(bounds.right, closeTo(171, 1e-9));
    expect(bounds.bottom, closeTo(156, 1e-9));
  });

  test('the layer\'s bounds are in the canvas\'s units', () {
    final spy = _LayerSpy(ui.Canvas(ui.PictureRecorder()));
    _run().draw(spy, scale: 2, paint: faded);
    final bounds = spy.layers.single!;
    expect(bounds.left, closeTo(12, 1e-9));
    expect(bounds.top, closeTo(17, 1e-9));
    expect(bounds.right, closeTo(85.5, 1e-9));
    expect(bounds.bottom, closeTo(78, 1e-9));
  });

  test('image and mask filters\' layers aren\'t bounded', () {
    for (final paint in [blurred, masked]) {
      final spy = _LayerSpy(ui.Canvas(ui.PictureRecorder()));
      _run().draw(spy, paint: paint);
      expect(spy.layers, [null]);
    }
  });

  test('an unpainted run makes no layer', () {
    final spy = _LayerSpy(ui.Canvas(ui.PictureRecorder()));
    _run().draw(spy);
    expect(spy.layers, isEmpty);
  });
}
