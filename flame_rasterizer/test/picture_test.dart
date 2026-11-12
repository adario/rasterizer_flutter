// Checks RasterizerSvg drawn into a canvas that isn't a game's
// RasterizerCanvas, in flutter_tester. From this package's folder:
//   flutter test test/picture_test.dart
//
// Such a canvas is a picture of its own, such as a snapshot's or a camera
// post process's. There the SVG draws its paths with dart:ui. Its paint's
// alpha fades each path, and the paint's other fields apply in a layer. An
// SVG imported for a GPU renderer is imported for the canvas renderer the
// first time. Into the game's own canvas, before its renderer is ready, the
// SVG still draws nothing.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

Uint8List _bytes(String svg) => Uint8List.fromList(utf8.encode(svg));

// A red square filling its 10 × 10 viewBox, which starts at 5, 5.
final _square = _bytes(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" '
  'viewBox="5 5 10 10"><rect x="5" y="5" width="10" height="10" '
  'fill="#ff0000"/></svg>',
);

// Two red squares, the second over the left half of the first.
final _overlapping = _bytes(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"> '
  '<rect width="10" height="10" fill="#ff0000"/> '
  '<rect width="5" height="10" fill="#ff0000"/></svg>',
);

/// What [draw] draws into a picture, as RGBA.
Future<Uint8List> _picture(void Function(Canvas) draw) async {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = 4 * (y * _size + x);
  return pixels.sublist(i, i + 4);
}

const _red = [255, 0, 0, 255];
const _clear = [0, 0, 0, 0];

class _Game() extends FlameGame with HasRasterizer;

class _Snapshot({super.children}) extends PositionComponent with Snapshot;

void main() {
  for (final backend in RasterizerBackend.values) {
    test('a ${backend.name} SVG draws its paths into a picture', () async {
      final svg = RasterizerSvg.debugFromBytes(_square, backend);
      expect(svg.scene.backend, backend);
      final pixels = await _picture((canvas) {
        canvas
          ..translate(10, 10)
          ..scale(2);
        svg.render(canvas, Vector2.all(10));
      });
      expect(_pixel(pixels, 11, 11), _red);
      expect(_pixel(pixels, 29, 29), _red);
      expect(_pixel(pixels, 9, 9), _clear);
      expect(_pixel(pixels, 31, 31), _clear);
      svg.dispose();
    });
  }

  test("its paint's alpha fades each path, and its other fields apply as a "
      'layer', () async {
    final svg = RasterizerSvg.fromBytes(_overlapping);
    final faded = Paint()..color = const Color(0x80ffffff);
    final tinted = Paint()
      ..colorFilter = const ColorFilter.mode(
        Color(0xff00ff00),
        BlendMode.srcATop,
      );
    final pixels = await _picture((canvas) {
      svg.render(canvas, Vector2.all(10), overridePaint: faded);
      svg.render(
        canvas..translate(20, 0),
        Vector2.all(10),
        overridePaint: tinted,
      );
      svg.render(
        canvas..translate(0, 20),
        Vector2.all(10),
        overridePaint: Paint()..color = const Color(0x00ffffff),
      );
    });
    // One path at half alpha, then two paths at half alpha each, one over
    // the other.
    expect(_pixel(pixels, 8, 5)[3], closeTo(128, 2));
    expect(_pixel(pixels, 2, 5)[3], closeTo(191, 2));
    expect(_pixel(pixels, 25, 5), [0, 255, 0, 255]);
    expect(_pixel(pixels, 25, 25), _clear);
    svg.dispose();
  });

  test('a game draws nothing into its own canvas before its renderer is '
      'ready, but does into a snapshot', () async {
    final svg = RasterizerSvg.fromBytes(_square);
    final game = _Game()..onGameResize(Vector2.all(_size.toDouble()));
    game.add(RasterizerSvgComponent(svg: svg, size: Vector2.all(10)));
    game.add(
      _Snapshot(
        children: [
          RasterizerSvgComponent(
            svg: svg,
            position: Vector2(20, 20),
            size: Vector2.all(10),
          ),
        ],
      ),
    );
    // Loaded and mounted, without a GameWidget.
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    game.update(0);
    expect(game.rasterizer, isNull);
    final pixels = await _picture(game.render);
    expect(_pixel(pixels, 5, 5), _clear);
    expect(_pixel(pixels, 25, 25), _red);
    await game.rasterizerReady;
    game.onRemove();
    svg.dispose();
  });
}
