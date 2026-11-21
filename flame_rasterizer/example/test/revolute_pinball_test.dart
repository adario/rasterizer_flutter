import 'package:flame/components.dart' show Component;
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/bucket_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/flipper_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

/// Pumps the game with [renderer], and waits for it to load.
Future<RevolutePinballExample> pumpGame(
  WidgetTester tester, {
  SvgRenderer renderer = SvgRenderer.rasterizer,
}) async {
  late RevolutePinballExample game;
  await tester.pumpWidget(
    MaterialApp(
      home: GameStory<RevolutePinballExample, Never>(
        renderer: renderer,
        create: (status, _) => game = RevolutePinballExample.of(
          renderer,
          status,
          pieces: false,
        ),
      ),
    ),
  );
  // The game's assets and Box2D load outside the test's fake time.
  await pumpWhileLoading(tester, () => !game.isLoaded);
  expect(game.isLoaded, isTrue);
  await pumpFrames(tester, 10);
  return game;
}

Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Presses and releases [key].
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
}

/// The texts in the game's viewport: READY or GAME OVER, and the HUD.
Iterable<String> textsOf(RevolutePinballExample game) => game
    .camera
    .viewport
    .children
    .whereType<VectorTextComponent>()
    .map((text) => text.text);

List<T> partsOf<T extends Component>(RevolutePinballExample game) =>
    game.world.descendants().whereType<T>().toList();

int bodiesOf(RevolutePinballExample game) =>
    game.svgBodies.length + game.balls.length;

void main() {
  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer. flame_svg shares its loads between
  // tests, so only the first test runs with it.
  for (final renderer in [
    SvgRenderer.flameSvg,
    SvgRenderer.rasterizer,
    SvgRenderer.rasterizerAtlas,
    SvgRenderer.rasterizerCanvas,
  ]) {
    testWidgets('the table loads with ${renderer.label}, at READY', (
      tester,
    ) async {
      final game = await pumpGame(tester, renderer: renderer);
      expect(
        textsOf(game),
        containsAll(['READY', 'ENERGY 100%', 'TARGET 0%', 'DROP 0', 'SCORE 0']),
      );
      expect(partsOf<FlipperComponent>(game), hasLength(2));
      expect(partsOf<BucketComponent>(game), hasLength(2));
      expect(partsOf<CircleShuffler>(game), hasLength(1));
      expect(bodiesOf(game), 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a key starts the game, and drops 15 bodies', (tester) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 30);
    expect(textsOf(game), isNot(contains('READY')));
    expect(textsOf(game), contains('DROP 1'));
    expect(bodiesOf(game), 15);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a key kicks its flipper, which falls back once released', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    final [left, right] = partsOf<FlipperComponent>(game);
    final rest = left.body.angle;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await pumpFrames(tester, 2);
    expect(left.kicking, isTrue);
    expect(right.kicking, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await pumpFrames(tester, 60);
    expect(left.kicking, isFalse);
    expect(left.body.angle, closeTo(rest, 0.1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drained energy ends the game, and a key starts a new one', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 10);
    game
      ..score = 100
      ..drainedArea = double.maxFinite;
    await pumpFrames(tester, 2);
    expect(textsOf(game), containsAll(['GAME OVER', 'ENERGY 0%']));
    expect(game.world.timeScale, 0);

    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 2);
    expect(
      textsOf(game),
      containsAll(['READY', 'ENERGY 100%', 'DROP 0', 'SCORE 0']),
    );
    expect(textsOf(game), isNot(contains('GAME OVER')));
    expect(game.world.timeScale, 1);
    expect(bodiesOf(game), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a resize builds the table again, for the new size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await pumpGame(tester);
    final before = partsOf<FlipperComponent>(game).first.body.position.x;
    tester.view.physicalSize = const Size(900, 800);
    await pumpFrames(tester, 10);
    final flippers = partsOf<FlipperComponent>(game);
    expect(flippers, hasLength(2));
    expect(partsOf<BucketComponent>(game), hasLength(2));
    expect(partsOf<CircleShuffler>(game), hasLength(1));
    expect(flippers.first.body.position.x, isNot(closeTo(before, 0.1)));
    await tester.pumpWidget(const SizedBox());
  });
}
