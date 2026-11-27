import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/main_revolute_pinball.dart';
import 'package:flame_rasterizer_example/main_tube_runner.dart';
import 'package:flame_rasterizer_example/main_tube_shooter.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
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

  /// Expects the app to be titled [title], with no app bar and no status bar,
  /// and the game to draw with [renderer]: its status starts with that.
  void expectBars(
    WidgetTester tester,
    String title,
    StoryGame game, {
    String renderer = 'Canvas',
  }) {
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, title);
    expect(find.byType(AppBar), findsNothing);
    expect(find.textContaining(' · render '), findsNothing);
    expect(game.status.value, startsWith('$renderer · render '));
  }

  /// Opens the settings dialog, picks the renderer that shows [text], and
  /// [then] does what else it's given, before the dialog's Done.
  Future<void> pick(
    WidgetTester tester,
    String text, {
    Future<void> Function()? then,
  }) async {
    await tester.tap(find.byIcon(Icons.settings));
    await pumpFrames(tester, 30);
    await tester.tap(find.byType(DropdownButton<SvgRenderer>));
    await pumpFrames(tester, 30);
    await tester.tap(find.text(text).last);
    await pumpFrames(tester, 30);
    await then?.call();
    await tester.tap(find.text('Done'));
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
    final game = gameOf<TubeShooterExample>(tester);
    expect(game.isLoaded, isTrue);
    expect(game.descendants().whereType<FpsTextComponent>(), isNotEmpty);
    // The renderer is the canvas one here.
    expectBars(tester, 'Tube Shooter', game);
    // Tube Shooter draws no SVGs, so Flame SVG shows Flame.
    await pick(tester, 'Flame');
    final flameGame = gameOf<TubeShooterExample>(tester);
    expect(flameGame, isNot(same(game)));
    expect(flameGame.isLoaded, isTrue);
    expectBars(tester, 'Tube Shooter', flameGame, renderer: 'Flame');
    await tester.pumpWidget(const SizedBox());
  });

  // Not switched to Flame SVG: flame_svg games with random SVGs need a test
  // file of their own (see cache_knobs_test.dart).
  testWidgets('Revolute Pinball runs on its own, and the dialog changes its '
      'settings', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RevolutePinballApp(sound: false));
    await pumpFrames(tester, 30);
    expect(find.byType(Widgetbook), findsNothing);
    final game = gameOf<RevolutePinballExample>(tester);
    expect(game.isLoaded, isTrue);
    expect(game.descendants().whereType<FpsTextComponent>(), isNotEmpty);
    expectBars(tester, 'Revolute Pinball', game);
    expect(game.pieces, isFalse);
    // The same game shows its pieces, and no cache settings without Flame
    // SVG.
    await tester.tap(find.byIcon(Icons.settings));
    await pumpFrames(tester, 30);
    expect(find.text('Cache mode'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await pumpFrames(tester, 30);
    await tester.tap(find.text('Done'));
    await pumpFrames(tester, 30);
    expect(gameOf<RevolutePinballExample>(tester), same(game));
    expect(game.pieces, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tube Runner runs on its own, paused while the dialog shows, '
      'which switches its renderer, going on from where it was', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1000, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TubeRunnerApp(sound: false));
    await pumpFrames(tester, 30);
    expect(find.byType(Widgetbook), findsNothing);
    final game = gameOf<TubeRunnerExample>(tester);
    expect(game.isLoaded, isTrue);
    expect(game.descendants().whereType<FpsTextComponent>(), isNotEmpty);
    expectBars(tester, 'Tube Runner', game);
    game.score = 1234;
    // Tube Runner draws no SVGs, so Flame SVG shows Flame.
    await pick(
      tester,
      'Flame',
      then: () async {
        expect(game.isPaused, isTrue);
        final flown = game.runner.flown;
        await pumpFrames(tester, 30);
        expect(game.runner.flown, flown);
        await tester.tap(find.byType(DropdownButton<Tube>));
        await pumpFrames(tester, 30);
        await tester.tap(find.text('Diamond').last);
        await pumpFrames(tester, 30);
      },
    );
    final flameGame = gameOf<TubeRunnerExample>(tester);
    expect(flameGame, isNot(same(game)));
    expect(flameGame.isLoaded, isTrue);
    expect(flameGame.isPaused, isFalse);
    expect(flameGame.score, 1234);
    expect(flameGame.tube, same(Tubes.diamond));
    expectBars(tester, 'Tube Runner', flameGame, renderer: 'Flame');
    await tester.pumpWidget(const SizedBox());
  });
}
