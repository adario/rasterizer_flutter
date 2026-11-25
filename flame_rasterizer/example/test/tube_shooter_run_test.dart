// Checks Tube Shooter's runs into Tube Runner's tube: that the run's tube
// leads on from the round's and into the next round's, that a closed or an
// open tube's drop flies on down a run, onto the next round's rim, and that
// the run plays by Tube Runner's rules.
import 'dart:math' as math;

import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'tube_shooter_test.dart'
    show beginLevel, pumpFrames, pumpGame, pumpUntil;

void main() {
  const course = (bendFrom: Tube.depth, bendTo: 40.0, ease: 8.0);
  final hexagon = levels.indexWhere((level) => level.tube == Tubes.hexagon);

  test('a course goes straight before and after its bends', () {
    final tube = EndlessTube(course: course)..advanceTo(0);
    for (final distance in [0.0, 1.3, Tube.depth]) {
      final ring = tube.ringAt(distance);
      expect(ring.forward.z, 1);
      expect(ring.right.x, 1);
      expect(ring.down.y, 1);
    }
    Ring flyTo(double distance) {
      for (var at = 0.0; at < distance; at += 0.37) {
        tube.advanceTo(at);
      }
      tube.advanceTo(distance);
      return tube.ringAt(distance);
    }

    final end = flyTo(41);
    final later = flyTo(59);
    expect(end.forward.dot(later.forward), closeTo(1, 1e-12));
    expect(end.right.dot(later.right), closeTo(1, 1e-12));
  });

  test('a run draws nothing past the far end as the drop starts, '
      'and the next tube as the round draws it, at its rim', () {
    final view = TubeView()
      ..tube = Tubes.hexagon
      ..fit(720, 1);
    final start = (EndlessTube(course: course)..advanceTo(0)).quadsAt(
      0,
      view,
      from: Tube.depth,
      until: Tube.depth,
    );
    expect(start.tube.vertexCounts, isEmpty);
    const rim = 46.0;
    final tube = EndlessTube(course: course);
    for (var distance = 0.0; distance <= rim; distance += 0.5) {
      tube.advanceTo(distance);
    }
    final arrived = tube.quadsAt(
      rim,
      view,
      from: Tube.depth,
      until: 44,
      next: (tube: Tubes.floor, rim: rim),
    );
    expect(arrived.tube.vertexCounts, isEmpty);
    final shooter = TubeView()
      ..tube = Tubes.floor
      ..fit(720, 1);
    final expected = shooter.tubePath().getBounds();
    final drawn = arrived.next.bounds;
    for (final (a, b) in [
      (drawn.left, expected.left),
      (drawn.top, expected.top),
      (drawn.right, expected.right),
      (drawn.bottom, expected.bottom),
    ]) {
      expect(a, closeTo(b, 1e-9));
    }
  });

  for (final tube in [
    Tubes.hexagon,
    Tubes.floor,
    Tubes.ridge,
    Tubes.horseshoe,
  ]) {
    final first = levels.indexWhere((level) => level.tube == tube);
    final next = levels[first + 1].tube;
    testWidgets('with runs, the ${tube.name} drop flies on down a run, then '
        'onto the next rim, with no jump of the ship, the camera looking '
        "where the round's does, then where the next round's does", (
      tester,
    ) async {
      final game = await pumpGame(
        tester,
        SvgRenderer.rasterizerCanvas,
        firstLevel: first,
        runs: true,
      );
      game.shooter.spawning = false;
      await beginLevel(tester, game);
      game.score = 1234;
      game.shooter.clearSpawns();
      Offset aim() => game.camera.viewfinder.position.toOffset();
      final round = tube.center * game.view.rimScale;
      var last = game.shooter.player.position.toOffset();
      var most = 0.0;
      var mostOff = 0.0;
      final states = <TubeState>[];
      for (var i = 0; i < 2000 && game.shooter.state != TubeState.ready; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final position = game.shooter.player.position.toOffset();
        most = math.max(most, (position - last).distance);
        last = position;
        if (game.shooter.state == TubeState.run) {
          mostOff = math.max(mostOff, (aim() - round).distance);
        }
        if (states.isEmpty || states.last != game.shooter.state) {
          states.add(game.shooter.state);
        }
      }
      expect(states, [
        TubeState.drop,
        TubeState.run,
        TubeState.arrive,
        TubeState.ready,
      ]);
      // The viewfinder keeps its position in single precision.
      expect(mostOff, lessThan(1e-3));
      expect(
        (aim() - next.center * game.view.rimScale).distance,
        lessThan(1e-3),
      );
      // The ship glides onto the next tube's lanes, a little each frame.
      expect(most, lessThan(0.02 * game.view.rimScale));
      expect(game.shooter.level.tube, next);
      expect(game.shooter.round, 2);
      expect(game.score, 1234);
      expect(game.lives, TubeHost.startLives);
      expect(game.shooter.player.isVisible, isTrue);
      expect(game.shooter.player.depth, 0);
      expect(game.view.eyeShift, 0);
      await pumpFrames(tester, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }

  /// Pumps [game], on its first round, with its runs on, until its drop
  /// flies on down a run, and returns the run's runner.
  Future<RunnerMode> pumpToRun(
    WidgetTester tester,
    TubeShooterExample game,
  ) async {
    game.shooter.spawning = false;
    await beginLevel(tester, game);
    game.shooter.clearSpawns();
    await pumpUntil(
      tester,
      () => game.shooter.state == TubeState.run,
      frames: 400,
    );
    return game.shooter.runner!;
  }

  Future<void> pressKey(
    WidgetTester tester, [
    LogicalKeyboardKey key = LogicalKeyboardKey.keyX,
  ]) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
  }

  for (final tube in [Tubes.hexagon, Tubes.horseshoe]) {
    testWidgets("on the ${tube.name}'s run, Tube Runner's ship takes over "
        "where the round's was, the round brings seeders, and none comes from "
        "past the end of the run's play", (tester) async {
      final game = await pumpGame(
        tester,
        SvgRenderer.rasterizerCanvas,
        firstLevel: levels.indexWhere((level) => level.tube == tube),
        runs: true,
      );
      final runner = await pumpToRun(tester, game);
      runner.spawning = true;
      await pumpFrames(tester, 2);
      expect(game.shooter.player.isVisible, isFalse);
      expect(runner.ship.isVisible, isTrue);
      expect(runner.ship.step, game.shooter.player.step);
      expect(
        (runner.ship.position - game.shooter.player.position).length,
        lessThan(0.02 * game.view.rimScale),
      );
      const playEnd = Tube.depth + RunnerMode.flightSpeed * ShooterMode.runTime;
      final kinds = <EnemyKind>{};
      var mostAt = 0.0;
      for (var i = 0; i < 2000 && game.shooter.state == TubeState.run; i++) {
        // A lost ship goes on at READY.
        if (game.isReady) {
          await pressKey(tester);
        }
        await tester.pump(const Duration(milliseconds: 16));
        for (final enemy in runner.enemies) {
          kinds.add(enemy.kind);
          mostAt = math.max(mostAt, enemy.at);
        }
      }
      expect(game.shooter.state, TubeState.arrive);
      expect(kinds, {EnemyKind.seeder});
      expect(mostAt, lessThanOrEqualTo(playEnd));
      expect(runner.isMounted, isFalse);
      expect(game.shooter.player.isVisible, isTrue);
      await pumpFrames(tester, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a ship lost on a run waits at READY, with the run standing '
      'still, and Game Over there starts a new game at the round', (
    tester,
  ) async {
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizerCanvas,
      firstLevel: hexagon,
      runs: true,
    );
    final runner = await pumpToRun(tester, game);
    final round = game.shooter.round;
    game.lives = 2;
    runner.addEnemy(EnemyKind.seeder, runner.ship.lane);
    await pumpUntil(tester, () => game.isReady, frames: 1000);
    expect(game.lives, 1);
    expect(game.shooter.state, TubeState.run);
    final flown = runner.flown;
    final time = game.roundText.text;
    await pumpFrames(tester, 30);
    expect(runner.flown, flown);
    expect(game.roundText.text, time);
    await pressKey(tester);
    await pumpFrames(tester, 2);
    expect(game.canMove, isTrue);
    expect(runner.flown, greaterThan(flown));
    runner.addEnemy(EnemyKind.seeder, runner.ship.lane);
    await pumpUntil(tester, () => game.isOver, frames: 1000);
    // Game Over mounts on the next frame.
    await pumpFrames(tester, 1);
    expect(game.shooter.state, TubeState.run);
    expect(game.gameOverText.isMounted, isTrue);
    expect(game.world.timeScale, 0);
    await pressKey(tester, LogicalKeyboardKey.enter);
    await pumpFrames(tester, 2);
    expect(game.shooter.state, TubeState.zoom);
    expect(game.shooter.round, round);
    expect(game.shooter.level.tube, Tubes.hexagon);
    expect(game.lives, TubeHost.startLives);
    expect(game.score, 0);
    expect(runner.isMounted, isFalse);
    expect(game.gameOverText.isMounted, isFalse);
    await pumpFrames(tester, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an enemy's explosion as the run's play ends goes on, where it "
      'is along the run, on the arrival, until done', (tester) async {
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizerCanvas,
      firstLevel: hexagon,
      runs: true,
    );
    final runner = await pumpToRun(tester, game);
    const playEnd = Tube.depth + RunnerMode.flightSpeed * ShooterMode.runTime;
    await pumpUntil(
      tester,
      () => runner.flown >= playEnd - 0.5,
      frames: 2000,
    );
    // A climber across the tube, a little ahead of the ship, which a shot
    // destroys just before the run's play ends.
    final lanes = game.view.tube.laneCount;
    runner.addEnemy(EnemyKind.climber, (runner.ship.lane + lanes ~/ 2) % lanes);
    final climber = (runner.enemies.last as RunnerFlipperComponent)
      ..at = runner.flown + 3;
    await pumpFrames(tester, 1);
    expect(climber.isVisible, isTrue);
    runner.destroyEnemy(climber);
    await pumpFrames(tester, 1);
    final blast = runner.blasts.single;
    expect(blast.isVisible, isTrue);
    await pumpUntil(tester, () => game.shooter.state == TubeState.arrive);
    expect(runner.isMounted, isFalse);
    expect(blast.isMounted, isTrue);
    expect(blast.parent, same(game.shooter.explosionGroup));
    expect(blast.isVisible, isTrue);
    // The eye flies on, so it shows elsewhere each frame.
    final at = blast.position.clone();
    await pumpFrames(tester, 1);
    expect(blast.position, isNot(at));
    await pumpUntil(tester, () => !blast.isMounted, frames: 100);
    expect(game.shooter.state, TubeState.arrive);
    await pumpFrames(tester, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
