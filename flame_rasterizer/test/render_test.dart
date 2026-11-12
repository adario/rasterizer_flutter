// Checks HasRasterizer's renderer and frames, in flutter_tester, with
// rasterizer_gpu's canvas renderer. From this package's folder:
//   flutter test test/render_test.dart
//
// When a component throws while the game draws its tree, the run that ended
// before must still draw, and the frame must render. A renderer created after
// the game is removed must be disposed of. Settings that the renderer doesn't
// take must throw, at each frame. And the frame must be at the device pixel
// ratio of the game's view.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

// A red square filling its 10 × 10 SVG.
final _square = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"> '
    '<rect width="10" height="10" fill="#ff0000"/></svg>',
  ),
);

class _Game() extends FlameGame with HasRasterizer;

class _BadSlots() extends FlameGame with HasRasterizer {
  @override
  int get rasterizerSlots => 0;
}

class _BadSamples() extends FlameGame with HasRasterizer {
  @override
  int get rasterizerMeshSamples => 2;
}

class _Throwing() extends Component {
  @override
  void render(Canvas canvas) => throw StateError('render failed');
}

void main() {
  test('a component that throws leaves the run before it drawn', () async {
    final svg = RasterizerSvg.fromBytes(_square);
    final game = _Game()..onGameResize(Vector2.all(_size.toDouble()));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    game.world.addAll([
      RasterizerSvgComponent(
        svg: svg,
        size: Vector2.all(10),
        anchor: Anchor.center,
      ),
      _Throwing()..priority = 1,
    ]);
    await game.ready();
    await game.rasterizerReady;
    final recorder = PictureRecorder();
    expect(() => game.render(Canvas(recorder)), throwsStateError);
    final image = await recorder.endRecording().toImage(_size, _size);
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    const i = 4 * (20 * _size + 20);
    expect(pixels.sublist(i, i + 4), [255, 0, 0, 255]);
    expect(game.rasterizerFrame?.entryCount, 1);
    game.onRemove();
    svg.dispose();
  });

  test('a renderer created after the game is removed is disposed of', () async {
    final game = _Game()..onGameResize(Vector2.all(_size.toDouble()));
    final ready = game.rasterizerReady;
    game.onRemove();
    final renderer = await ready;
    expect(game.rasterizer, isNull);
    expect(() => renderer.beginFrame(_size, _size), throwsStateError);
    // Drawn again, the game creates a new renderer. Removed again, it forgets
    // its last frame.
    game.render(Canvas(PictureRecorder()));
    expect(await game.rasterizerReady, isNot(same(renderer)));
    game.render(Canvas(PictureRecorder()));
    expect(game.rasterizerFrame, isNotNull);
    game.onRemove();
    expect(game.rasterizerFrame, isNull);
  });

  test("settings the renderer can't take throw each frame", () {
    for (final game in [_BadSlots(), _BadSamples()]) {
      game.onGameResize(Vector2.all(_size.toDouble()));
      expect(() => game.rasterizerReady, throwsArgumentError);
      for (var i = 0; i < 2; i++) {
        expect(
          () => game.render(Canvas(PictureRecorder())),
          throwsArgumentError,
        );
      }
      expect(game.rasterizer, isNull);
    }
  });

  testWidgets("its frame is at its widget's device pixel ratio", (
    tester,
  ) async {
    final game = _Game();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.5),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: _size.toDouble(),
              child: GameWidget(game: game),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10 && game.rasterizerFrame == null; i++) {
      await tester.runAsync(() => game.rasterizerReady);
      await tester.pump();
    }
    expect(game.rasterizerFrame?.width, (_size * 2.5).ceil());
    await tester.pumpWidget(const SizedBox());
  });
}
