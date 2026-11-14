import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/svg/collidable_svgs_example.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';
import 'slow_bundle.dart';

/// The Collidable Svgs story with [renderer] and [count] SVGs, picked with a
/// seeded random, at [speed].
///
/// A new count changes the same game.
Widget story(SvgRenderer renderer, {int count = 4, double speed = 1}) =>
    MaterialApp(
      home: GameStory<CollidableSvgsExample, Never>(
        renderer: renderer,
        create: (status, _) => CollidableSvgsExample.of(
          (renderer: renderer, count: count),
          status,
          random: math.Random(1),
        ),
        update: (game) => game.count = count,
        speed: speed,
      ),
    );

/// Pumps [story], and waits for its game to load.
Future<CollidableSvgsExample> pumpGame(
  WidgetTester tester,
  SvgRenderer renderer, {
  int count = 4,
  double speed = 1,
}) async {
  await tester.pumpWidget(story(renderer, count: count, speed: speed));
  final game = tester
      .widget<GameWidget<CollidableSvgsExample>>(
        find.byWidgetPredicate((w) => w is GameWidget),
      )
      .game!;
  // The game's assets load outside the test's fake time.
  await pumpWhileLoading(tester, () => !game.isLoaded);
  expect(game.isLoaded, isTrue);
  await tester.pump(const Duration(milliseconds: 16));
  return game;
}

void main() {
  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer. Only one test loads with flame_svg:
  // vector_graphics shares its loads between tests, and a test's fake time
  // doesn't run another test's loads.
  for (final (renderer, status) in [
    (SvgRenderer.rasterizer, 'flame_rasterizer, canvas (noImpeller)'),
    (SvgRenderer.flameSvg, 'flame_svg'),
  ]) {
    testWidgets('the game loads with ${renderer.label}', (tester) async {
      final game = await pumpGame(tester, renderer, count: 12);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.svgs, hasLength(12));
      for (final svg in game.svgs) {
        expect(svg.children.whereType<SvgHitbox>(), hasLength(1));
      }
      expect(find.textContaining(status), findsOneWidget);
      expect(find.textContaining('collision'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('two that collide swap their velocities', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, count: 2);
    final [a, b] = game.svgs;
    // Two SVGs of the same size, nearly on top of each other, moving toward
    // each other.
    b.size = a.size.clone();
    a
      ..position = Vector2.zero()
      ..velocity.setValues(100, 0);
    b
      ..position = Vector2(a.size.x / 10, 0)
      ..velocity.setValues(-200, 0);
    game.update(0);
    expect(a.velocity, Vector2(-200, 0));
    expect(b.velocity, Vector2(100, 0));
    expect(game.collisions, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one that hits a wall reflects off it', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, count: 2);
    final [svg, other] = game.svgs;
    final rect = game.arena.toRect();
    other.position = Vector2(rect.left + other.size.length, 0);
    svg
      ..position = Vector2(rect.right, 0)
      ..velocity.setValues(200, 50);
    game.update(0);
    expect(svg.velocity, Vector2(-200, 50));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one in a corner moves away from both walls', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, count: 2);
    final [svg, other] = game.svgs;
    final rect = game.arena.toRect();
    other.position = Vector2(rect.left + other.size.length, 0);
    // It moves into both walls.
    svg
      ..position = Vector2(rect.right, rect.top)
      ..velocity.setValues(200, -50);
    game.update(0);
    expect(svg.velocity, Vector2(-200, 50));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one past a wall comes back, moving away from it', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, count: 2);
    final [svg, other] = game.svgs;
    final rect = game.arena.toRect();
    other.position = Vector2(rect.left + other.size.length, 0);
    svg
      ..position = Vector2(rect.right + svg.size.length, rect.top - 10)
      ..velocity.setValues(200, -50);
    game.update(0);
    expect(svg.position, Vector2(rect.right, rect.top));
    expect(svg.velocity, Vector2(-200, 50));
    await tester.pumpWidget(const SizedBox());
  });

  // With the knob's most, 50 SVGs, another SVG sometimes sends one back
  // toward the walls while it still touches them. The walls turn it back at
  // each frame of a contact, and an SVG past a wall comes back.
  testWidgets('many SVGs stay in the arena', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, count: 50);
    final arena = game.arena.toRect();
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final svg in game.svgs) {
        expect(
          arena.inflate(svg.size.length).contains(svg.position.toOffset()),
          isTrue,
          reason: '${svg.position} left the arena, $arena, frame $i',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  // The SVGs it has stay, shrunk to make room, and their hitboxes shrink with
  // them.
  testWidgets('a new SVG number adds SVGs to the game, or removes some', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    final kept = [...game.svgs];
    final width = kept.first.size.x;
    await tester.pumpWidget(story(SvgRenderer.rasterizer, count: 50));
    // New SVGs load outside the test's fake time.
    await pumpWhileLoading(tester, () => game.svgs.length != 50);
    await tester.pump(const Duration(milliseconds: 16));
    final current = tester
        .widget<GameWidget<CollidableSvgsExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    expect(current, same(game));
    expect(game.svgs, hasLength(50));
    expect(game.svgs.take(4), kept);
    expect(game.world.children.whereType<CollidableSvg>(), hasLength(50));
    final first = kept.first;
    expect(first.size.x, lessThan(width));
    expect(
      first.children.whereType<RasterizerSvgComponent>().single.size,
      first.size,
    );
    final hitbox = first.children.whereType<SvgHitbox>().single;
    expect(
      hitbox.scale.x,
      closeTo(first.size.x / hitbox.outline.rect.width, 1e-6),
    );

    await tester.pumpWidget(story(SvgRenderer.rasterizer, count: 2));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.svgs, kept.take(2));
    expect(game.world.children.whereType<CollidableSvg>(), hasLength(2));
    expect(first.size.x, width);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('at speed 0, the SVGs stand still', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, speed: 0);
    final positions = [for (final svg in game.svgs) svg.position.clone()];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect([for (final svg in game.svgs) svg.position], positions);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a resize while it loads resizes the arena', (tester) async {
    Flame.bundle = SlowBundle();
    addTearDown(() => Flame.bundle = rootBundle);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(story(SvgRenderer.rasterizer));
    final game = tester
        .widget<GameWidget<CollidableSvgsExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    await tester.pump();
    expect(game.isLoaded, isFalse);
    tester.view.physicalSize = tester.view.physicalSize * 1.5;
    await tester.pump();
    for (var i = 0; i < 100 && !game.isLoaded; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(game.isLoaded, isTrue);
    expect(game.arena.size, game.size);
    await tester.pumpWidget(const SizedBox());
  });
}
