part of 'multiple_shapes_example.dart';

/// Where a component is, and how it moves and spins.
typedef MovingSnapshot = ({
  Vector2 position,
  Vector2 velocity,
  double angle,
  double rotationSpeed,
});

/// The state that a game with another renderer resumes from.
///
/// It holds the shapes picked, and the positions and motion of the snowman and
/// the shapes.
typedef MultipleShapesSnapshot = ({
  List<ShapePick> picks,
  MovingSnapshot snowman,
  List<MovingSnapshot> shapes,
});

/// Takes a snapshot of a [MultipleShapesExample] and resumes from one.
extension MultipleShapesSnapshots on MultipleShapesExample {
  /// The state that a game with another renderer resumes from.
  MultipleShapesSnapshot get snapshot => (
    picks: [..._picks],
    snowman: snowman._snapshot,
    shapes: [for (final shape in tintedShapes) shape._snapshot],
  );

  /// Picks the snapshot's shapes, before they're made.
  void _restorePicks() {
    if (_from case final from?) {
      _picks.addAll(from.picks);
    }
  }

  /// Places the snowman and the shapes where the snapshot's were, with the same
  /// velocities, angles and rotation speeds.
  void _restoreCollidables() {
    if (_from case final from?) {
      snowman._restore(from.snowman);
      for (final (i, was) in from.shapes.take(tintedShapes.length).indexed) {
        tintedShapes[i]._restore(was);
      }
    }
  }
}

extension on MovingCollidable {
  MovingSnapshot get _snapshot => (
    position: position.clone(),
    velocity: velocity.clone(),
    angle: angle,
    rotationSpeed: rotationSpeed,
  );

  void _restore(MovingSnapshot was) {
    position.setFrom(was.position);
    velocity.setFrom(was.velocity);
    angle = was.angle;
    rotationSpeed = was.rotationSpeed;
  }
}
