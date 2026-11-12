// Helpers that the headless and the device tests of a whole Tube Shooter game
// share.
import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Watches [game] after each frame for anything that falls back from the
/// [expected] renderer.
///
/// It reports a renderer other than [expected], and any path component that
/// draws with `Canvas.drawPath`, so with no [RasterizerScene], or with a
/// scene of another renderer. It also stops at the test's end, in case the
/// test fails before it calls [stop].
class FallbackWatch(
  final RasterizerTubeShooterExample game,
  final RasterizerBackend expected,
) {
  this {
    SchedulerBinding.instance.addPostFrameCallback(_check);
    addTearDown(stop);
  }

  /// What fell back, each named once, with the game state it fell back in.
  final problems = <String>{};

  /// The game states of the frames it checked.
  final states = <TubeState>{};

  /// How many frames it checked.
  int frames = 0;

  bool _stopped = false;

  /// Stops watching.
  void stop() => _stopped = true;

  void _check(Duration _) {
    if (_stopped) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(_check);
    final renderer = game.rasterizer;
    // The game draws nothing before its renderer is ready, or once it's gone.
    if (renderer == null) {
      return;
    }
    frames++;
    final state = game.state;
    states.add(state);
    if (renderer.backend != expected) {
      problems.add('${state.name}: the ${renderer.backend.name} renderer');
    }
    for (final path
        in game.descendants().whereType<RasterizerPathComponent>()) {
      if (!path.isMounted || _isHidden(path)) {
        continue;
      }
      final scene = path.debugScene;
      if (scene == null) {
        problems.add(
          '${state.name}: Canvas.drawPath under ${path.parent.runtimeType}',
        );
      } else if (scene.backend != expected) {
        problems.add(
          '${state.name}: a ${scene.backend.name} scene under '
          '${path.parent.runtimeType}',
        );
      }
    }
  }

  /// Whether [component] is under a hidden ancestor, so that it doesn't draw
  /// at all.
  static bool _isHidden(Component component) => component.ancestors().any(
    (ancestor) => ancestor is HasVisibility && !ancestor.isVisible,
  );
}

/// Plays a whole game of [game], tapping at [center] and pumping with
/// [pumpFor].
///
/// It goes through every [TubeState]: the zoom, a level begun by a tap, and
/// enemies fought by a finger that sweeps round the rim. Then come a purge, a
/// lost ship, a cleared round's drop and the next round. It loses the other
/// lives until Game Over, and starts a new game up to READY.
Future<void> playWholeGame(
  WidgetTester tester,
  TubeShooterExample game,
  Offset center,
  Future<void> Function(double seconds, {bool Function()? done}) pumpFor,
) async {
  Future<void> reach(TubeState state, {double seconds = 15}) async {
    await pumpFor(seconds, done: () => game.state == state);
    expect(game.state, state);
  }

  // An enemy can destroy the ship at any time, so the game may be in play
  // already, or waiting on READY again.
  Future<void> begin() async {
    await pumpFor(
      15,
      done: () => game.state == TubeState.ready || game.state == TubeState.play,
    );
    if (game.state == TubeState.ready) {
      await tester.tapAt(center);
      await reach(TubeState.play, seconds: 1);
    }
    expect(game.state, TubeState.play);
  }

  // A climber at the rim in the ship's lane destroys the ship.
  void loseShip() =>
      game.addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));

  await begin();
  final finger = await tester.startGesture(center);
  for (var i = 0; i < 240 && game.state == TubeState.play; i++) {
    await finger.moveBy(Offset(i % 60 < 30 ? 8 : -8, 0));
    await pumpFor(1 / 60);
  }
  await finger.up();
  game.purge();
  await pumpFor(0.5);

  await begin();
  loseShip();
  await reach(TubeState.dying, seconds: 1);

  await begin();
  game.clearSpawns();
  for (final enemy in [...game.enemies]) {
    game.discard(enemy);
  }
  await reach(TubeState.drop, seconds: 1);
  await reach(TubeState.zoom);

  do {
    await begin();
    loseShip();
    await pumpFor(
      5,
      done: () => game.state == TubeState.ready || game.state == TubeState.over,
    );
  } while (game.state != TubeState.over);
  await pumpFor(0.5);
  await tester.tapAt(center);
  await reach(TubeState.zoom, seconds: 2);
  await reach(TubeState.ready);
}
