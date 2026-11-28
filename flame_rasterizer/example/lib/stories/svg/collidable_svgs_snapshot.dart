part of 'collidable_svgs_example.dart';

/// The state that a game with another renderer resumes from.
///
/// It holds the SVGs' names and widths, their positions, velocities and angles,
/// and the number of collisions so far.
typedef CollidableSvgsSnapshot = ({
  List<String> names,
  List<double> widths,
  List<({Vector2 position, Vector2 velocity, double angle})> svgs,
  int collisions,
});

/// Takes a snapshot of a [CollidableSvgsExample] and resumes from one.
extension CollidableSvgsSnapshots on CollidableSvgsExample {
  /// The state that a game with another renderer resumes from.
  CollidableSvgsSnapshot get snapshot => (
    names: [..._names],
    widths: [..._widthsPicked],
    svgs: [
      for (final svg in svgs)
        (
          position: svg.position.clone(),
          velocity: svg.velocity.clone(),
          angle: svg.angle,
        ),
    ],
    collisions: collisions,
  );

  /// Picks the snapshot's SVGs and widths before the SVGs load.
  void _restorePicks() {
    if (_from case final from?) {
      _names.addAll(from.names);
      _widthsPicked.addAll(from.widths);
    }
  }

  /// Gives the SVGs the snapshot's positions, velocities and angles, and
  /// restores its collision count.
  void _restoreSvgs() {
    if (_from case final from?) {
      for (final (i, was) in from.svgs.take(svgs.length).indexed) {
        svgs[i]
          ..position.setFrom(was.position)
          ..velocity.setFrom(was.velocity)
          ..angle = was.angle;
      }
      collisions = from.collisions;
    }
  }
}
