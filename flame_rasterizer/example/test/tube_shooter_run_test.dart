// Checks Tube Shooter's runs into Tube Runner's tube: that the run's tube
// leads on from the round's and into the next round's, that a closed or an
// open tube's drop flies on down a run, onto the next round's rim, and that
// the run plays by Tube Runner's rules.
import 'dart:math' as math;

import 'package:flame/components.dart' show HasVisibility, PositionComponent;
import 'package:flame/extensions.dart';
import 'package:flame/game.dart' show GameWidget;
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';
import 'tube_shooter_test.dart'
    show beginLevel, pumpFrames, pumpGame, pumpUntil, story;

void main() {
  const course = (bendFrom: Tube.depth, bendTo: 40.0, ease: 8.0);
  final hexagon = levels.indexWhere((level) => level.tube == Tubes.hexagon);
  // As many frames as the first round's drop, run and arrival take, and
  // some more.
  final runFrames =
      ((ShooterMode.dropTime +
                  ShooterMode.runTime(1) +
                  ShooterMode.arriveTime) /
              0.016)
          .ceil() +
      500;

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
      for (
        var i = 0;
        i < runFrames && game.shooter.state != TubeState.ready;
        i++
      ) {
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
      final playEnd =
          Tube.depth + TubeHost.defaultFlightSpeed * ShooterMode.runTime(1);
      final kinds = <EnemyKind>{};
      var mostAt = 0.0;
      for (
        var i = 0;
        i < runFrames && game.shooter.state == TubeState.run;
        i++
      ) {
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

  testWidgets('a new renderer on the drop goes on down its run, with no '
      'jump of the eye', (tester) async {
    Widget storyWith(SvgRenderer renderer, {double speed = 1}) =>
        story(renderer, speed: speed, firstLevel: hexagon, runs: true);
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizer,
      firstLevel: hexagon,
      runs: true,
    );
    game.shooter.spawning = false;
    await beginLevel(tester, game);
    game.shooter.clearSpawns();
    await pumpUntil(
      tester,
      () => game.shooter.state == TubeState.drop && game.view.eyeShift > 0.5,
      frames: 400,
    );
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizer, speed: 0));
    await tester.pump(const Duration(milliseconds: 16));
    final eyeShift = game.view.eyeShift;
    expect(game.snapshot.hasRun, isTrue);

    await tester.pumpWidget(storyWith(SvgRenderer.rasterizerCanvas, speed: 0));
    final next = tester
        .widget<GameWidget<TubeShooterExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    expect(next, isNot(same(game)));
    await pumpWhileLoading(tester, () => !next.isLoaded);
    await pumpFrames(tester, 2);
    expect(next.shooter.state, TubeState.drop);
    expect(next.view.eyeShift, eyeShift);
    expect(next.shooter.runner, isNotNull);

    // The drop goes on along the run's curve, not the plain drop's.
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizerCanvas));
    var last = eyeShift;
    var most = 0.0;
    for (var i = 0; i < 400 && next.shooter.state == TubeState.drop; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      most = math.max(most, (next.view.eyeShift - last).abs());
      last = next.view.eyeShift;
    }
    expect(next.shooter.state, TubeState.run);
    // As far as the ship flies in a frame at full speed, and a little more.
    expect(most, lessThan(TubeHost.defaultFlightSpeed * 0.02));
    await pumpFrames(tester, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new renderer on a run goes on from the same distance, ship, '
      'enemies, spikes and shots, where they show', (tester) async {
    Widget storyWith(SvgRenderer renderer, {double speed = 1}) =>
        story(renderer, speed: speed, firstLevel: hexagon, runs: true);
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizer,
      firstLevel: hexagon,
      runs: true,
    );
    final runner = await pumpToRun(tester, game);
    // Into the bends, where each ring has turned from the one before.
    await pumpFrames(
      tester,
      ((ShooterMode.runEase + 1) / TubeHost.defaultFlightSpeed / 0.016).ceil(),
    );
    expect(runner.flown, greaterThan(Tube.depth + ShooterMode.runEase));
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
    await pumpFrames(tester, 180);
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizer, speed: 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.shooter.state, TubeState.run);
    expect(runner.canMove, isTrue);
    final snapshot = runner.snapshot;
    expect(snapshot.shots, isNotEmpty);
    expect(snapshot.spikes, isNotEmpty);
    expect(snapshot.enemies.map((enemy) => enemy.kind).toSet(), {
      EnemyKind.seeder,
      EnemyKind.climber,
      EnemyKind.zapper,
      EnemyKind.splitter,
    });
    // A hidden shape keeps where it last showed, so only the shown count.
    Offset? placeOf(PositionComponent shape) =>
        (shape as HasVisibility).isVisible ? shape.position.toOffset() : null;
    List<Offset?> placesOf(RunnerMode runner) => [
      for (final shape in <PositionComponent>[
        runner.ship,
        ...runner.enemies,
        ...runner.children.whereType<RunnerShotComponent>(),
      ])
        placeOf(shape),
    ];
    final places = placesOf(runner);

    await tester.pumpWidget(storyWith(SvgRenderer.rasterizerCanvas, speed: 0));
    final next = tester
        .widget<GameWidget<TubeShooterExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    expect(next, isNot(same(game)));
    await pumpWhileLoading(tester, () => !next.isLoaded);
    await pumpFrames(tester, 2);
    expect(next.shooter.state, TubeState.run);
    final again = next.shooter.runner!;
    expect(again, isNot(same(runner)));
    final snapshotAgain = again.snapshot;
    // Records compare their lists by identity, so the lists go apart.
    expect(snapshotAgain.spikes, snapshot.spikes);
    expect(snapshotAgain.enemies, snapshot.enemies);
    expect(snapshotAgain.shots, snapshot.shots);
    expect(snapshotAgain.enemyShots, snapshot.enemyShots);
    expect(snapshotAgain.ship, snapshot.ship);
    expect(
      (
        snapshotAgain.state,
        snapshotAgain.stateTime,
        snapshotAgain.tubeTime,
        snapshotAgain.flown,
        snapshotAgain.sinceShot,
        snapshotAgain.untilEnemy,
        snapshotAgain.pulseClock,
      ),
      (
        snapshot.state,
        snapshot.stateTime,
        snapshot.tubeTime,
        snapshot.flown,
        snapshot.sinceShot,
        snapshot.untilEnemy,
        snapshot.pulseClock,
      ),
    );
    // The tube's rings turn as they did, so everything shows where it did.
    final placesAgain = placesOf(again);
    expect(placesAgain, hasLength(places.length));
    // The ship, some enemies and some shots show.
    expect(places.first, isNotNull);
    expect(places.skip(1).take(runner.enemies.length).nonNulls, isNotEmpty);
    expect(places.skip(1 + runner.enemies.length).nonNulls, isNotEmpty);
    for (final (i, place) in placesAgain.indexed) {
      expect(place == null, places[i] == null);
      if (place != null) {
        expect((place - places[i]!).distance, lessThan(1e-9));
      }
    }
    expect(next.shooter.player.isVisible, isFalse);
    expect(again.ship.isVisible, isTrue);
    expect(next.view.eyeShift, snapshot.flown);

    // The run goes on.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizerCanvas));
    await pumpFrames(tester, 30);
    expect(next.shooter.state, TubeState.run);
    expect(again.flown, greaterThan(snapshot.flown));
    await pumpFrames(tester, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a new renderer goes on from a run's lost ship as it fades, "
      'and from READY', (tester) async {
    Widget storyWith(SvgRenderer renderer, {double speed = 1}) =>
        story(renderer, speed: speed, firstLevel: hexagon, runs: true);

    /// Stills the world, switches to [renderer], and returns the new
    /// game's runner.
    Future<RunnerMode> switchTo(SvgRenderer from, SvgRenderer renderer) async {
      await tester.pumpWidget(storyWith(from, speed: 0));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(storyWith(renderer, speed: 0));
      final next = tester
          .widget<GameWidget<TubeShooterExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      await pumpWhileLoading(tester, () => !next.isLoaded);
      await pumpFrames(tester, 2);
      expect(next.shooter.state, TubeState.run);
      return next.shooter.runner!;
    }

    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizer,
      firstLevel: hexagon,
      runs: true,
    );
    var runner = await pumpToRun(tester, game);
    runner.addEnemy(EnemyKind.seeder, runner.ship.lane);
    await pumpUntil(
      tester,
      () => runner.state == RunnerState.dying,
      frames: 1000,
    );
    await pumpFrames(tester, 10);
    final faded = runner.ship.drawing.opacity;
    expect(faded, inExclusiveRange(0, 1));
    final flown = runner.flown;
    runner = await switchTo(
      SvgRenderer.rasterizer,
      SvgRenderer.rasterizerCanvas,
    );
    expect(runner.state, RunnerState.dying);
    expect(runner.ship.drawing.opacity, faded);
    expect(runner.flown, flown);

    // The fade goes on, to READY.
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizerCanvas));
    await pumpUntil(tester, () => runner.isReady);
    runner = await switchTo(
      SvgRenderer.rasterizerCanvas,
      SvgRenderer.rasterizer,
    );
    expect(runner.isReady, isTrue);
    expect(runner.ship.isVisible, isTrue);
    expect(runner.ship.drawing.opacity, 1);
    expect(runner.gameRef.readyText.isMounted, isTrue);
    expect(runner.flown, flown);

    // A key goes on with the run.
    await tester.pumpWidget(storyWith(SvgRenderer.rasterizer));
    await pressKey(tester);
    await pumpFrames(tester, 2);
    expect(runner.canMove, isTrue);
    expect(runner.gameRef.readyText.isMounted, isFalse);
    expect(runner.flown, greaterThan(flown));
    await tester.pumpWidget(const SizedBox());
  });

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
    final playEnd =
        Tube.depth + TubeHost.defaultFlightSpeed * ShooterMode.runTime(1);
    await pumpUntil(
      tester,
      () => runner.flown >= playEnd - 0.5,
      frames: runFrames,
    );
    // A climber across the tube, a little ahead of the ship, which a shot
    // destroys just before the run's play ends.
    final lanes = game.view.tube.laneCount;
    runner.addEnemy(EnemyKind.climber, (runner.ship.lane + lanes ~/ 2) % lanes);
    final climber = (runner.enemies.last as RunnerFlipperComponent)
      ..at = runner.flown + 1.5;
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
