// Checks HasRasterizer on a game with a world of its own type, as a
// Forge2DGame has, in flutter_tester. From this package's folder:
//   flutter test test/world_test.dart
//
// The game must draw the SVGs in that world, through its camera, with
// rasterizer_gpu's canvas renderer.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

// A red square filling its 10 × 10 SVG.
final _square = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"> '
    '<rect width="10" height="10" fill="#ff0000"/></svg>',
  ),
);

class _World() extends World {
  bool updated = false;

  @override
  void update(double dt) => updated = true;
}

class _Game() extends FlameGame<_World> with HasRasterizer {
  this : super(world: _World());
}

void main() {
  test('a game with its own type of world draws its SVGs', () async {
    final svg = RasterizerSvg.fromBytes(_square);
    final game = _Game()..onGameResize(Vector2.all(_size.toDouble()));
    // Its world keeps its type.
    final world = game.world;
    // Loaded and mounted, without a GameWidget.
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    // The camera looks at the world's origin, in the game's centre.
    world.add(
      RasterizerSvgComponent(
        svg: svg,
        size: Vector2.all(10),
        anchor: Anchor.center,
      ),
    );
    await game.ready();
    game.update(0);
    expect(world.updated, isTrue);
    await game.rasterizerReady;
    final recorder = PictureRecorder();
    game.render(Canvas(recorder));
    final image = await recorder.endRecording().toImage(_size, _size);
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    List<int> pixel(int x, int y) {
      final i = 4 * (y * _size + x);
      return pixels.sublist(i, i + 4);
    }

    expect(pixel(20, 20), [255, 0, 0, 255]);
    expect(pixel(5, 5), [0, 0, 0, 0]);
    game.onRemove();
    svg.dispose();
  });
}
