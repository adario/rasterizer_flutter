part of 'revolute_joint_svgs_example.dart';

/// What a game for another renderer goes on from: the wheel and the bodies
/// dropped, where they are and how they move, and the next body's color.
typedef RevoluteJointSvgsSnapshot = ({
  BodySnapshot? wheel,
  List<BallSnapshot> balls,
  List<SvgBodySnapshot> svgBodies,
  int tint,
});

/// Takes a [RevoluteJointSvgsExample]'s snapshot, and goes on from one.
///
/// Box2D's contacts between the bodies start again in the new game, so a
/// pile can settle a little at its first steps.
extension RevoluteJointSvgsSnapshots on RevoluteJointSvgsExample {
  /// What a game for another renderer goes on from.
  ///
  /// It leaves out the bodies that a tap dropped at this frame, which have no
  /// Box2D body yet.
  RevoluteJointSvgsSnapshot get snapshot => (
    wheel: switch (_wheel) {
      final wheel? when wheel.isLoaded => wheel.body.snapshot,
      _ => null,
    },
    balls: [
      for (final ball in balls)
        if (ball.isLoaded) ball.snapshot,
    ],
    svgBodies: [
      for (final svgBody in svgBodies)
        if (svgBody.isLoaded) svgBody.snapshot,
    ],
    tint: tint,
  );

  /// Drops the snapshot's bodies again, where they were and moving as they
  /// were.
  void _restoreBodies() {
    if (_from case final from?) {
      balls.addAll(from.balls.map(Ball.from));
      svgBodies.addAll(from.svgBodies.map(svgBodyFrom));
      world.addAll([...balls, ...svgBodies]);
      tint = from.tint;
    }
  }
}
