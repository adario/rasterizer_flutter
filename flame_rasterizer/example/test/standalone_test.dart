import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/main_revolute_pinball.dart';
import 'package:flame_rasterizer_example/main_tube_shooter.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';

void main() {
  /// Pumps [frames] frames of 16 milliseconds: the games never settle.
  Future<void> pumpFrames(WidgetTester tester, int frames) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Returns the running game of type [G].
  G gameOf<G extends FlameGame>(WidgetTester tester) => tester
      .widget<GameWidget<G>>(find.byWidgetPredicate((w) => w is GameWidget<G>))
      .game!;

  /// Expects the app to be titled [title], with no app bar, and the status
  /// bar to be one line tall.
  void expectBars(WidgetTester tester, String title) {
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, title);
    expect(find.byType(AppBar), findsNothing);
    final status = find.textContaining(RegExp(r'^canvas \('));
    expect(tester.widget<Text>(status).maxLines, 1);
  }

  /// Opens the renderer menu, and picks the entry that shows [text].
  Future<void> pick(WidgetTester tester, String text) async {
    await tester.tap(find.byType(DropdownButton<SvgRenderer>));
    await pumpFrames(tester, 30);
    await tester.tap(find.text(text).last);
    await pumpFrames(tester, 30);
  }

  testWidgets('Tube Shooter runs on its own, with its status bar, and the '
      'menu switches its renderer', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TubeShooterApp(sound: false));
    await pumpFrames(tester, 30);
    expect(find.byType(Widgetbook), findsNothing);
    expectBars(tester, 'Tube Shooter');
    final game = gameOf<TubeShooterExample>(tester);
    expect(game.isLoaded, isTrue);
    expect(game.descendants().whereType<FpsTextComponent>(), isNotEmpty);
    // The status bar shows the renderer, which is the canvas one here, and
    // the frame times.
    expect(find.textContaining(RegExp(r'^canvas \(.*render ')), findsOneWidget);
    // Tube Shooter draws no SVGs, so Flame SVG shows Flame.
    await pick(tester, 'Flame');
    final flameGame = gameOf<TubeShooterExample>(tester);
    expect(flameGame, isNot(same(game)));
    expect(flameGame.isLoaded, isTrue);
    expect(find.textContaining("Flame's PathComponent"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // Not switched to Flame SVG: flame_svg games with random SVGs need a test
  // file of their own (see cache_knobs_test.dart).
  testWidgets('Revolute Pinball runs on its own, with its status bar', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1000, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RevolutePinballApp(sound: false));
    await pumpFrames(tester, 30);
    expect(find.byType(Widgetbook), findsNothing);
    expectBars(tester, 'Revolute Pinball');
    final game = gameOf<RevolutePinballExample>(tester);
    expect(game.isLoaded, isTrue);
    expect(game.descendants().whereType<FpsTextComponent>(), isNotEmpty);
    expect(find.textContaining(RegExp(r'^canvas \(.*render ')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
