import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns where on the screen the centre of the tube's near end is: the
/// world's origin, in the [GameWidget] that plays [game].
Offset nearEndCentreOf(WidgetTester tester, FlameGame game) {
  final origin = game.camera.localToGlobal(Vector2.zero());
  return tester.getTopLeft(find.byWidgetPredicate((w) => w is GameWidget)) +
      origin.toOffset();
}

/// Draws [turns] of a circle of [radius] logical pixels round [centre] with
/// a finger that goes down at the angle [from], in 36 moves a turn,
/// clockwise on the screen for positive [turns], with a frame after each
/// move.
Future<void> drawCircle(
  WidgetTester tester,
  Offset centre, {
  required double from,
  double turns = 1,
  double radius = 200,
}) async {
  const movesPerTurn = 36;
  final moves = (turns.abs() * movesPerTurn).round();
  Offset pointAt(int move) => Offset.fromDirection(
    from + 2 * math.pi * turns * move / moves,
    radius,
  );
  final finger = await tester.startGesture(centre + pointAt(0));
  await tester.pump();
  for (var move = 1; move <= moves; move++) {
    await finger.moveTo(centre + pointAt(move));
    await tester.pump();
  }
  await finger.up();
  await tester.pump();
}

/// Returns [angle] as a turn between minus and plus pi.
double turnOf(double angle) => (angle + math.pi) % (2 * math.pi) - math.pi;
