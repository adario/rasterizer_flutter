// Checks the Multiple Shapes game with each renderer and each kind of shapes,
// on a device such as macos or emulator-5554:
//   flutter test integration_test/multiple_shapes_test.dart -d <device>
//
// Each game must load, draw and name its renderer in the status bar. With
// flame_rasterizer, all its shapes, SVGs and paths alike, must stay in one
// run while some are tinted. A run is a batch of entries, each an SVG or a
// path placed in the frame, that the renderer draws together.
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/collision_detection.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/multiple_shapes_example.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'renderer_status.dart';

const _timeout = Timeout(Duration(minutes: 1));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  for (final shapes in Shapes.values) {
    for (final renderer in SvgRenderer.values) {
      final name = '${renderer.name} ${shapes.name}';
      testWidgets(name, timeout: _timeout, (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MultipleShapesStory(
              settings: (renderer: renderer, shapes: shapes, count: 15),
            ),
          ),
        );
        final game = tester
            .widget<GameWidget<MultipleShapesExample>>(
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
        // Of about two seconds of collisions, the frames drawn while some
        // shapes were tinted.
        var tintedFrames = 0;
        // With flame_rasterizer, the frames that its renderer drew, whose runs
        // and entries the loop checks.
        var drawnFrames = 0;
        for (var i = 0; i < 120; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)),
          );
          await tester.pump();
          final tinted = game.tintedShapes.where((s) => s.isColliding).length;
          final frame = game is RasterizerMultipleShapesExample
              ? game.rasterizerFrame
              : null;
          // Null until its renderer is ready.
          if (frame != null) {
            drawnFrames++;
            expect(frame.runs, hasLength(1));
            // The mesh renderer leaves out entries outside the viewport, as a
            // shape is until it wraps around.
            expect(
              frame.entryCount,
              renderer == SvgRenderer.rasterizer
                  ? lessThanOrEqualTo(game.tintedShapes.length)
                  : game.tintedShapes.length,
            );
          }
          if (tinted > 0) {
            tintedFrames++;
          }
        }
        expect(tintedFrames, greaterThan(0));
        // Its renderer must be ready for most of the frames.
        if (renderer != SvgRenderer.flameSvg) {
          expect(drawnFrames, greaterThan(60));
        }
        final status = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .firstWhere((text) => text.contains(' · '), orElse: () => '');
        final line = '$name multiple: $status';
        // ignore: avoid_print
        print('  RASTERIZER_EXAMPLE $line');
        // On the web, prints go to the browser's console: flutter drive gets
        // the status from the response data instead.
        (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] =
            status;
        expect(
          status,
          startsWith(
            renderer == SvgRenderer.flameSvg && shapes == Shapes.paths
                ? "Flame's PathComponent · "
                : rendererStatus(renderer),
          ),
        );
        final what = shapes == Shapes.svgs ? 'SVGs' : 'paths';
        expect(status, contains('$what and a snowman'));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
