// Checks the Revolute Joint Svgs game with each renderer, on a device:
//   flutter test integration_test/forge2d_test.dart -d <macos|emulator-5554>
//
// Each game must load Box2D, drop 45 bodies, 15 at each of three places, and
// keep them inside its walls. With Pieces on, it must name its renderer in
// the status bar. With flame_rasterizer, all its SVG bodies must draw in one
// run: a batch of entries, each an SVG placed in the frame, that the renderer
// draws together.
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/forge2d/forge2d.dart';
import 'package:flame_rasterizer_example/stories/forge2d/revolute_joint_svgs_example.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'renderer_status.dart';

const _timeout = Timeout(Duration(minutes: 1));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  /// Pumps [frames] live frames, about 16 ms apart.
  Future<void> wait(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
  }

  /// The status bar's text, or an empty string before it shows.
  String status(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .firstWhere((text) => text.contains(' · '), orElse: () => '');

  for (final renderer in SvgRenderer.values) {
    testWidgets(renderer.name, timeout: _timeout, (tester) async {
      Widget story({bool pieces = false}) => MaterialApp(
        home: RevoluteJointSvgsStory(
          settings: (renderer: renderer, pieces: pieces),
        ),
      );
      await tester.pumpWidget(story());
      final game = tester
          .widget<GameWidget<RevoluteJointSvgsExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      for (var i = 0; i < 600 && !game.isLoaded; i++) {
        await wait(tester, 1);
      }
      expect(game.isLoaded, isTrue);
      await settleRenderer(tester, renderer);
      final rect = tester.getRect(
        find.byType(GameWidget<RevoluteJointSvgsExample>),
      );
      await tester.tapAt(Offset(rect.center.dx, rect.top + 60));
      game
        ..drop(Vector2(-25, -28))
        ..drop(Vector2(25, -28));
      // About three seconds, for the bodies to fall.
      await wait(tester, 180);
      final svgs = game.svgBodies.length;
      expect(svgs + game.balls.length, 45);
      final arena = Rect.fromCenter(
        center: Offset.zero,
        width: game.size.x / game.metersToPixels,
        height: game.size.y / game.metersToPixels,
      );
      for (final body in [...game.svgBodies, ...game.balls]) {
        final position = body.body.position;
        expect(
          arena.contains(Offset(position.x, position.y)),
          isTrue,
          reason: '$position left the arena, $arena',
        );
      }
      await tester.pumpWidget(story(pieces: true));
      await wait(tester, 10);
      final line = '${renderer.name} revolute joint: ${status(tester)}';
      // ignore: avoid_print
      print('  RASTERIZER_EXAMPLE $line');
      // On the web, prints go to the browser's console: flutter drive gets
      // the status from the response data instead.
      (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] =
          status(tester);
      final text = status(tester);
      expect(text, startsWith(rendererStatus(renderer)));
      if (renderer != SvgRenderer.flameSvg) {
        expect(text, contains('1 run, $svgs entries'));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
