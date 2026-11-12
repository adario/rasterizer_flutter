// Checks RasterizerCanvas with the canvas renderer, in flutter_tester. From
// this package's folder:
//   flutter test test/rasterizer_canvas_test.dart
//
// It checks which draws share a run, how paints draw, and runs that end
// under a transform that can't be inverted, or under perspective.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

const _size = 40;

RasterizerScene _fromString(String svg) => RasterizerScene.fromSvg(
  Uint8List.fromList(utf8.encode(svg)),
  backend: RasterizerBackend.canvas,
);

// A red square filling its 10 × 10 viewBox.
final _svg = _fromString(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
  '<rect width="10" height="10" fill="#ff0000"/></svg>',
);

// A red square, and a red rectangle over its left half. So the left half is
// covered twice, and the right half once.
final _overlapping = _fromString(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
  '<rect width="10" height="10" fill="#ff0000"/>'
  '<rect width="5" height="10" fill="#ff0000"/></svg>',
);

// The same, each at half alpha. So the left half is at 0.75 alpha, and the
// right half at 0.5.
final _translucent = _fromString(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
  '<rect width="10" height="10" fill="#ff0000" fill-opacity="0.5"/>'
  '<rect width="5" height="10" fill="#ff0000" fill-opacity="0.5"/></svg>',
);

late RasterizerRenderer _renderer;

extension on RasterizerScene {
  /// Draws it into [canvas] with its rect fitted to [size] by [size], from
  /// the canvas's origin, with [overridePaint].
  void render(RasterizerCanvas canvas, double size, {ui.Paint? overridePaint}) {
    final r = rect, s = size / r.width;
    canvas.drawScene(
      this,
      s,
      0,
      0,
      s,
      -r.left * s,
      -r.top * s,
      paint: overridePaint,
    );
  }
}

/// Draws [draw] with a [RasterizerCanvas], in a new frame.
///
/// Warps perspective if [warp], else does as the frame's renderer does.
/// Returns how many runs the canvas made, and the frame's pixels, as RGBA.
Future<(int, Uint8List)> _frame(
  void Function(RasterizerCanvas) draw, {
  bool warp = false,
}) async {
  final recorder = ui.PictureRecorder();
  final frame = _renderer.beginFrame(_size, _size);
  final canvas = RasterizerCanvas()
    ..warpPerspective = warp ? true : null
    ..begin(ui.Canvas(recorder), frame, 1);
  draw(canvas);
  canvas.end();
  frame.render();
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return (canvas.runCount, data!.buffer.asUint8List());
}

/// How many runs it takes to draw a square with each of [paints], side by
/// side.
Future<int> _runs(List<ui.Paint?> paints) async {
  final (runs, _) = await _frame((canvas) {
    for (final (i, paint) in paints.indexed) {
      _svg.render(canvas..translate(i.toDouble(), 0), 4, overridePaint: paint);
    }
  });
  return runs;
}

/// The pixel at [x], [y] of [pixels], as RGBA.
List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = 4 * (y * _size + x);
  return pixels.sublist(i, i + 4);
}

ui.Paint _faded(
  double opacity, [
  ui.Color color = const ui.Color(0xffffffff),
]) => ui.Paint()..color = color.withValues(alpha: opacity);

const _red = [255, 0, 0, 255], _clear = [0, 0, 0, 0];

// w = 1 + x / 50: a perspective along x, as a turn about y would make.
final _perspective = Float64List(16)
  ..[0] = 1
  ..[3] = 0.02
  ..[5] = 1
  ..[10] = 1
  ..[15] = 1;
final _blue = ui.Paint()..color = const ui.Color(0xff0000ff);

/// Draws a square from 0, 0 to 10, 10. Then draws [inner] in a save, moved
/// to 20, 20 and scaled by [scale].
void _squareThenScaled(
  RasterizerCanvas canvas,
  double scale,
  void Function(RasterizerCanvas) inner,
) {
  _svg.render(canvas, 10);
  canvas
    ..save()
    ..translate(20, 20)
    ..scale(scale);
  inner(canvas);
  canvas.restore();
}

void main() {
  setUpAll(() async {
    _renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.canvas,
    );
  });

  group('runs', () {
    test('a default paint is no paint', () async {
      expect(
        await _runs([
          null,
          ui.Paint(),
          ui.Paint()..color = const ui.Color(0xffffffff),
          ui.Paint()..color = const ui.Color(0xff123456),
        ]),
        1,
      );
    });

    test('paints that only differ by alpha share a run', () async {
      expect(
        await _runs([
          null,
          _faded(0.5),
          _faded(0.5, const ui.Color(0xff00ff00)),
          _faded(0.4),
          null,
        ]),
        1,
      );
      ui.Paint tint(double opacity) => _faded(opacity)
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xff00ff00),
          ui.BlendMode.multiply,
        );
      expect(await _runs([tint(1), tint(0.5), tint(0.2)]), 1);
    });

    test(
      'a paint whose alpha is 0 draws nothing and doesn\'t end the run',
      () async {
        expect(await _runs([_faded(0)]), 0);
        expect(await _runs([null, _faded(0), null]), 1);
        expect(
          await _runs([
            null,
            _faded(0)..imageFilter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            null,
          ]),
          1,
        );
      },
    );

    test('paints that draw alike share a run', () async {
      ui.Paint tint() => ui.Paint()
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xff00ff00),
          ui.BlendMode.srcATop,
        );
      expect(await _runs([tint(), tint()]), 1);
      ui.Paint hue() => ui.Paint()
        ..colorFilter = ui.ColorFilter.matrix([
          for (var i = 0; i < 20; i++) i % 6 == 0 ? 0.5 : 0.1,
        ]);
      expect(await _runs([hue(), hue()]), 1);
      ui.Paint blur() =>
          ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2);
      expect(await _runs([blur(), blur()]), 1);
      ui.Paint mask() =>
          ui.Paint()
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2);
      expect(await _runs([mask(), mask()]), 1);
    });

    test('tints, whatever their colors and order, share a run with plain '
        'paints', () async {
      ui.Paint tint(int color, [double opacity = 1]) => _faded(opacity)
        ..colorFilter = RasterizerColorTransform.mode(
          ui.Color(color),
          ui.BlendMode.srcATop,
        )!.filter;
      expect(
        await _runs([
          null,
          tint(0xff00ff00),
          tint(0x800000ff, 0.5),
          null,
          ui.Paint()
            ..colorFilter = RasterizerColorTransform.matrix(const [
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0, 0, 0, 1, 0,
            ])!.filter,
          _faded(0.5),
          tint(0xff00ff00),
        ]),
        1,
      );
    });

    test(
      'a tint made otherwise, which can\'t be read back, ends the run',
      () async {
        expect(
          await _runs([
            null,
            ui.Paint()
              ..colorFilter = const ui.ColorFilter.mode(
                ui.Color(0xff00ff00),
                ui.BlendMode.srcATop,
              ),
            null,
          ]),
          3,
        );
      },
    );

    test('color filters that change alpha still end the run', () async {
      ui.Paint mode(ui.BlendMode mode) => ui.Paint()
        ..colorFilter = ui.ColorFilter.mode(const ui.Color(0x800000ff), mode);
      expect(
        await _runs([
          null,
          mode(ui.BlendMode.modulate),
          null,
          mode(ui.BlendMode.dstIn),
          null,
        ]),
        5,
      );
    });

    test('another paint ends the run', () async {
      expect(
        await _runs([
          null,
          ui.Paint()..blendMode = ui.BlendMode.multiply,
          ui.Paint()..invertColors = true,
          ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          ui.Paint()
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
        ]),
        6,
      );
    });
  });

  group('drawing', () {
    test('a faded run is drawn faded', () async {
      final (_, pixels) = await _frame(
        (canvas) =>
            _svg.render(canvas, _size.toDouble(), overridePaint: _faded(0.5)),
      );
      expect(_pixel(pixels, 20, 20)[3], closeTo(128, 1));
    });

    test(
      'a faded scene\'s paths that overlap show through each other',
      () async {
        final (_, pixels) = await _frame(
          (canvas) => _overlapping.render(
            canvas,
            _size.toDouble(),
            overridePaint: _faded(0.5),
          ),
        );
        // 0.5 alpha over 0.5, where a faded sprite would be 0.5 throughout.
        expect(_pixel(pixels, 10, 20)[3], closeTo(191, 1));
        expect(_pixel(pixels, 30, 20)[3], closeTo(128, 1));
      },
    );

    test('a paint whose alpha changes between draws keeps the run, and each '
        'entry its alpha', () async {
      final paint = _faded(0.5);
      final (runs, pixels) = await _frame((canvas) {
        _svg.render(canvas, 20, overridePaint: paint);
        paint.color = const ui.Color(0xffffffff);
        _svg.render(canvas..translate(20, 0), 20, overridePaint: paint);
      });
      expect(runs, 1);
      expect(_pixel(pixels, 10, 10)[3], closeTo(128, 1));
      expect(_pixel(pixels, 30, 10)[3], 255);
    });

    test('a paint changed between draws ends the run, and the first keeps '
        'its paint', () async {
      final paint = ui.Paint()
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xff0000ff),
          ui.BlendMode.srcIn,
        );
      final (runs, pixels) = await _frame((canvas) {
        _svg.render(canvas, 20, overridePaint: paint);
        paint.colorFilter = null;
        _svg.render(canvas..translate(20, 0), 20, overridePaint: paint);
      });
      expect(runs, 2);
      expect(_pixel(pixels, 10, 10), [0, 0, 255, 255]);
      expect(_pixel(pixels, 30, 10), [255, 0, 0, 255]);
    });

    test('a faded and tinted run is drawn faded and tinted', () async {
      final (_, pixels) = await _frame(
        (canvas) => _svg.render(
          canvas,
          _size.toDouble(),
          overridePaint: _faded(0.5)
            ..colorFilter = const ui.ColorFilter.mode(
              ui.Color(0xff0000ff),
              ui.BlendMode.srcATop,
            ),
        ),
      );
      // Blue at half alpha, premultiplied.
      expect(_pixel(pixels, 20, 20), [0, 0, closeTo(128, 1), closeTo(128, 1)]);
    });

    test(
      'tinted translucent paths that overlap are drawn as in a layer',
      () async {
        final (runs, pixels) = await _frame(
          (canvas) => _translucent.render(
            canvas,
            _size.toDouble(),
            overridePaint: ui.Paint()
              ..colorFilter = RasterizerColorTransform.mode(
                const ui.Color(0xff0000ff),
                ui.BlendMode.srcATop,
              )!.filter,
          ),
        );
        expect(runs, 1);
        // Blue, premultiplied, at the paths' composited alphas.
        expect(_pixel(pixels, 10, 20), [
          0,
          0,
          closeTo(191, 1),
          closeTo(191, 1),
        ]);
        expect(_pixel(pixels, 30, 20), [
          0,
          0,
          closeTo(128, 1),
          closeTo(128, 1),
        ]);
      },
    );

    test('a tinted run is drawn tinted', () async {
      final (_, pixels) = await _frame(
        (canvas) => _svg.render(
          canvas,
          _size.toDouble(),
          overridePaint: ui.Paint()
            ..colorFilter = const ui.ColorFilter.mode(
              ui.Color(0xff0000ff),
              ui.BlendMode.srcATop,
            ),
        ),
      );
      expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    });
  });

  group('drawWithPaint', () {
    /// Calls [RasterizerCanvas.drawWithPaint] with [paint].
    ///
    /// Returns what it passes to its callback, and the canvas's save count
    /// there, or null if it doesn't call it.
    (double, RasterizerColorTransform?, int)? passed(ui.Paint? paint) {
      final canvas = ui.Canvas(ui.PictureRecorder());
      (double, RasterizerColorTransform?, int)? result;
      RasterizerCanvas.drawWithPaint(canvas, paint, (opacity, transform) {
        result = (opacity, transform, canvas.getSaveCount());
      });
      expect(canvas.getSaveCount(), 1);
      return result;
    }

    test('a default paint fades, with no layer', () {
      expect(passed(null), (1.0, null, 1));
      expect(passed(_faded(0.5)), (0.5, null, 1));
    });

    test('a paint whose alpha is 0 draws nothing', () {
      expect(passed(_faded(0)), isNull);
    });

    test('a color transform\'s filter is passed, with no layer', () {
      final tint = RasterizerColorTransform.mode(
        const ui.Color(0xff00ff00),
        ui.BlendMode.srcATop,
      )!;
      expect(passed(_faded(0.5)..colorFilter = tint.filter), (0.5, tint, 1));
    });

    test('other fields apply in a layer', () async {
      final paint = _faded(0.5)
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xff0000ff),
          ui.BlendMode.srcIn,
        );
      expect(passed(paint), (0.5, null, 2));
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      RasterizerCanvas.drawWithPaint(canvas, paint, (opacity, _) {
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 10, 10),
          ui.Paint()..color = ui.Color.fromRGBO(255, 0, 0, opacity),
        );
      });
      final image = await recorder.endRecording().toImage(_size, _size);
      final pixels = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      // Blue at the content's half alpha, premultiplied.
      expect(_pixel(pixels, 5, 5), [0, 0, closeTo(128, 1), closeTo(128, 1)]);
    });
  });

  group('transforms', () {
    test('a run that ends at scale 0 is still drawn', () async {
      for (final scale in [0.0, 1e-9]) {
        final (runs, pixels) = await _frame(
          (canvas) => _squareThenScaled(canvas, scale, (canvas) {
            _svg.render(canvas, 10);
            canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), _blue);
          }),
        );
        expect(runs, 1, reason: 'scale $scale');
        expect(_pixel(pixels, 5, 5), _red, reason: 'scale $scale');
        expect(_pixel(pixels, 25, 25), _clear, reason: 'scale $scale');
      }
    });

    test('runs ending at scale 0 keep their order and paints', () async {
      final faded = ui.Paint()..color = const ui.Color(0x80ffffff);
      // srcIn, which no color transform folds, so the run draws it in a
      // layer.
      final tinted = ui.Paint()
        ..colorFilter = const ui.ColorFilter.mode(
          ui.Color(0xff00ff00),
          ui.BlendMode.srcIn,
        );
      final (runs, pixels) = await _frame((canvas) {
        _svg.render(canvas, 10, overridePaint: tinted);
        canvas
          ..save()
          ..scale(0);
        // This ends the tinted run, then makes a faded one and ends it too,
        // both while the transform is singular.
        _svg.render(canvas, 10, overridePaint: faded);
        canvas
          ..drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), _blue)
          ..restore();
        // A plain square over the tinted square's right half, drawn after it.
        _svg.render(canvas..translate(5, 0), 10);
      });
      expect(runs, 3);
      expect(_pixel(pixels, 2, 5), [0, 255, 0, 255]);
      expect(_pixel(pixels, 8, 5), _red);
    });

    test('a clip made at scale 0 doesn\'t clip the run before it', () async {
      final (_, pixels) = await _frame(
        (canvas) => _squareThenScaled(canvas, 0, (canvas) {
          canvas.clipRect(const ui.Rect.fromLTWH(0, 0, 1, 1));
          _svg.render(canvas, 10);
        }),
      );
      expect(_pixel(pixels, 5, 5), _red);
    });

    test('a run that ends under perspective is drawn where it was', () async {
      final (runs, pixels) = await _frame((canvas) {
        _svg.render(canvas, 10);
        canvas
          ..save()
          ..transform(_perspective)
          ..drawRect(const ui.Rect.fromLTWH(20, 20, 4, 4), _blue)
          ..restore();
      });
      expect(runs, 1);
      expect(_pixel(pixels, 1, 1), _red);
      expect(_pixel(pixels, 9, 9), _red);
      expect(_pixel(pixels, 11, 5), _clear);
    });

    for (final warp in [false, true]) {
      test('an SVG under perspective is drawn where the perspective puts it, '
          '${warp ? 'warped, as a run of its own' : 'in its run'}', () async {
        final (runs, pixels) = await _frame((canvas) {
          _svg.render(canvas, 10);
          canvas
            ..save()
            ..transform(_perspective)
            ..translate(15, 15);
          _svg.render(canvas, 20);
          canvas.restore();
          _svg.render(canvas..translate(0, 30), 10);
        }, warp: warp);
        expect(runs, warp ? 3 : 1);
        await _expectPerspective(pixels);
      });

      test("an SVG under perspective behind the eye isn't drawn"
          "${warp ? ', warped' : ''}", () async {
        final (_, pixels) = await _frame((canvas) {
          canvas
            ..transform(_perspective)
            ..translate(-60, 0);
          _svg.render(canvas, 10);
        }, warp: warp);
        expect(pixels.every((v) => v == 0), isTrue);
      });
    }

    test('under a canvas scaled to 0 at begin, scenes aren\'t added', () {
      final frame = _renderer.beginFrame(_size, _size);
      final canvas = RasterizerCanvas()
        ..begin(ui.Canvas(ui.PictureRecorder())..scale(0), frame, 1);
      _svg.render(canvas, 10);
      canvas.end();
      frame.render();
      expect(frame.entryCount, 0);
    });

    test('runs still pending at the end are dropped', () async {
      final (_, pixels) = await _frame((canvas) {
        canvas.scale(0);
        _svg.render(canvas, 10);
        canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), _blue);
      });
      expect(_pixel(pixels, 5, 5), _clear);
    });
  });
}

/// Checks [pixels] against the squares of the perspective tests, drawn
/// straight into a canvas.
Future<void> _expectPerspective(Uint8List pixels) async {
  final recorder = ui.PictureRecorder();
  final red = ui.Paint()..color = const ui.Color(0xffff0000);
  ui.Canvas(recorder)
    ..drawRect(const ui.Rect.fromLTWH(0, 0, 10, 10), red)
    ..save()
    ..transform(_perspective)
    ..drawRect(const ui.Rect.fromLTWH(15, 15, 20, 20), red)
    ..restore()
    ..drawRect(const ui.Rect.fromLTWH(0, 30, 10, 10), red);
  final image = await recorder.endRecording().toImage(_size, _size);
  final expected = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  var differing = 0;
  for (var i = 0; i < pixels.length; i++) {
    if ((pixels[i] - expected[i]).abs() > 8) {
      differing++;
    }
  }
  expect(differing, 0);
  // The perspective shrinks the square to span from 15 / 1.3 to 35 / 1.7.
  expect(_pixel(pixels, 13, 13), _red);
  expect(_pixel(pixels, 19, 19), _red);
  expect(_pixel(pixels, 22, 22), _clear);
}
