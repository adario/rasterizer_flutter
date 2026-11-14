part of 'multiple_shapes_example.dart';

/// Where a component is, and how it moves and spins.
typedef MovingSnapshot = ({
  Vector2 position,
  Vector2 velocity,
  double angle,
  double rotationSpeed,
});

/// What a game for another renderer goes on from: the shapes picked, and
/// where the snowman and the shapes are and how they move.
typedef MultipleShapesSnapshot = ({
  List<(int, double)> picks,
  MovingSnapshot snowman,
  List<MovingSnapshot> shapes,
});

/// Takes a [MultipleShapesExample]'s snapshot, and goes on from one.
extension MultipleShapesSnapshots on MultipleShapesExample {
  /// What a game for another renderer goes on from.
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

  /// Places the snowman and the shapes where the snapshot's were, moving and
  /// spinning as they were.
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
