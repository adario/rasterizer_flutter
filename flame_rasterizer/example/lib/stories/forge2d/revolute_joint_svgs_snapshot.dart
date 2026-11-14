part of 'revolute_joint_svgs_example.dart';

/// What a game for another renderer goes on from: the wheel and the bodies
/// dropped, where they are and how they move, and the next body's color.
typedef RevoluteJointSvgsSnapshot = ({
  BodySnapshot? wheel,
  List<({double radius, Color color, BodySnapshot body})> balls,
  List<({String name, int side, Color color, BodySnapshot body})> svgBodies,
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
        if (ball.isLoaded)
          (
            radius: ball.radius,
            color: ball.paint.color,
            body: ball.body.snapshot,
          ),
    ],
    svgBodies: [
      for (final svgBody in svgBodies)
        if (svgBody.isLoaded)
          (
            name: svgBody.name,
            side: svgBody.side,
            color: svgBody.color,
            body: svgBody.body.snapshot,
          ),
    ],
    tint: _tint,
  );

  /// Drops the snapshot's bodies again, where they were and moving as they
  /// were.
  void _restoreBodies() {
    if (_from case final from?) {
      for (final ball in from.balls) {
        balls.add(
          Ball(
            ball.body.position,
            ball.body.linearVelocity,
            radius: ball.radius,
            color: ball.color,
            from: ball.body,
          ),
        );
      }
      for (final svgBody in from.svgBodies) {
        svgBodies.add(
          _svgBody(
            svgBody.name,
            svgBody.side,
            svgBody.body.position,
            svgBody.body.linearVelocity,
            angle: svgBody.body.rotation.angle,
            color: svgBody.color,
            from: svgBody.body,
          ),
        );
      }
      world.addAll([...balls, ...svgBodies]);
      _tint = from.tint;
    }
  }
}
