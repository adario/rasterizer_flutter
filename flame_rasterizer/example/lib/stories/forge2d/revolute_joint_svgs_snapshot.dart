part of 'revolute_joint_svgs_example.dart';

/// The state that a game with another renderer resumes from.
///
/// It holds the wheel and the dropped bodies, with their positions and motion,
/// and the next body's color.
typedef RevoluteJointSvgsSnapshot = ({
  WheelSnapshot? wheel,
  List<BallSnapshot> balls,
  List<SvgBodySnapshot> svgBodies,
  int tint,
});

/// Takes a snapshot of a [RevoluteJointSvgsExample] and resumes from one.
///
/// Box2D rebuilds the contacts between the bodies in the new game, so a pile
/// can settle a little during the first steps.
extension RevoluteJointSvgsSnapshots on RevoluteJointSvgsExample {
  /// The state that a game with another renderer resumes from.
  ///
  /// It leaves out the bodies that a tap dropped in this frame, which have no
  /// Box2D body yet.
  RevoluteJointSvgsSnapshot get snapshot => (
    wheel: switch (_wheel) {
      final wheel? when wheel.isLoaded => wheel.snapshot,
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

  /// Drops the snapshot's bodies again, at the positions and with the motion
  /// they had, and restores the next body's color.
  void _restoreBodies() {
    if (_from case final from?) {
      balls.addAll(from.balls.map(Ball.from));
      svgBodies.addAll(from.svgBodies.map(svgBodyFrom));
      world.addAll([...balls, ...svgBodies]);
      tint = from.tint;
    }
  }
}
