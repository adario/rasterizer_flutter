// Checks the prototype of Tube Shooter's runs into Tube Runner's tube: that
// the run's tube leads on from the round's and into the next round's, and
// that a round's drop flies on down a run, onto the next round's rim.
import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'tube_shooter_test.dart' show beginLevel, pumpFrames, pumpGame;

void main() {
  const course = (bendFrom: Tube.depth, bendTo: 40.0, ease: 8.0);

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

  testWidgets('with runs, the hexagon drop flies on down a run, then onto '
      'the next rim, with no jump of the ship', (tester) async {
    final hexagon = levels.indexWhere((level) => level.tube == Tubes.hexagon);
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizerCanvas,
      firstLevel: hexagon,
    );
    game
      ..runs = true
      ..spawning = false;
    await beginLevel(tester, game);
    game.score = 1234;
    game.clearSpawns();
    var last = game.player.position.toOffset();
    var most = 0.0;
    final states = <TubeState>[];
    for (var i = 0; i < 2000 && game.state != TubeState.ready; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final position = game.player.position.toOffset();
      most = (position - last).distance > most
          ? (position - last).distance
          : most;
      last = position;
      if (states.isEmpty || states.last != game.state) {
        states.add(game.state);
      }
    }
    expect(states, [
      TubeState.drop,
      TubeState.run,
      TubeState.arrive,
      TubeState.ready,
    ]);
    // The ship glides onto the floor's lanes, a little each frame.
    expect(most, lessThan(0.02 * game.view.rimScale));
    expect(game.level.tube, Tubes.floor);
    expect(game.round, 2);
    expect(game.score, 1234);
    expect(game.lives, TubeShooterExample.startLives);
    expect(game.player.isVisible, isTrue);
    expect(game.player.depth, 0);
    expect(game.view.eyeShift, 0);
    await pumpFrames(tester, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
