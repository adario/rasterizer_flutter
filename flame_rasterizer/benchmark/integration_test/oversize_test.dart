// Checks a game wider than its renderer takes, in the app:
//   flutter test integration_test/oversize_test.dart \
//     -d <macos|iOS udid|emulator-5554> [--dart-define=BACKEND=atlas]
//
// The GPU renderers take viewports up to RasterizerRenderer.maxViewportSize
// device pixels a side. A wider game renders its vectors at a lower pixel
// ratio, to fit, and scales them up. So a square at each end must draw where
// it belongs, rather than the frame throwing.
//
// The game draws with demoGpu: the mesh renderer, or the GPU renderer with
// BACKEND=atlas. On OpenGL ES, it does once the renderer's self-test passes.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_benchmark/game.dart' show demoGpu;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _square =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="#3080ff"/></svg>';

// The game's size, in logical pixels. The width is over any renderer's limit
// at any pixel ratio.
const _width = 9000;
const _height = 48;

class _Game() extends FlameGame with HasRasterizer {
  @override
  RasterizerBackend get rasterizerGpu => demoGpu;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  RasterizerGpu.allowOpenGles = true;

  testWidgets('a game wider than its renderer takes draws its vectors', (
    tester,
  ) async {
    final gpu = RasterizerGpu.of(demoGpu);
    // On OpenGL ES, the renderer's self-test waits for a rasterized frame, so
    // pump one first.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(gpu.initialize);
    final svg = RasterizerSvg.fromBytes(utf8.encode(_square), gpu: demoGpu);
    final game = _Game()
      ..onGameResize(Vector2(_width.toDouble(), _height.toDouble()));
    await tester.runAsync(() async => await game.onLoad());
    // ignore: invalid_use_of_internal_member
    game.mount();
    // The camera puts the world's origin at the game's centre. Place a square
    // 100 pixels in from each end.
    for (final x in [100 - _width / 2, _width / 2 - 100]) {
      game.world.add(
        RasterizerSvgComponent(
          svg: svg,
          position: Vector2(x, 0),
          size: Vector2.all(40),
          anchor: Anchor.center,
        ),
      );
    }
    await tester.runAsync(game.ready);
    final renderer = (await tester.runAsync(() => game.rasterizerReady))!;
    final pixels = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      game.render(Canvas(recorder));
      final image = await recorder.endRecording().toImage(_width, _height);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;
    final max = renderer.maxViewportSize;
    final frame = game.rasterizerFrame!;
    debugPrint(
      'oversize: ${frame.backend.name} frame ${frame.width}×${frame.height}, '
      'limit $max',
    );
    if (frame.backend != RasterizerBackend.canvas) {
      expect(frame.width, max);
    }
    List<int> pixel(int x, int y) {
      final i = 4 * (y * _width + x);
      return pixels.sublist(i, i + 4);
    }

    for (final x in [100, _width - 100]) {
      final p = pixel(x, _height ~/ 2);
      expect(p[0], closeTo(0x30, 2), reason: 'at $x: $p');
      expect(p[1], closeTo(0x80, 2), reason: 'at $x: $p');
      expect(p[2], closeTo(0xff, 2), reason: 'at $x: $p');
      expect(p[3], 255, reason: 'at $x: $p');
    }
    expect(pixel(_width ~/ 2, _height ~/ 2)[3], 0);
    game.onRemove();
    svg.dispose();
  });
}
