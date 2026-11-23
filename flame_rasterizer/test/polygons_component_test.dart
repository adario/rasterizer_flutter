// Checks RasterizerPolygonsComponent, in flutter_tester, with rasterizer_gpu's
// canvas renderer. From this package's folder:
//   flutter test test/polygons_component_test.dart
//
// The component draws its polygons with its paint as a layer, into the
// game's runs, as a RasterizerPathComponent without paint layers does. Its
// size is the polygons' bounds. Components of the same polygons share an
// import, and its removal, or its game's, frees it. Outside a game with
// HasRasterizer, it draws the polygons' path with drawPath.

import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

const _red = Color(0xffff0000);
const _blue = Color(0xff0000ff);

// Two 10 × 10 squares side by side, from 5, 0 to 25, 10.
final _squares = RasterizerPolygons(
  Float32List.fromList([
    5,
    0,
    15,
    0,
    15,
    10,
    5,
    10,
    15,
    0,
    25,
    0,
    25,
    10,
    15,
    10,
  ]),
  Int32List.fromList([4, 4]),
);

class _Game() extends FlameGame with HasRasterizer;

/// Returns a game [_size] wide whose world has [components], as
/// path_component_test.dart does.
Future<FlameGame> _game(List<Component> components, {bool ready = true}) async {
  final game = (ready ? _Game() : FlameGame())
    ..onGameResize(Vector2.all(_size.toDouble()));
  await game.onLoad();
  // ignore: invalid_use_of_internal_member
  game.mount();
  game.world.addAll(components);
  await game.ready();
  if (game is HasRasterizer) {
    await game.rasterizerReady;
  }
  return game;
}

/// Returns [game]'s frame, as RGBA.
Future<Uint8List> _render(FlameGame game) async {
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Returns the pixel at [x], [y] of [pixels], as RGBA.
List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = 4 * (y * _size + x);
  return pixels.sublist(i, i + 4);
}

/// Returns the squares, centred at the world's origin, filled with [color].
RasterizerPolygonsComponent _polygons({
  Color color = _red,
  bool separate = false,
}) => RasterizerPolygonsComponent(
  polygons: _squares,
  anchor: Anchor.center,
  paint: Paint()..color = color,
  separate: separate,
);

void main() {
  test("it draws its polygons into the game's runs, its size their "
      'bounds', () async {
    final polygons = _polygons();
    expect(polygons.size, Vector2(20, 10));
    final game = await _game([polygons]);
    final pixels = await _render(game);
    // The squares span 10 to 30 across and 15 to 25 down.
    expect(_pixel(pixels, 12, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 28, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 8, 20), [0, 0, 0, 0]);
    expect(_pixel(pixels, 20, 12), [0, 0, 0, 0]);
    expect((game as HasRasterizer).rasterizerFrame!.runs, hasLength(1));
    expect(polygons.debugScene!.backend, RasterizerBackend.canvas);
    expect(polygons.debugScene!.pathCount, 1);
    game.onRemove();
  });

  test('components of the same polygons share an import, unless they differ '
      'in separate', () async {
    final first = _polygons();
    final second = _polygons();
    final separate = _polygons(separate: true);
    final game = await _game([first, second, separate]);
    await _render(game);
    expect(second.debugScene, same(first.debugScene));
    expect(separate.debugScene, isNot(same(first.debugScene)));
    game.onRemove();
  });

  test('its opacity applies over its import, and a new color imports it '
      'again', () async {
    final polygons = _polygons();
    final game = await _game([polygons]);
    await _render(game);
    final scene = polygons.debugScene;
    polygons.opacity = 0.5;
    var pixels = await _render(game);
    // Premultiplied.
    expect(_pixel(pixels, 12, 20), [128, 0, 0, 128]);
    expect(polygons.debugScene, same(scene));
    polygons.paint.color = _blue;
    pixels = await _render(game);
    expect(_pixel(pixels, 12, 20), [0, 0, 255, 255]);
    expect(polygons.debugScene, isNot(same(scene)));
    game.onRemove();
  });

  test("its removal, or its game's, frees its import", () async {
    final removed = _polygons();
    final kept = _polygons(color: _blue);
    final game = await _game([removed, kept]);
    await _render(game);
    expect(removed.debugScene, isNotNull);
    removed.removeFromParent();
    game.update(0);
    expect(removed.debugScene, isNull);
    expect(kept.debugScene, isNotNull);
    game.onRemove();
    expect(kept.debugScene, isNull);
  });

  test('outside a game with HasRasterizer, it draws with drawPath', () async {
    final polygons = _polygons();
    final game = await _game([polygons], ready: false);
    final pixels = await _render(game);
    expect(_pixel(pixels, 12, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 8, 20), [0, 0, 0, 0]);
    expect(polygons.debugScene, isNull);
  });

  test('throws for a maxSize that is not positive', () {
    for (final maxSize in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => RasterizerPolygonsComponent(polygons: _squares, maxSize: maxSize),
        throwsArgumentError,
      );
    }
  });
}
