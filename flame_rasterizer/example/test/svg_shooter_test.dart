// Checks the Svg Shooter example in widget tests: it loads with each
// renderer, and its waves, controls, missiles, hits, health, Game Over and
// stars behave as its docs say.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame/particles.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/bottom_right_text.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_creator.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/game_over_text.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/missile_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/star_background_creator.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';
import 'slow_bundle.dart';

/// The Svg Shooter story with [renderer], at [zoom]. A seeded random makes
/// the game repeat from run to run.
Widget story(SvgRenderer renderer, {double zoom = 1}) => MaterialApp(
  home: GameStory<SvgShooterExample>(
    create: (status) =>
        SvgShooterExample.of(renderer, status, random: math.Random(1)),
    zoom: zoom,
  ),
);

/// Pumps [story], and waits for its game and its stars to load.
Future<SvgShooterExample> pumpGame(
  WidgetTester tester,
  SvgRenderer renderer, {
  double zoom = 1,
}) async {
  await tester.pumpWidget(story(renderer, zoom: zoom));
  final game = tester
      .widget<GameWidget<SvgShooterExample>>(
        find.byWidgetPredicate((w) => w is GameWidget),
      )
      .game!;
  // The assets and the stars' image load in real time, outside the test's
  // fake time.
  await pumpWhileLoading(
    tester,
    () => !(game.isLoaded && game.starGroup.children.isNotEmpty),
  );
  expect(game.isLoaded, isTrue);
  expect(game.starGroup.children, isNotEmpty);
  // The game loop's first frame advances no time, so pump another one.
  await tester.pump(const Duration(milliseconds: 16));
  return game;
}

/// The enemies of [game].
Iterable<EnemyComponent> enemiesOf(SvgShooterExample game) =>
    game.enemyGroup.children.whereType<EnemyComponent>();

/// The missiles of [game].
Iterable<MissileComponent> missilesOf(SvgShooterExample game) =>
    game.missileGroup.children.whereType<MissileComponent>();

/// The health text, the first of [game]'s texts at the bottom right.
String healthTextOf(SvgShooterExample game) =>
    game.camera.viewport.children.whereType<BottomRightText>().first.text;

/// Stops [game]'s waves, and removes its enemies.
void stopWaves(SvgShooterExample game) {
  game.world.children.whereType<EnemyCreator>().single.timer.stop();
  game.enemyGroup.removeAll(enemiesOf(game).toList());
}

/// Pumps [frames] frames of 16 ms each.
Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Expects [game]'s enemies to be a first wave in the game's top 20%, well
/// above the player.
///
/// The enemies may have fallen for up to [seconds], at the fastest enemy
/// speed.
void expectFirstWave(SvgShooterExample game, {double seconds = 0.016}) {
  final player = game.player;
  final bottom = game.size.y * 0.2;
  expect(bottom, lessThan(player.y - player.size.y / 2 - 100));
  const fastest = EnemyComponent.speed * (1 + EnemyComponent.speedSpread);
  final enemies = enemiesOf(game);
  expect(enemies, isNotEmpty);
  for (final enemy in enemies) {
    expect(enemy.y + enemy.size.y / 2, lessThan(bottom + fastest * seconds));
  }
}

/// The paint of [component]'s SVG: its first child with a paint.
Paint svgPaintOf(PositionComponent component) =>
    component.children.whereType<HasPaint>().first.paint;

void main() {
  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer. Only one test loads SVGs with
  // flame_svg: vector_graphics shares its loads between tests, and one
  // test's fake time doesn't run another test's loads.
  for (final (renderer, status) in [
    (SvgRenderer.rasterizer, 'flame_rasterizer, canvas (noImpeller)'),
    (SvgRenderer.flameSvg, 'flame_svg'),
  ]) {
    testWidgets('the game loads with ${renderer.label}', (tester) async {
      final game = await pumpGame(tester, renderer);
      // Full health before any frame.
      expect(game.player.health, 100);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final player = game.player;
      // At the center of the game's size at load. The status bar's second
      // line has made the game shorter since.
      expect(player.x, game.size.x / 2);
      expect(player.y, closeTo(game.size.y / 2, 10));
      // 64 wide, and as high as its SVG's proportions make it.
      expect(player.size, Vector2(64, 42));
      final svgSize = game.playerSvg.size;
      expect(svgSize.x / svgSize.y, closeTo(64 / 42, 1e-3));
      final enemies = enemiesOf(game);
      expect(enemies, isNotEmpty);
      for (final component in [player, ...enemies]) {
        expect(component.children.whereType<SvgHitbox>(), hasLength(1));
      }
      expect(find.textContaining(status), findsOneWidget);
      // At the bottom right, from the top: the health, the score and the
      // number of components.
      final [health, score, components] = game.camera.viewport.children
          .whereType<BottomRightText>()
          .toList();
      expect(health.text, matches(RegExp(r'^Health: \d+%$')));
      expect(score.text, 'Score: 0');
      expect(components.text, startsWith('Components: '));
      final right = game.size.x - StoryGame.hudMargin;
      final bottom = game.size.y - StoryGame.hudMargin;
      expect(components.position, Vector2(right, bottom));
      expect(score.position, Vector2(right, bottom - components.size.y));
      expect(health.position, Vector2(right, bottom - 2 * components.size.y));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the waves have the four enemies, at random, in the six '
      'colours of Revolute Joint SVGs, at random', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final enemies = enemiesOf(game).toList();
    expect(game.enemyKinds, hasLength(4));
    expect({for (final enemy in enemies) enemy.kind}, game.enemyKinds.toSet());
    expect({
      for (final enemy in enemies) enemy.color,
    }, ExampleColors.dynamics.toSet());
    for (final enemy in enemies) {
      expect(enemy.size, Vector2.all(29));
      // Its white SVG is tinted with its colour.
      expect(
        svgPaintOf(enemy).colorFilter,
        RasterizerColorTransform.mode(enemy.color, BlendMode.srcATop)!.filter,
      );
      final swings = enemy.children.whereType<RotateEffect>();
      if (enemy.kind.swings) {
        expect(swings, hasLength(1));
        expect(enemy.angle.abs(), lessThanOrEqualTo(15 * math.pi / 180));
        expect(enemy.velocity, Vector2(0, 135));
      } else {
        expect(swings, isEmpty);
        // Turned by 180°, tilted by whole degrees, and flying where it
        // points. The tilt is the angle past the turn, from -180° to 180°.
        final turn = enemy.angle - math.pi;
        final tilt = math.atan2(math.sin(turn), math.cos(turn)) * 180 / math.pi;
        expect(tilt, inInclusiveRange(-15.001, 15.001));
        expect(tilt, closeTo(tilt.roundToDouble(), 1e-3));
        final heading = Vector2(0, -1)..rotate(enemy.angle);
        expect(enemy.velocity.normalized().distanceTo(heading), lessThan(1e-3));
        expect(enemy.velocity.length, inInclusiveRange(121.49, 148.51));
      }
      expect(enemy.x, inInclusiveRange(-20, game.size.x + 20));
    }
    final ships = enemies.where((enemy) => !enemy.kind.swings);
    expect({for (final ship in ships) ship.angle}.length, greaterThan(10));
    expect(
      {for (final ship in ships) ship.velocity.length}.length,
      greaterThan(10),
    );
    expect(
      [for (final kind in game.enemyKinds) kind.swings],
      [false, false, false, true],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a game starts with a first wave, as if the waves had been '
      "coming for a while, all in the game's top 20%", (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    expect(EnemyCreator.firstWaveDepth, 0.2);
    // A wave of 5 every 135 / 15 = 9 units down from the top, each wave's
    // bottom above 20% of the game's height. They've fallen for one frame
    // since.
    final bottom = game.size.y * 0.2;
    final waves = [for (var y = 0.0; y + 14.5 < bottom; y += 9) y];
    expect(waves.length, greaterThan(5));
    expect(enemiesOf(game), hasLength(5 * waves.length));
    expectFirstWave(game);
    final ys = {for (final enemy in enemiesOf(game)) enemy.y};
    expect(ys, hasLength(waves.length));
    // Its robots swing as if they'd been falling, so not all are upright.
    final robots = enemiesOf(game).where((enemy) => enemy.kind.swings);
    expect(robots.where((robot) => robot.angle.abs() > 0.01), isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the waves come 5 every 1/15 s, 75 a second, the robots '
      'falling at 135 a second, the others flying at their speeds', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    game.enemyGroup.removeAll(enemiesOf(game).toList());
    await tester.pump();
    expect(enemiesOf(game), isEmpty);
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
    expect(enemiesOf(game).length, inInclusiveRange(70, 80));
    final enemies = enemiesOf(game).toList();
    final positions = [for (final enemy in enemies) enemy.position.clone()];
    await tester.pump(const Duration(milliseconds: 100));
    for (final (i, enemy) in enemies.indexed) {
      final moved = enemy.position - positions[i];
      if (enemy.kind.swings) {
        expect(moved.x, 0);
        expect(moved.y, closeTo(13.5, 1e-3));
      } else {
        expect(moved.distanceTo(enemy.velocity * 0.1), lessThan(1e-3));
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the enemies come in whole, across the whole width', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final creator = game.world.children.whereType<EnemyCreator>().single;
    for (var i = 0; i < 10; i++) {
      creator.createFirstWave();
    }
    // Mount them, before they move.
    await tester.pump();
    final half = EnemyComponent.initialSize.x / 2;
    final xs = [for (final enemy in enemiesOf(game)) enemy.x];
    expect(xs, hasLength(greaterThan(500)));
    for (final x in xs) {
      expect(x, inInclusiveRange(half, game.size.x - half));
    }
    expect(xs.reduce(math.min), lessThan(half + 10));
    expect(xs.reduce(math.max), greaterThan(game.size.x - half - 10));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a robot swings as a pendulum, 5° to 15° either way, 2 s a '
      'swing, while it falls straight down', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final robot = EnemyComponent(
      game.enemyKinds.firstWhere((kind) => kind.swings),
      position: Vector2(100, 0),
    );
    game.enemyGroup.add(robot);
    await tester.pump();
    final x = robot.x;
    final y = robot.y;
    final angles = <double>[];
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      angles.add(robot.angle);
    }
    final most = angles.reduce(math.max);
    final degrees = most * 180 / math.pi;
    expect(degrees, inInclusiveRange(4.99, 15.01));
    expect(degrees, closeTo(degrees.roundToDouble(), 0.01));
    expect(angles.reduce(math.min), closeTo(-most, 1e-3));
    // It reaches one side a quarter of a swing in, the other side three
    // quarters in, and is upright again at the end.
    expect(angles.indexOf(most), inInclusiveRange(48, 50));
    expect(angles.indexOf(angles.reduce(math.min)), inInclusiveRange(148, 150));
    expect(angles.last, closeTo(0, 0.01));
    expect(robot.x, x);
    expect(robot.y, closeTo(y + 135 * 2, 135 * 0.011));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a drag moves the player as far as the finger, at any zoom, '
      'and fires missiles while it lasts', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, zoom: 2);
    stopWaves(game);
    await tester.pump(const Duration(milliseconds: 16));
    final player = game.player;
    final start = player.position.clone();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byWidgetPredicate((w) => w is GameWidget)),
    );
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    expect(player.position, start + Vector2(20, 10));

    // A volley of 3 missiles comes at once. Each is in the same ratio to the
    // player's width as Rogue Shooter's bullets, 20 high, to its player, 75
    // wide.
    for (var i = 0; i < 3 && missilesOf(game).isEmpty; i++) {
      await tester.pump();
    }
    final missiles = missilesOf(game).toList();
    expect([
      for (final missile in missiles) missile.angle,
    ], unorderedEquals([0.3, 0.0, -0.3]));
    for (final missile in missiles) {
      expect(missile.size.x, closeTo(64 * 20 / 75, 1e-5));
      expect(missile.size.y, missile.size.x);
      expect(missile.children.whereType<SvgHitbox>(), hasLength(1));
    }

    // Once the drag ends, they fly off the game, and no more come.
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(missilesOf(game), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the player is in its SVG's orange, and its missiles in a "
      'lighter one, neither tinted', (tester) async {
    // These are the files' only colours, wherever the files set them.
    final player = File('assets/svgs/spaceship_game.svg')
        .readAsStringSync(encoding: latin1);
    expect(player, contains('stroke="#F09050"'));
    expect(player, isNot(contains('#FFFFFF')));
    final missile = File('assets/svgs/wireframe/missile.svg')
        .readAsStringSync();
    expect(missile, contains('fill="#F5B58A"'));
    expect(missile, contains('.st0{fill:#F5B58A;}'));
    expect(missile, isNot(contains('#FFFFFF')));
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    game.player.beginFire();
    await tester.pump(const Duration(milliseconds: 16));
    game.player.stopFire();
    expect(missilesOf(game), hasLength(3));
    for (final component in [game.player, ...missilesOf(game)]) {
      expect(svgPaintOf(component).colorFilter, isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the player fires a volley at once, then one every 0.15 s, '
      "and taps don't fire faster", (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final player = game.player;
    // Counts the volleys so far, 3 missiles each, from every missile seen
    // after each frame, before it flies off. A last pump with no time mounts
    // the last frame's missiles.
    final seen = <MissileComponent>{};
    Future<int> volleysAfter(int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.addAll(missilesOf(game));
      }
      await tester.pump();
      seen.addAll(missilesOf(game));
      return seen.length ~/ 3;
    }

    player.beginFire();
    expect(await volleysAfter(1), 1);
    // None more at 0.144 s, then one at 0.16 s, the first frame past 0.15 s.
    expect(await volleysAfter(8), 1);
    expect(await volleysAfter(1), 2);
    // The volleys are 75 apart, as missiles fly 500 a second, give or take
    // the 8 they fly in a frame.
    final straight = [
      for (final missile in missilesOf(game))
        if (missile.angle == 0) missile.y,
    ]..sort();
    expect(straight[1] - straight[0], closeTo(75, 8.1));
    // The third comes at 0.304 s. Firing stops at 0.32 s, and taps follow at
    // 0.336 s. They fire nothing at once: the next volley comes a period
    // after the last, at 0.464 s.
    expect(await volleysAfter(10), 3);
    player.stopFire();
    expect(await volleysAfter(1), 3);
    player
      ..beginFire()
      ..stopFire()
      ..beginFire();
    expect(await volleysAfter(7), 3);
    expect(await volleysAfter(1), 4);
    // After a stop of a whole period, a volley comes at once again.
    player.stopFire();
    expect(await volleysAfter(10), 4);
    player.beginFire();
    expect(await volleysAfter(1), 5);
    player.stopFire();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tilted enemy is removed once it has flown out of a side', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    // On the left and right sides, alternately.
    final ships = [
      for (var i = 0; i < 40; i++)
        EnemyComponent(
          game.enemyKinds.first,
          position: Vector2(i.isEven ? 0 : game.size.x, 100),
        ),
    ];
    game.enemyGroup.addAll(ships);
    // About 1 s. A ship that moves out sideways faster than about 20.5 a
    // second is then out by more than half its diagonal, about 20.5.
    await pumpFrames(tester, 63);
    var removed = 0;
    var kept = 0;
    for (final (i, ship) in ships.indexed) {
      final outward = i.isEven ? -ship.velocity.x : ship.velocity.x;
      if (outward > 23) {
        expect(ship.isRemoved, isTrue);
        removed++;
      } else if (outward < 18) {
        expect(ship.isRemoved, isFalse);
        kept++;
      }
    }
    expect(removed, greaterThan(0));
    expect(kept, greaterThan(removed));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a missile that hits an enemy removes both, scores, and '
      'explodes once', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final enemy = EnemyComponent(
      game.enemyKinds.first,
      position: Vector2(100, 100),
    );
    final missile = MissileComponent(
      game.missileSvg,
      position: Vector2(100, 150),
    );
    game.enemyGroup.add(enemy);
    game.missileGroup.add(missile);
    for (var i = 0; i < 10 && !enemy.isRemoved; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(enemy.isRemoved, isTrue);
    expect(missile.isRemoved, isTrue);
    expect(game.score, 1);
    await tester.pump(const Duration(milliseconds: 16));
    final explosion = game.explosionGroup.children
        .whereType<ExplosionComponent>()
        .single;
    expect(explosion.kind, ExplosionKind.missileHit);
    expect(explosion.position, enemy.position);
    expect(
      explosion.children.whereType<ParticleEmitterComponent>(),
      hasLength(2),
    );

    // Its longest-lived debris lasts 1.4 s.
    for (var i = 0; i < 100 && !explosion.isRemoved; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(explosion.isRemoved, isTrue);
    expect(game.explosionGroup.children, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a missile that hits two enemies in the same frame removes '
      'only one', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final enemies = [
      for (final x in [95.0, 105.0])
        EnemyComponent(game.enemyKinds.first, position: Vector2(x, 100)),
    ];
    final missile = MissileComponent(
      game.missileSvg,
      position: Vector2(100, 150),
    );
    game.enemyGroup.addAll(enemies);
    game.missileGroup.add(missile);
    for (var i = 0; i < 10 && !missile.isRemoved; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(missile.isRemoved, isTrue);
    expect(enemies.where((enemy) => enemy.isRemoved), hasLength(1));
    expect(game.score, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an enemy that hits the player takes 2% of its health, '
      "doesn't score, and explodes in red", (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final player = game.player;
    // It falls onto the player, as the waves' enemies do.
    final enemy = EnemyComponent(
      game.enemyKinds.first,
      position: player.position - Vector2(0, 60),
    );
    game.enemyGroup.add(enemy);
    for (var i = 0; i < 60 && !enemy.isRemoved; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(enemy.isRemoved, isTrue);
    expect(player.health, 98);
    expect(game.score, 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(healthTextOf(game), 'Health: 98%');
    final explosion = game.explosionGroup.children
        .whereType<ExplosionComponent>()
        .single;
    expect(explosion.kind, ExplosionKind.playerHit);
    expect(explosion.position, enemy.position);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an enemy that a missile and the player hit in the same frame '
      'explodes and scores once', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final enemy = EnemyComponent(
      game.enemyKinds.first,
      position: Vector2(100, 100),
    );
    game.enemyGroup.add(enemy);
    await tester.pump(const Duration(milliseconds: 16));
    enemy.takeHit();
    expect(enemy.hitPlayer(), isFalse);
    enemy.takeHit();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.score, 1);
    expect(game.player.health, 100);
    expect(
      game.explosionGroup.children.whereType<ExplosionComponent>().single.kind,
      ExplosionKind.missileHit,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the health comes back after 3 s without a hit, 2% a second, '
      'up to 100%', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final player = game.player;
    for (var i = 0; i < 3; i++) {
      player.takeHit();
    }
    expect(player.health, 94);
    await tester.pump(const Duration(seconds: 3));
    expect(player.health, 94);
    await tester.pump(const Duration(seconds: 1));
    expect(player.health, 96);

    // A hit starts the delay again.
    player.takeHit();
    await tester.pump(const Duration(seconds: 2));
    expect(player.health, 94);
    await tester.pump(const Duration(seconds: 10));
    expect(player.health, 100);
    await tester.pump(const Duration(milliseconds: 16));
    expect(healthTextOf(game), 'Health: 100%');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('at 0% health, the player blows up in red, turns red and '
      'fades out over 2 s of the world, neither moving, firing nor hit, and '
      'then the game is over', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final player = game.player;
    final ship = player.children.whereType<RasterizerSvgComponent>().single;
    final drag = await tester.startGesture(
      tester.getCenter(find.byWidgetPredicate((w) => w is GameWidget)),
    );
    await drag.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(player.missileCreator.timer.isRunning(), isTrue);
    // At 2% a hit, 50 hits take all its health: allow twice as many.
    for (var i = 0; i < 100 && player.health > 0; i++) {
      player.takeHit();
    }
    expect(player.isDestroyed, isTrue);
    expect(game.isGameOver, isFalse);
    expect(player.missileCreator.timer.isRunning(), isFalse);
    expect(
      player.children.whereType<SvgHitbox>().single.collisionType,
      CollisionType.inactive,
    );
    await tester.pump(const Duration(milliseconds: 16));
    // The explosion is twice the player's width, as an enemy's explosion is
    // twice the enemy's width.
    final explosion = game.explosionGroup.children
        .whereType<ExplosionComponent>()
        .single;
    expect(explosion.kind, ExplosionKind.playerDestroyed);
    expect(explosion.position, player.position);
    expect(ExplosionComponent.acrossOf(ExplosionKind.playerDestroyed), 128);
    expect(ExplosionComponent.acrossOf(ExplosionKind.playerHit), 58);
    expect(ExplosionComponent.acrossOf(ExplosionKind.missileHit), 58);

    // Once the volley that the drag fired is gone, neither drags nor keys
    // move it or fire, and enemies go through it.
    game.missileGroup.removeAll(missilesOf(game).toList());
    final position = player.position.clone();
    await drag.moveBy(const Offset(40, 20));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final enemy = EnemyComponent(
      game.enemyKinds.first,
      position: player.position - Vector2(0, 30),
    );
    game.enemyGroup.add(enemy);
    // Up to 1 s after the last hit.
    await pumpFrames(tester, 61);
    expect(player.position, position);
    expect(player.missileCreator.timer.isRunning(), isFalse);
    expect(enemy.isRemoved, isFalse);
    expect(enemy.y, greaterThan(player.y + 30));
    expect(player.health, 0);
    // It's red already, and half faded out.
    expect(ship.paint.colorFilter, isNotNull);
    expect(ship.opacity, closeTo(0.5, 0.02));
    expect(game.isGameOver, isFalse);

    // The fade runs in the world's time, so it stands still at a speed of 0.
    game.speed = 0;
    await tester.pump(const Duration(seconds: 3));
    expect(game.isGameOver, isFalse);
    expect(ship.opacity, closeTo(0.5, 0.02));
    game.speed = 1;
    await pumpFrames(tester, 70);
    expect(game.isGameOver, isTrue);
    expect(ship.opacity, 0);
    expect(
      game.camera.viewport.children.whereType<GameOverText>(),
      hasLength(1),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await drag.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('once the player has faded out, the game is over: the world '
      'stops, at any speed, drags neither move nor fire, and a tap starts a '
      'new game', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    await pumpFrames(tester, 20);
    final player = game.player;
    final ship = player.children.whereType<RasterizerSvgComponent>().single;
    final center = tester.getCenter(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    // A drag that starts before the game is over, and fires.
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(20, 0));
    await pumpFrames(tester, 5);
    expect(player.missileCreator.timer.isRunning(), isTrue);
    // At 2% a hit, 50 hits take all its health: allow twice as many.
    for (var i = 0; i < 100 && player.health > 0; i++) {
      player.takeHit();
    }
    for (var i = 0; i < 200 && !game.isGameOver; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.isGameOver, isTrue);
    expect(player.health, 0);
    expect(player.missileCreator.timer.isRunning(), isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    final gameOver = game.camera.viewport.children
        .whereType<GameOverText>()
        .single;
    expect(gameOver.text, 'Game Over');
    expect(gameOver.position, game.size / 2);
    expect(healthTextOf(game), 'Health: 0%');

    // Nothing moves at any speed, and nothing follows the drag.
    List<Vector2> positions() => [
      for (final component in <PositionComponent>[
        player,
        ...enemiesOf(game),
        ...missilesOf(game),
        ...game.starGroup.children.whereType<StarComponent>(),
      ])
        component.position.clone(),
    ];
    final still = positions();
    expect(enemiesOf(game), isNotEmpty);
    game.speed = 1.5;
    expect(game.speed, 1.5);
    await drag.moveBy(const Offset(40, 20));
    await tester.pump(const Duration(seconds: 1));
    expect(positions(), still);
    // The drag doesn't start a new game as it goes up: it went down before
    // the game was over.
    await drag.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.isGameOver, isTrue);

    // A tap starts a new game at the Speed knob's speed, with the player
    // whole again and a first wave in the top 20%.
    await tester.tapAt(center);
    expect(game.isGameOver, isFalse);
    await tester.pump();
    expect(game.world.timeScale, 1.5);
    expect(game.camera.viewport.children.whereType<GameOverText>(), isEmpty);
    expect(game.score, 0);
    expect(player.health, 100);
    expect(player.position, game.size / 2);
    expect(player.isDestroyed, isFalse);
    expect(ship.opacity, 1);
    expect(ship.paint.colorFilter, isNull);
    expect(
      player.children.whereType<SvgHitbox>().single.collisionType,
      CollisionType.active,
    );
    expect(missilesOf(game), isEmpty);
    expect(game.explosionGroup.children, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expectFirstWave(game, seconds: 0.016 * 1.5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a drag held through Game Over fires again in the new game', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    await pumpFrames(tester, 20);
    final player = game.player;
    final center = tester.getCenter(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(20, 0));
    await pumpFrames(tester, 5);
    // At 2% a hit, 50 hits take all its health: allow twice as many.
    for (var i = 0; i < 100 && player.health > 0; i++) {
      player.takeHit();
    }
    for (var i = 0; i < 200 && !game.isGameOver; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.isGameOver, isTrue);
    expect(player.missileCreator.timer.isRunning(), isFalse);
    // Another finger's tap starts a new game while the drag is still down.
    await tester.tapAt(center + const Offset(0, 40), pointer: 2);
    expect(game.isGameOver, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    expect(player.missileCreator.timer.isRunning(), isTrue);
    await drag.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the arrow keys and WASD move the player at 400 a second, '
      'within the play area, the space bar fires while held, and a click '
      'on the game takes the keys back', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    stopWaves(game);
    final player = game.player;
    final timer = player.missileCreator.timer;
    expect(PlayerComponent.keySpeed, 400);

    /// Holds [keys] for [seconds], in one frame, then releases them.
    Future<void> hold(List<LogicalKeyboardKey> keys, double seconds) async {
      for (final key in keys) {
        await tester.sendKeyDownEvent(key);
      }
      await tester.pump(Duration(microseconds: (seconds * 1e6).round()));
      for (final key in keys) {
        await tester.sendKeyUpEvent(key);
      }
      await tester.pump();
    }

    void expectAt(double x, double y) {
      expect(player.x, closeTo(x, 1e-3));
      expect(player.y, closeTo(y, 1e-3));
    }

    final start = player.position.clone();
    await hold([LogicalKeyboardKey.arrowRight], 0.25);
    expectAt(start.x + 100, start.y);
    await hold([LogicalKeyboardKey.arrowUp], 0.25);
    expectAt(start.x + 100, start.y - 100);
    await hold([LogicalKeyboardKey.keyA], 0.25);
    expectAt(start.x, start.y - 100);
    await hold([LogicalKeyboardKey.keyS], 0.25);
    expectAt(start.x, start.y);
    // It's as fast diagonally, and an arrow with its letter counts as one
    // key.
    await hold([LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyW], 0.25);
    const diagonal = 100 / math.sqrt2;
    expectAt(start.x + diagonal, start.y - diagonal);
    await hold([LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft], 0.25);
    expectAt(start.x + diagonal - 100, start.y - diagonal);
    // It stops at the play area's edges.
    await hold([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp], 5);
    expectAt(32, 21);
    // Out of the play area, where a drag can take it, the keys only move it
    // back toward the play area.
    player.x = game.size.x + 50;
    await hold([LogicalKeyboardKey.arrowRight], 0.25);
    expectAt(game.size.x + 50, 21);
    await hold([LogicalKeyboardKey.arrowLeft], 0.25);
    expectAt(game.size.x - 50, 21);

    // The space bar fires while held, as a drag does. While either lasts,
    // releasing the other doesn't stop the fire.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(timer.isRunning(), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(timer.isRunning(), isFalse);
    final center = tester.getCenter(
      find.byWidgetPredicate((w) => w is GameWidget),
    );
    final drag = await tester.startGesture(center);
    await drag.moveBy(const Offset(1, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(timer.isRunning(), isTrue);
    await drag.up();
    expect(timer.isRunning(), isFalse);

    // A key released after another widget took the focus stops counting as
    // held.
    await tester.pump();
    final x = player.x;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 16));
    final left = player.x;
    expect(left, lessThan(x));
    await tester.pump(const Duration(milliseconds: 250));
    expect(player.x, left);
    // Keys don't reach the game until a click on it.
    await hold([LogicalKeyboardKey.arrowLeft], 0.25);
    expect(player.x, left);
    await tester.tapAt(center);
    await tester.pump();
    await hold([LogicalKeyboardKey.arrowLeft], 0.25);
    expect(player.x, closeTo(left - 100, 1e-3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the space bar, held while the game loads, fires once it has', (
    tester,
  ) async {
    Flame.bundle = SlowBundle();
    addTearDown(() => Flame.bundle = rootBundle);
    await tester.pumpWidget(story(SvgRenderer.rasterizer));
    final game = tester
        .widget<GameWidget<SvgShooterExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    expect(game.isLoaded, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    // The slow bundle's assets load in the test's fake time, and the stars'
    // image in real time.
    for (var i = 0; i < 100 && game.missileGroup.children.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(game.player.missileCreator.timer.isRunning(), isTrue);
    expect(missilesOf(game), isNotEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(game.player.missileCreator.timer.isRunning(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the stars fall, pale yellow, of sizes at random, and a new row '
      'comes at the top', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    Iterable<StarComponent> stars() =>
        game.starGroup.children.whereType<StarComponent>();
    expect(
      stars(),
      hasLength(StarBackgroundCreator.rows * StarBackgroundCreator.starsInRow),
    );
    for (final star in stars()) {
      expect(star.size.x, star.size.y);
      expect(star.size.x, inInclusiveRange(3, 15));
    }
    expect({for (final star in stars()) star.size.x}.length, greaterThan(1));
    // Their image's center is pale yellow.
    final image = stars().first.sprite!.image;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
    ))!;
    final center = 4 * (image.width * (image.height ~/ 2) + image.width ~/ 2);
    final rgb = [for (var i = 0; i < 3; i++) bytes.getUint8(center + i)];
    for (final (i, channel) in [0xFD, 0xE6, 0x8A].indexed) {
      expect(rgb[i], closeTo(channel, 3));
    }

    // Wait past the time the stars take to fall by a row's gap.
    final top = stars().reduce((a, b) => a.y < b.y ? a : b);
    final y = top.y;
    expect(y, lessThan(20));
    final gapTime =
        game.size.y / StarBackgroundCreator.rows / StarComponent.speed;
    expect(gapTime, lessThan(5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));
    expect(StarComponent.speed, 15);
    expect(top.y, closeTo(y + 15 * 5.016, 1e-3));
    expect(
      stars().where((star) => star.y < 20),
      hasLength(StarBackgroundCreator.starsInRow),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
