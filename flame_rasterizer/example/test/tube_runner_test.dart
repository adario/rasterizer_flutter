// Checks the Tube Runner prototype headlessly, with flame_rasterizer's canvas
// renderer and with Flame's PathComponent: the endless tube's rings, that the
// ship flies and moves round the tube, and that its shots hit.
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
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
            (lane: from, at: at, flip: null),
            (lane: from, at: at, flip: (to: to, turn: 0)),
            (lane: from, at: at, flip: (to: to, turn: angle)),
            (lane: to, at: at, flip: null),
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
                  (lane: face.lane, at: face.at, flip: null),
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
      final lane = game.ship.lane;
      // A key starts the game at READY.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(game.state, RunnerState.play);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        game.flown,
        closeTo(61 * 0.016 * TubeRunnerExample.flightSpeed, 0.05),
      );
      expect(game.ship.lane, isNot(lane));
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
      for (var i = 0; i < 400 && game.seeders.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final seeder = game.seeders.single;
      game.ship.moveBy((seeder.spike.lane - game.ship.lane).toDouble());
      expect(game.ship.lane, seeder.spike.lane);
      // Fires until the seeder is gone, and then at its spike.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 300 && game.score <= EnemyKind.seeder.score; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.seeders, isNot(contains(seeder)));
      expect(
        game.score,
        EnemyKind.seeder.score + TubeShooterExample.spikeScore,
      );
      expect(game.state, RunnerState.play);
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
      game.addEnemy(EnemyKind.climber, game.ship.lane);
      final climber = game.enemies.single;
      // Fires, following the climber as it flips, until it's gone, before
      // the first seeder comes.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 300 && game.score < EnemyKind.climber.score; i++) {
        game.ship.moveBy((climber.currentLane - game.ship.lane).toDouble());
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.enemies, isNot(contains(climber)));
      expect(game.score, EnemyKind.climber.score);
      expect(game.state, RunnerState.play);
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
      final lane = game.tube.neighbour(game.ship.lane, 2)!;
      game.addEnemy(EnemyKind.zapper, lane);
      // The first pulse, 2.4 seconds in, before the zapper's first flip, at
      // 3 seconds or later, leaves the ship in another lane alone.
      for (var i = 0; i < 300 && !game.isPulsing; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isPulsing, isTrue);
      expect(game.state, RunnerState.play);
      game.ship.moveBy(2);
      expect(game.ship.lane, lane);
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.state, RunnerState.dying);
      expect(game.lives, TubeRunnerExample.startLives - 1);
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
      final lane = game.tube.neighbour(game.ship.lane, 2)!;
      game.addEnemy(EnemyKind.splitter, lane);
      bool splitting() =>
          game.enemies.whereType<RunnerSplitterComponent>().isNotEmpty;
      for (var i = 0; i < 300 && splitting(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final climbers = game.enemies.whereType<RunnerClimberComponent>();
      expect(climbers, hasLength(2));
      expect(climbers.map((climber) => climber.mark.flip?.to).toSet(), {
        game.tube.neighbour(lane, -1),
        game.tube.neighbour(lane, 1),
      });
      expect(
        climbers.first.at - game.flown,
        closeTo(RunnerSplitterComponent.splitAhead, 0.1),
      );
      expect(game.score, 0);
      // Shot, it scores, and splits too.
      game.addEnemy(EnemyKind.splitter, game.ship.lane);
      final splitter = game.enemies.last;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      for (var i = 0; i < 300 && game.score < EnemyKind.splitter.score; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(game.enemies, isNot(contains(splitter)));
      expect(game.score, greaterThanOrEqualTo(EnemyKind.splitter.score));
      expect(game.state, RunnerState.play);
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
      game.ship.moveBy(-2.0 * tube.laneCount);
      expect(game.ship.lane, 0);
      game.ship.moveBy(2.0 * tube.laneCount);
      expect(game.ship.lane, tube.laneCount - 1);
      game.addEnemy(EnemyKind.splitter, 0);
      bool splitting() =>
          game.enemies.whereType<RunnerSplitterComponent>().isNotEmpty;
      for (var i = 0; i < 300 && splitting(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final climbers = game.enemies.whereType<RunnerClimberComponent>();
      expect(climbers, hasLength(2));
      expect(climbers.map((climber) => climber.mark.flip?.to).toSet(), {
        null,
        1,
      });
      expect(climbers.map((climber) => climber.lane), everyElement(0));
      expect(game.state, RunnerState.play);
    });
  }
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
