// Checks the Collidable Svgs game with each renderer and 4 or 50 SVGs, on a
// device:
//   flutter test integration_test/collidable_test.dart -d <macos|emulator-5554>
//
// Each game must load, draw and name its renderer in the status bar. After
// about two seconds of collisions, its SVGs must still be in the arena. With
// flame_rasterizer, all its SVGs must draw in one run: a batch of entries,
// each an SVG placed in the frame, that the renderer draws together.
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/svg/collidable_svgs_example.dart';
import 'package:flame_rasterizer_example/stories/svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'renderer_status.dart';

const _timeout = Timeout(Duration(minutes: 1));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  for (final renderer in SvgRenderer.values) {
    for (final count in [4, 50]) {
      testWidgets('${renderer.name}, $count SVGs', timeout: _timeout, (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CollidableSvgsStory(
              settings: (renderer: renderer, count: count),
            ),
          ),
        );
        final game = tester
            .widget<GameWidget<CollidableSvgsExample>>(
              find.byWidgetPredicate((w) => w is GameWidget),
            )
            .game!;
        for (var i = 0; i < 600 && !game.isLoaded; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(game.isLoaded, isTrue);
        await settleRenderer(tester, renderer);
        // About two seconds, for the SVGs to hit each other and the walls.
        for (var i = 0; i < 120; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump();
        }
        final status = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .firstWhere((text) => text.contains(' · '), orElse: () => '');
        final line = '${renderer.name} collidable $count: $status';
        // ignore: avoid_print
        print('  RASTERIZER_EXAMPLE $line');
        // On the web, prints go to the browser's console: flutter drive gets
        // the status from the response data instead.
        (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] =
            status;
        expect(status, startsWith(rendererStatus(renderer)));
        if (renderer != SvgRenderer.flameSvg) {
          expect(status, contains('1 run, $count entries'));
        }
        expect(game.svgs, hasLength(count));
        final arena = game.arena.toRect();
        for (final svg in game.svgs) {
          expect(
            arena.inflate(svg.size.length).contains(svg.position.toOffset()),
            isTrue,
            reason: '${svg.position} left the arena, $arena',
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
