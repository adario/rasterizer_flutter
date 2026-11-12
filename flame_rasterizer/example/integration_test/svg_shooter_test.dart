// Checks the Svg Shooter game with each renderer, on a device:
//   flutter test integration_test/svg_shooter_test.dart -d <macos|emulator-5554>
//
// Each game must load, draw and name its renderer in the status bar. It then
// fires for about two seconds, sweeping from side to side, and must score,
// whether or not the game is over by then. With flame_rasterizer, its SVGs
// must draw in at most two runs, as the explosions' particles split them. A
// run is a batch of entries, each an SVG placed in the frame, that the
// renderer draws together.
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'renderer_status.dart';

const _timeout = Timeout(Duration(minutes: 1));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  for (final renderer in SvgRenderer.values) {
    testWidgets(renderer.name, timeout: _timeout, (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SvgShooterStory(renderer: renderer)),
      );
      final gameWidget = find.byWidgetPredicate((w) => w is GameWidget);
      final game = tester
          .widget<GameWidget<SvgShooterExample>>(gameWidget)
          .game!;
      for (var i = 0; i < 600 && !game.isLoaded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(game.isLoaded, isTrue);
      await settleRenderer(tester, renderer);
      // About two seconds of fire, sweeping from side to side.
      final gesture = await tester.startGesture(tester.getCenter(gameWidget));
      for (var i = 0; i < 120; i++) {
        await gesture.moveBy(Offset(i % 60 < 30 ? 4 : -4, 0));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)),
        );
        await tester.pump();
      }
      final status = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .firstWhere((text) => text.contains(' · '), orElse: () => '');
      await gesture.up();
      final line = '${renderer.name} shooter: $status';
      // ignore: avoid_print
      print(
        '  RASTERIZER_EXAMPLE $line · score ${game.score} · '
        'health ${game.player.health}%',
      );
      // On the web, prints go to the browser's console: flutter drive gets
      // the status from the response data instead.
      (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] =
          status;
      expect(status, startsWith(rendererStatus(renderer)));
      if (renderer != SvgRenderer.flameSvg) {
        expect(status, contains(RegExp(r'\b[12] runs?, ')));
      }
      expect(game.score, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
