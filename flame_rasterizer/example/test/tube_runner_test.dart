// Checks the Tube Runner prototype headlessly, with flame_rasterizer's canvas
// renderer and with Flame's PathComponent: the endless tube's rings, that the
// ship flies and moves round the tube, and that its shots hit.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_field_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

void main() {
  test('the rings stay square to the axis on a long flight', () {
    final tube = EndlessTube();
    for (var distance = 0.0; distance < 20000; distance += 0.37) {
      tube.advanceTo(distance);
    }
    final ring = tube.ringAt(20000);
    expect(ring.forward.dot(EndlessTube.forwardAt(20000)), closeTo(1, 1e-9));
    expect(ring.right.dot(ring.right), closeTo(1, 1e-9));
    expect(ring.right.dot(ring.forward), closeTo(0, 1e-9));
    expect(ring.down.dot(ring.right), closeTo(0, 1e-9));
  });

  test('a shape that flips turns round the corner onto the next lane', () {
    final tube = Tubes.hexagon;
    final view = TubeView()
      ..tube = tube
      ..fit(720, 1);
    final from = tube.bottomLane;
    final to = tube.neighbour(from, 1)!;
    final angle = tube.flipAngle(from, to);
    const at = 3.0;
    final places = (EndlessTube()..advanceTo(0))
        .quadsAt(
          0,
          view,
          marks: [
            (lane: from, at: at, flip: null, across: null),
            (lane: from, at: at, flip: (to: to, turn: 0), across: null),
            (lane: from, at: at, flip: (to: to, turn: angle), across: null),
            (lane: to, at: at, flip: null, across: null),
          ],
        )
        .places;
    expect(places, everyElement(isNotNull));
    final [still!, starting!, flipped!, landed!] = places;
    expect(starting.position, still.position);
    expect(starting.angle, still.angle);
    expect((flipped.position - landed.position).distance, lessThan(1e-6));
    expect(flipped.angle, closeTo(still.angle + angle, 1e-9));
  });

  for (final tube in [Tubes.floor, Tubes.ridge, Tubes.horseshoe]) {
    test("an open tube's nearer lanes hide what's beyond them: "
        '${tube.name}', () {
      final view = TubeView()
        ..tube = tube
        ..fit(720, 1);
      final endless = EndlessTube();
      const step = EndlessTube.step;
      var marks = 0;
      var hidden = 0;
      var wrong = 0;
      for (var distance = 0.0; distance < 2400; distance += 60) {
        endless.advanceTo(distance);
        final ship = endless.ringAt(distance);
        final eye = ship.center - ship.forward * Tube.eye;
        final first = ((distance - EndlessTube.behind) / step).floor();
        final last = ((distance + EndlessTube.ahead) / step).ceil();
        final rings = {
          for (var k = first; k <= last; k++)
            k: [
              for (final point in tube.points)
                endless.ringAt(k * step).place(point),
            ],
        };
        // A mark at the middle of each face ahead of the ship.
        final faces = [
          for (var k = (distance / step).floor() + 1; k < last; k++)
            for (var lane = 0; lane < tube.laneCount; lane++)
              (k: k, lane: lane, at: (k + 0.5) * step),
        ];
        final places = endless
            .quadsAt(
              distance,
              view,
              marks: [
                for (final face in faces)
                  (lane: face.lane, at: face.at, flip: null, across: null),
              ],
            )
            .places;
        for (final (i, face) in faces.indexed) {
          final point = endless.ringAt(face.at).place(tube.middles[face.lane]);
          var behind = false;
          for (var k = first; k < last && !behind; k++) {
            for (var lane = 0; lane < tube.laneCount && !behind; lane++) {
              if (k == face.k && lane == face.lane) {
                continue;
              }
              final after = tube.pointAfter(lane);
              behind = _hides(eye, point, [
                rings[k]![lane],
                rings[k]![after],
                rings[k + 1]![after],
                rings[k + 1]![lane],
              ]);
            }
          }
          marks++;
          if (behind) {
            hidden++;
          }
          if (behind != (places[i] == null)) {
            wrong++;
          }
        }
      }
      // Without hiding, 15% of the Floor's marks, 23% of the Ridge's and
      // 40% of the Horseshoe's would show through.
      expect(hidden / marks, greaterThan(0.1));
      expect(wrong / marks, lessThan(0.015));
    });
  }

  for (final renderer in [SvgRenderer.rasterizerCanvas, SvgRenderer.flameSvg]) {
    testWidgets('the ship flies and moves with ${renderer.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) =>
                TubeRunnerExample.of(renderer, status, random: math.Random(1)),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      final lane = game.runner.ship.lane;
      // A key starts the game at READY.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(game.runner.state, RunnerState.play);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        game.runner.flown,
        closeTo(61 * 0.016 * TubeHost.defaultFlightSpeed, 0.05),
      );
      expect(game.runner.ship.lane, isNot(lane));
      expect(game.exampleStats.first, isNot('0 quads'));
    });

    testWidgets('a shot destroys a seeder, and cuts its spike back, with '
        '${renderer.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) =>
                TubeRunnerExample.of(renderer, status, random: math.Random(1)),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 400 && game.runner.seeders.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final seeder = game.runner.seeders.single;
      game.runner.ship.moveBy(
        (seeder.spike.lane - game.runner.ship.lane).toDouble(),
      );
      expect(game.runner.ship.lane, seeder.spike.lane);
      // Fires until the seeder is gone, and then at its spike.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 300 && game.score <= EnemyKind.seeder.score; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.runner.seeders, isNot(contains(seeder)));
      expect(
        game.score,
        EnemyKind.seeder.score + ShooterMode.spikeScore,
      );
      expect(game.runner.state, RunnerState.play);
    });

    testWidgets('a shot destroys a climber, with ${renderer.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) =>
                TubeRunnerExample.of(renderer, status, random: math.Random(1)),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      game.runner.addEnemy(EnemyKind.climber, game.runner.ship.lane);
      final climber = game.runner.enemies.single;
      // Fires, following the climber as it flips, until it's gone, before
      // the first seeder comes.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 1000 && game.score < EnemyKind.climber.score; i++) {
        game.runner.ship.moveBy(
          (climber.currentLane - game.runner.ship.lane).toDouble(),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.runner.enemies, isNot(contains(climber)));
      expect(game.score, EnemyKind.climber.score);
      expect(game.runner.state, RunnerState.play);
    });

    testWidgets("a zapper's bolt destroys the ship in its lane, with "
        '${renderer.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) =>
                TubeRunnerExample.of(renderer, status, random: math.Random(1)),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      final lane = game.tube.neighbour(game.runner.ship.lane, 2)!;
      game.runner.addEnemy(EnemyKind.zapper, lane);
      // The first pulse, 2.4 seconds in, before the zapper's first flip, at
      // 3 seconds or later, leaves the ship in another lane alone.
      for (var i = 0; i < 300 && !game.runner.isPulsing; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.runner.isPulsing, isTrue);
      expect(game.runner.state, RunnerState.play);
      game.runner.ship.moveBy(2);
      expect(game.runner.ship.lane, lane);
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.runner.state, RunnerState.dying);
      expect(game.lives, TubeHost.startLives - 1);
    });

    testWidgets('a splitter splits near the ship, or when shot, with '
        '${renderer.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) =>
                TubeRunnerExample.of(renderer, status, random: math.Random(1)),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      // Unshot, two lanes from the ship, it splits 4 units ahead of it, into
      // climbers that flip onto the lanes on either side.
      final lane = game.tube.neighbour(game.runner.ship.lane, 2)!;
      game.runner.addEnemy(EnemyKind.splitter, lane);
      bool splitting() =>
          game.runner.enemies.whereType<RunnerSplitterComponent>().isNotEmpty;
      for (var i = 0; i < 1000 && splitting(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final climbers = game.runner.enemies.whereType<RunnerClimberComponent>();
      expect(climbers, hasLength(2));
      expect(climbers.map((climber) => climber.mark.flip?.to).toSet(), {
        game.tube.neighbour(lane, -1),
        game.tube.neighbour(lane, 1),
      });
      expect(
        climbers.first.at - game.runner.flown,
        closeTo(RunnerSplitterComponent.splitAhead, 0.1),
      );
      expect(game.score, 0);
      // Shot, it scores, and splits too.
      game.runner.addEnemy(EnemyKind.splitter, game.runner.ship.lane);
      final splitter = game.runner.enemies.last;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 1000 && game.score < EnemyKind.splitter.score; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.runner.enemies, isNot(contains(splitter)));
      expect(game.score, greaterThanOrEqualTo(EnemyKind.splitter.score));
      expect(game.runner.state, RunnerState.play);
    });

    testWidgets('round an open tube, the ship stops at its ends, and a '
        'splitter at an end splits into a climber that stays, with '
        '${renderer.name}', (tester) async {
      final tube = Tubes.floor;
      await tester.pumpWidget(
        MaterialApp(
          home: GameStory<TubeRunnerExample, Object>(
            renderer: renderer,
            create: (status, _) => TubeRunnerExample.of(
              renderer,
              status,
              random: math.Random(1),
              tube: tube,
            ),
          ),
        ),
      );
      final game = tester
          .widget<GameWidget<TubeRunnerExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !game.isLoaded);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      game.runner.ship.moveBy(-2.0 * tube.laneCount);
      expect(game.runner.ship.lane, 0);
      game.runner.ship.moveBy(2.0 * tube.laneCount);
      expect(game.runner.ship.lane, tube.laneCount - 1);
      game.runner.addEnemy(EnemyKind.splitter, 0);
      bool splitting() =>
          game.runner.enemies.whereType<RunnerSplitterComponent>().isNotEmpty;
      for (var i = 0; i < 1000 && splitting(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final climbers = game.runner.enemies.whereType<RunnerClimberComponent>();
      expect(climbers, hasLength(2));
      expect(climbers.map((climber) => climber.mark.flip?.to).toSet(), {
        null,
        1,
      });
      expect(climbers.map((climber) => climber.lane), everyElement(0));
      expect(game.runner.state, RunnerState.play);
    });
  }

  _snapshotTests();
  _starsTests();
}

/// Returns whether the quad of [corners] hides [point] from [eye]: whether
/// one of its two triangles crosses the line of sight between them, by the
/// Möller-Trumbore algorithm.
bool _hides(Point3 eye, Point3 point, List<Point3> corners) {
  final sight = point - eye;
  for (final [a, b, c] in [
    [corners[0], corners[1], corners[2]],
    [corners[0], corners[2], corners[3]],
  ]) {
    final ab = b - a;
    final ac = c - a;
    final p = sight.cross(ac);
    final determinant = ab.dot(p);
    if (determinant.abs() < 1e-12) {
      continue;
    }
    final fromA = eye - a;
    final u = fromA.dot(p) / determinant;
    final q = fromA.cross(ab);
    final v = sight.dot(q) / determinant;
    final t = ac.dot(q) / determinant;
    // Short of the point, which lies on a face itself.
    if (u >= 0 && v >= 0 && u + v <= 1 && t > 1e-6 && t < 1 - 1e-3) {
      return true;
    }
  }
  return false;
}

/// The story of a Tube Runner game for [renderer], at [speed], that goes on
/// from the snapshot of the game before.
Widget _story(SvgRenderer renderer, {double speed = 1}) => MaterialApp(
  home: GameStory<TubeRunnerExample, TubeRunnerSnapshot>(
    renderer: renderer,
    create: (status, from) => TubeRunnerExample.of(
      renderer,
      status,
      random: math.Random(1),
      from: from,
    ),
    snapshot: (game) => game.snapshot,
    speed: speed,
  ),
);

/// Returns the story's game, once loaded.
Future<TubeRunnerExample> _gameOf(WidgetTester tester) async {
  final game = tester
      .widget<GameWidget<TubeRunnerExample>>(
        find.byWidgetPredicate((w) => w is GameWidget),
      )
      .game!;
  await pumpWhileLoading(tester, () => !game.isLoaded);
  return game;
}

/// Checks that the Stars knob changes how many stars there are.
void _starsTests() {
  testWidgets('the Stars knob changes how many stars there are in the '
      'running game, even in a still world', (tester) async {
    await tester.pumpWidget(_story(SvgRenderer.rasterizerCanvas));
    final game = await _gameOf(tester);
    final field = game.runner.stars;
    expect(field.stars, hasLength(TubeHost.defaultStarCount));
    expect(field.children, hasLength(TubeHost.defaultStarCount));
    // The last ones go.
    final first = field.stars.first;
    game.starCount = 20;
    // Flame adds and removes the children in the frames after, once what
    // loads before them has.
    await pumpWhileLoading(
      tester,
      () => field.children.length != game.starCount,
    );
    expect(field.stars, hasLength(20));
    expect(field.stars.first, same(first));
    expect(field.children, hasLength(20));
    game.starCount = 0;
    await pumpWhileLoading(
      tester,
      () => field.children.length != game.starCount,
    );
    expect(field.stars, isEmpty);
    expect(field.children, isEmpty);
    // In a still world, new ones come at once, at random distances.
    game.world.timeScale = 0;
    game.starCount = 1000;
    await pumpWhileLoading(
      tester,
      () => field.children.length != game.starCount,
    );
    expect(field.stars, hasLength(1000));
    expect(field.children, hasLength(1000));
    final distances = field.stars.map((star) => star.eyeDistance).toSet();
    expect(distances.length, greaterThan(900));
    expect(
      distances,
      everyElement(inInclusiveRange(TubeView.near, StarFieldComponent.far)),
    );
    await tester.pumpWidget(const SizedBox());
  });
}

/// Checks that a new renderer's game goes on from the old one's.
void _snapshotTests() {
  testWidgets('a new renderer goes on from the same distance, score, lives, '
      'ship, enemies, spikes and shots, where they show, and from Game Over', (
    tester,
  ) async {
    await tester.pumpWidget(_story(SvgRenderer.rasterizerCanvas));
    final game = await _gameOf(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    final runner = game.runner;
    final lane = runner.ship.lane;
    final laneCount = game.view.tube.laneCount;
    for (final (i, kind) in [
      EnemyKind.seeder,
      EnemyKind.climber,
      EnemyKind.zapper,
      EnemyKind.splitter,
    ].indexed) {
      runner.addEnemy(kind, (lane + 1 + i) % laneCount);
    }
    // The ship fires down its lane as it flies, and the enemies climb.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game
      ..score = 1234
      ..lives = 2;
    await tester.pumpWidget(_story(SvgRenderer.rasterizerCanvas, speed: 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(runner.state, RunnerState.play);
    final snapshot = game.snapshot;
    expect(snapshot.runner.shots, isNotEmpty);
    expect(snapshot.runner.spikes, isNotEmpty);
    expect(snapshot.runner.enemies, isNotEmpty);
    // A hidden shape keeps where it last showed, so only the shown count.
    List<Offset?> placesOf(RunnerMode runner) => [
      for (final shape in <PositionComponent>[
        runner.ship,
        ...runner.enemies,
        ...runner.children.whereType<RunnerShotComponent>(),
      ])
        if ((shape as HasVisibility).isVisible)
          shape.position.toOffset()
        else
          null,
    ];
    final places = placesOf(runner);

    await tester.pumpWidget(_story(SvgRenderer.flameSvg, speed: 0));
    final next = await _gameOf(tester);
    expect(next, isNot(same(game)));
    await tester.pump(const Duration(milliseconds: 16));
    final again = next.snapshot;
    // Records compare their lists by identity, so the lists go apart.
    expect((again.score, again.lives), (1234, 2));
    expect(again.runner.spikes, snapshot.runner.spikes);
    expect(again.runner.enemies, snapshot.runner.enemies);
    expect(again.runner.shots, snapshot.runner.shots);
    expect(again.runner.ship, snapshot.runner.ship);
    expect(
      (again.runner.state, again.runner.flown, again.runner.tubeTime),
      (snapshot.runner.state, snapshot.runner.flown, snapshot.runner.tubeTime),
    );
    final placesAgain = placesOf(next.runner);
    expect(placesAgain, hasLength(places.length));
    expect(places.nonNulls, hasLength(greaterThan(1)));
    for (final (i, place) in placesAgain.indexed) {
      expect(place == null, places[i] == null);
      if (place != null) {
        expect((place - places[i]!).distance, lessThan(1e-9));
      }
    }

    // The game goes on, until a seeder down the ship's lane ends it.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpWidget(_story(SvgRenderer.flameSvg));
    next.lives = 1;
    next.runner.addEnemy(EnemyKind.seeder, next.runner.ship.lane);
    for (var i = 0; i < 1000 && !next.runner.isOver; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(next.runner.isOver, isTrue);

    await tester.pumpWidget(_story(SvgRenderer.rasterizerCanvas));
    final over = await _gameOf(tester);
    await tester.pump(const Duration(milliseconds: 16));
    expect(over.runner.isOver, isTrue);
    expect(over.world.timeScale, 0);
    expect(over.gameOverText.isMounted, isTrue);
    expect(over.runner.ship.isVisible, isFalse);
    // Enter starts a new game, at READY.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 16));
    expect(over.runner.isReady, isTrue);
    expect(over.lives, TubeHost.startLives);
    expect(over.world.timeScale, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
