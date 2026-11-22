import 'dart:math' as math;

import 'package:flame/components.dart' show Component, Vector2;
import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/bucket_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/flipper_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/trail_component.dart';
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

  testWidgets('a key starts the game, and drops 10 bodies', (tester) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 30);
    expect(textsOf(game), isNot(contains('READY')));
    expect(textsOf(game), contains('DROP 1'));
    expect(bodiesOf(game), 10);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a body hitting the wheel trails', (tester) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    for (var i = 0; i < 300 && partsOf<TrailComponent>(game).isEmpty; i++) {
      await pumpFrames(tester, 1);
    }
    expect(partsOf<TrailComponent>(game), isNotEmpty);
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

  testWidgets("each Shift key kicks its side's flipper", (tester) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    final [left, right] = partsOf<FlipperComponent>(game);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftRight);
    await pumpFrames(tester, 2);
    expect(left.kicking, isFalse);
    expect(right.kicking, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await pumpFrames(tester, 2);
    expect(left.kicking, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a body counts in a bucket after 1 s in it, and then scores', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    final bucket = partsOf<BucketComponent>(game).first;
    Ball ball() => Ball(
      bucket.inner.center.toVector2(),
      Vector2.zero(),
      radius: 1,
      color: ExampleColors.slate,
    );
    Iterable<String> texts() =>
        bucket.children.whereType<VectorTextComponent>().map((t) => t.text);

    // One that leaves before 1 s never counts, nor scores.
    final passing = ball();
    game.addBody(passing);
    await pumpFrames(tester, 30);
    expect(bucket.counts(passing), isFalse);
    passing.body.setTransform(Vector2.zero(), passing.body.rotation);
    await pumpFrames(tester, 60);
    expect(bucket.counts(passing), isFalse);
    expect(texts(), isEmpty);

    final staying = ball();
    game.addBody(staying);
    await pumpFrames(tester, 70);
    expect(bucket.counts(staying), isTrue);
    expect(texts(), contains('1'));
    expect(game.score, 0);
    // It rocks in the bucket's bottom for a while.
    for (var i = 0; i < 600 && game.score == 0; i++) {
      await pumpFrames(tester, 1);
    }
    await pumpFrames(tester, 2);
    expect(game.score, greaterThan(0));
    expect(texts().where((t) => t.endsWith('%')), hasLength(1));

    // Once out and back in, it doesn't score again.
    final score = game.score;
    staying.body
      ..setTransform(Vector2.zero(), staying.body.rotation)
      ..linearVelocity = Vector2.zero();
    await pumpFrames(tester, 10);
    staying.body
      ..setTransform(bucket.inner.center.toVector2(), staying.body.rotation)
      ..linearVelocity = Vector2.zero();
    await pumpFrames(tester, 300);
    expect(bucket.counts(staying), isTrue);
    expect(game.score, score);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a bucket emptying kicks the other's bodies up and out", (
    tester,
  ) async {
    // Wide enough for the two balls that fill a bucket to sit side by side.
    tester.view
      ..physicalSize = const Size(1000, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await pumpGame(tester);
    final [left, right] = partsOf<BucketComponent>(game);
    Ball ball(Vector2 position, double radius) => Ball(
      position,
      Vector2.zero(),
      radius: radius,
      color: ExampleColors.slate,
    );
    final kicked = ball(right.inner.center.toVector2(), 1);
    game.addBody(kicked);
    await pumpFrames(tester, 70);
    expect(right.counts(kicked), isTrue);

    // Two balls of a quarter of the left bucket's area each fill it.
    final inner = left.inner;
    final rx = inner.width / 2;
    final ry = math.min(rx, inner.height);
    final area = inner.width * (inner.height - ry) + math.pi * rx * ry / 2;
    final radius = math.sqrt(area / 4 / math.pi);
    for (final side in [-1, 1]) {
      game.addBody(
        ball(
          inner.center.toVector2() + Vector2(side * 1.1 * radius, 0),
          radius,
        ),
      );
    }
    for (var i = 0; i < 600 && !left.full; i++) {
      await pumpFrames(tester, 1);
    }
    expect(left.full, isTrue);
    expect(kicked.body.linearVelocity.y, lessThan(0));
    var out = false;
    for (var i = 0; i < 60 && !out; i++) {
      await pumpFrames(tester, 1);
      out = kicked.body.position.y < right.inner.top;
    }
    expect(out, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drained energy ends the game, and a key starts a new one', (
    tester,
  ) async {
    final game = await pumpGame(tester);
    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 10);
    final [left, _] = partsOf<FlipperComponent>(game);
    final rest = left.body.angle;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    game
      ..score = 100
      ..drainedArea = double.maxFinite;
    await pumpFrames(tester, 2);
    expect(textsOf(game), containsAll(['GAME OVER', 'ENERGY 0%']));
    expect(textsOf(game), contains('DROP 1'));

    // The table goes on: the held flipper falls back, and the bodies move.
    final positions = [
      for (final body in game.balls) body.body.position.clone(),
    ];
    await pumpFrames(tester, 60);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(left.body.angle, closeTo(rest, 0.1));
    expect([
      for (final (i, body) in game.balls.indexed)
        body.body.position != positions[i],
    ], contains(true));

    // A drained body takes no energy, and a body in a bucket doesn't count.
    game.drainedArea = 1e6;
    final bucket = partsOf<BucketComponent>(game).first;
    final drained = Ball(
      Vector2(0, game.size.y / 10),
      Vector2.zero(),
      radius: 1,
      color: ExampleColors.slate,
    );
    final kept = Ball(
      bucket.inner.center.toVector2(),
      Vector2.zero(),
      radius: 1,
      color: ExampleColors.slate,
    );
    game
      ..addBody(drained)
      ..addBody(kept);
    await pumpFrames(tester, 70);
    expect(drained.isMounted, isFalse);
    expect(game.drainedArea, 1e6);
    expect(bucket.counts(kept), isFalse);
    expect(game.score, 100);
    expect(textsOf(game), contains('DROP 1'));

    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 2);
    expect(
      textsOf(game),
      containsAll(['READY', 'ENERGY 100%', 'DROP 0', 'SCORE 0']),
    );
    expect(textsOf(game), isNot(contains('GAME OVER')));
    expect(bodiesOf(game), 0);
    await tester.pumpWidget(const SizedBox());
  });

  // At speed 0, a new renderer's game shows the same bodies and HUD.
  testWidgets('a new renderer goes on from where the game was', (
    tester,
  ) async {
    late RevolutePinballExample game;
    Widget story(SvgRenderer renderer, {double speed = 1}) => MaterialApp(
      home: GameStory<RevolutePinballExample, RevolutePinballSnapshot>(
        renderer: renderer,
        create: (status, from) => game = RevolutePinballExample.of(
          renderer,
          status,
          pieces: false,
          from: from,
        ),
        snapshot: (game) => game.snapshot,
        speed: speed,
      ),
    );
    await tester.pumpWidget(story(SvgRenderer.rasterizer));
    await pumpWhileLoading(tester, () => !game.isLoaded);
    await pumpFrames(tester, 10);
    await press(tester, LogicalKeyboardKey.space);
    await pumpFrames(tester, 60);
    partsOf<CircleShuffler>(game).single.reverse();
    game.score = 123;
    await tester.pumpWidget(story(SvgRenderer.rasterizer, speed: 0));
    await pumpFrames(tester, 1);
    final snapshot = game.snapshot;
    expect(snapshot.balls.length + snapshot.svgBodies.length, 10);

    for (final renderer in [
      SvgRenderer.rasterizerCanvas,
      SvgRenderer.rasterizerAtlas,
    ]) {
      final last = game;
      await tester.pumpWidget(story(renderer, speed: 0));
      await pumpWhileLoading(tester, () => !game.isLoaded);
      expect(game, isNot(same(last)));
      await pumpFrames(tester, 2);
      final next = game.snapshot;
      expect(next.wheel, snapshot.wheel, reason: renderer.label);
      expect(partsOf<CircleShuffler>(game).single.reversing, isTrue);
      expect(
        next.balls.map((b) => b.ball),
        snapshot.balls.map((b) => b.ball),
        reason: renderer.label,
      );
      expect(
        next.svgBodies.map((b) => b.svgBody),
        snapshot.svgBodies.map((b) => b.svgBody),
        reason: renderer.label,
      );
      expect(textsOf(game), containsAll(['DROP 1', 'SCORE 123']));
      expect(textsOf(game), isNot(contains('READY')));
    }
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
    // Narrower than the widest table, so that its width changes.
    tester.view.physicalSize = const Size(700, 800);
    await pumpFrames(tester, 10);
    final flippers = partsOf<FlipperComponent>(game);
    expect(flippers, hasLength(2));
    expect(partsOf<BucketComponent>(game), hasLength(2));
    expect(partsOf<CircleShuffler>(game), hasLength(1));
    expect(flippers.first.body.position.x, isNot(closeTo(before, 0.1)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone, it zooms out, and the HUD sits below the table', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(411, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await pumpGame(tester);
    // At least 60 meters wide.
    expect(game.metersToPixels, closeTo(game.size.x / 60, 1e-6));
    // The flippers' lowest points are above the HUD's lines.
    final hud = [
      for (final text
          in game.camera.viewport.children.whereType<VectorTextComponent>())
        if (text.text != 'READY') text.toAbsoluteRect(),
    ];
    expect(hud, hasLength(4));
    final hudTop = hud.map((rect) => rect.top).reduce(math.min);
    for (final flipper in partsOf<FlipperComponent>(game)) {
      for (final v in flipper.outline) {
        final point = game.worldToScreen(flipper.body.worldPoint(v));
        expect(point.y, lessThan(hudTop));
      }
    }
    // The buckets are a fifth of the table's height deep, and the wheel's top
    // is level with their bottom.
    final ys = [
      for (final wall in partsOf<Wall>(game))
        for (final end in [wall.start, wall.end]) end.y,
    ];
    final height = ys.reduce(math.max) - ys.reduce(math.min);
    for (final bucket in partsOf<BucketComponent>(game)) {
      expect(bucket.inner.height, closeTo(0.2 * height, 1e-3));
    }
    final wheel = partsOf<CircleShuffler>(game).single;
    final wheelTop = wheel.body.position.y - wheel.scale * CircleShuffler.reach;
    for (final bucket in partsOf<BucketComponent>(game)) {
      expect(
        wheelTop,
        closeTo(bucket.inner.bottom + BucketComponent.thickness, 1e-3),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in landscape, the HUD sits beside a narrower table', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(520, 250)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final game = await pumpGame(tester);
    // The walls are 0.9 to 1.2 times the table's height apart.
    final xs = [
      for (final wall in partsOf<Wall>(game))
        for (final end in [wall.start, wall.end]) end.x,
    ];
    final width = xs.reduce(math.max) - xs.reduce(math.min);
    const height = 45.0;
    expect(width, inInclusiveRange(0.9 * height, 1.2 * height));
    expect(width * game.metersToPixels, lessThan(game.size.x * 0.6));
    // The HUD fits beside the table, so the table takes the whole height.
    expect(game.metersToPixels, closeTo(game.size.y / height, 1e-6));
    final left = game.worldToScreen(Vector2(xs.reduce(math.min), 0)).x;
    final right = game.worldToScreen(Vector2(xs.reduce(math.max), 0)).x;
    for (final text
        in game.camera.viewport.children.whereType<VectorTextComponent>()) {
      if (text.text != 'READY') {
        final rect = text.toAbsoluteRect();
        expect(rect.right < left || rect.left > right, isTrue);
      }
    }
    // READY is scaled down to an eighth of the height.
    final ready = game.camera.viewport.children
        .whereType<VectorTextComponent>()
        .firstWhere((text) => text.text == 'READY');
    expect(ready.toAbsoluteRect().height, closeTo(game.size.y / 8, 0.5));
    await tester.pumpWidget(const SizedBox());
  });
}
