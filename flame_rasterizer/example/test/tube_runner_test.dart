// Checks the Tube Runner prototype headlessly, with flame_rasterizer's canvas
// renderer and with Flame's PathComponent: the endless tube's rings, that the
// ship flies and moves round the tube, and that its shots hit.
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
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
  }
}
