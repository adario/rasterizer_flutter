// Checks that the canvas renderer skips the entries that paint nothing in the
// viewport. From this package's folder:
//   flutter test test/canvas_viewport_test.dart
//
// An entry is skipped when what it can paint, strokes included, lies more
// than a device pixel outside the viewport, so the output matches drawing
// every entry, clipped to the viewport.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/canvas_renderer.dart';

const _width = 100, _height = 80;

// A 20 × 20 square, and a stroke that reaches 4 past its right edge: its path
// is at x = 22, and half of its width is 2.
final _scene = CanvasScene(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" '
      'viewBox="0 0 20 20"><rect width="20" height="20" fill="red"/>'
      '<path d="M22,0 L22,20" stroke="blue" stroke-width="4"/></svg>',
    ),
  ),
);

final _renderer = CanvasRenderer(1);

/// A canvas that counts the entries drawn, one transform each, and draws
/// nothing.
class _EntrySpy() implements ui.Canvas {
  var entries = 0;

  @override
  void transform(Float64List matrix4) => entries++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Returns a new frame's run of affine entries, each a translation by [moves].
CanvasRun _run(List<({double x, double y})> moves) {
  final run = _renderer.beginFrame(_width, _height).addRun();
  for (final (:x, :y) in moves) {
    run.add(_scene, 1, 0, 0, 1, x, y);
  }
  return run..place();
}

Future<Uint8List> _pixels(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  // The scene paints the square, and its stroke's path grown by twice the
  // stroke's width, 8, which allows for miter joins: from 0, -8 to 30, 28.
  test('entries off the viewport are skipped', () {
    final spy = _EntrySpy();
    _run([
      (x: 10, y: 10), // Inside.
      (x: -31, y: 10), // Right edge at -1: skipped.
      (x: -30.5, y: 10), // Right edge at -0.5, within a pixel: drawn.
      (x: _width + 1.0, y: 10), // Left edge at width + 1: skipped.
      (x: _width + 0.5, y: 10), // Left edge at width + 0.5: drawn.
      (x: 10, y: -29), // Bottom edge at -1: skipped.
      (x: 10, y: _height + 9.0), // Top edge at height + 1: skipped.
      (x: -1000, y: -1000), // Far off.
    ]).draw(spy);
    expect(spy.entries, 3);
  });

  test('a stroke reaching into the viewport keeps its entry', () {
    final spy = _EntrySpy();
    // The square ends at -2, its stroke at 2.
    _run([(x: -22, y: 10)]).draw(spy);
    expect(spy.entries, 1);
  });

  test('a projective entry with a corner behind the eye is drawn', () {
    final spy = _EntrySpy();
    final run = _renderer.beginFrame(_width, _height).addRun()
      ..addProjective(_scene, 1, 0, 0, 1, -1000, -1000, -0.1, 0, 1)
      ..place();
    run.draw(spy);
    expect(spy.entries, 1);
  });

  test('a projective entry off the viewport is skipped', () {
    final spy = _EntrySpy();
    final run = _renderer.beginFrame(_width, _height).addRun()
      ..addProjective(_scene, 1, 0, 0, 1, -1000, 10, 0.001, 0, 1)
      ..place();
    run.draw(spy);
    expect(spy.entries, 0);
  });

  test('skipping draws as every entry clipped to the viewport', () async {
    const moves = [
      (x: -22.0, y: 10.0),
      (x: -30.5, y: 30.0),
      (x: 90.0, y: 50.0),
      (x: -31.0, y: 0.0),
    ];
    final actual = await _pixels(
      (canvas) => _run(moves).draw(canvas, scale: 1),
    );
    final expected = await _pixels((canvas) {
      canvas.clipRect(
        ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      );
      for (final (:x, :y) in moves) {
        canvas
          ..save()
          ..translate(x, y);
        _scene.draw(canvas);
        canvas.restore();
      }
    });
    expect(actual, expected);
    expect(actual.any((v) => v != 0), isTrue);
  });
}
