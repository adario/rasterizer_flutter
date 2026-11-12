import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

void main() {
  // One test, in a file of its own. These games load random SVGs with
  // flame_svg, which shares its loads between tests. A test's fake time
  // doesn't run another test's loads, so another test's game could wait for
  // them forever. example_test.dart checks Svg Renderers' cache knobs.
  testWidgets("the other use cases' flame_svg knobs show only with flame_svg, "
      'in Multiple Shapes with SVGs only', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // The game's assets load outside the test's fake time.
    Future<void> load() async {
      final game =
          tester
                  .widget<GameWidget>(
                    find.byWidgetPredicate((w) => w is GameWidget),
                  )
                  .game!
              as FlameGame;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      expect(game.isLoaded, isTrue);
    }

    Future<void> pick(SvgRenderer renderer) async {
      await tester.tap(find.byType(DropdownMenu<SvgRenderer>));
      await settle();
      await tester.tap(find.text(renderer.label).last);
      await settle();
      await load();
    }

    for (final path in [
      'svg/collidable-svgs',
      'collision-detection/multiple-shapes',
      'forge2d/revolute-joint-svgs',
    ]) {
      await tester.pumpWidget(
        FlameRasterizerExamples(initialRoute: '/?path=$path'),
      );
      await settle();
      await load();
      expect(find.text('Renderer'), findsOneWidget, reason: path);
      expect(find.text('Cache mode'), findsNothing, reason: path);
      expect(find.text('Cache size'), findsNothing, reason: path);
      await pick(SvgRenderer.flameSvg);
      if (path == 'collision-detection/multiple-shapes') {
        // Multiple Shapes starts with paths, which flame_svg doesn't draw.
        expect(find.text('Cache mode'), findsNothing);
        await tester.tap(find.text('SVGs'));
        await settle();
        await load();
      }
      expect(find.text('Cache mode'), findsOneWidget, reason: path);
      expect(find.text('Cache size'), findsOneWidget, reason: path);
      await pick(SvgRenderer.rasterizerCanvas);
      expect(find.text('Cache mode'), findsNothing, reason: path);
      expect(find.text('Cache size'), findsNothing, reason: path);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
