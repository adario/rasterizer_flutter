part of 'collidable_svgs_example.dart';

/// What a game for another renderer goes on from: the SVGs' names and
/// widths, where the SVGs are and how they move, and the collisions so far.
typedef CollidableSvgsSnapshot = ({
  List<String> names,
  List<double> widths,
  List<({Vector2 position, Vector2 velocity, double angle})> svgs,
  int collisions,
});

/// Takes a [CollidableSvgsExample]'s snapshot, and goes on from one.
extension CollidableSvgsSnapshots on CollidableSvgsExample {
  /// What a game for another renderer goes on from.
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

  /// Picks the snapshot's SVGs, at its widths, before they load.
  void _restorePicks() {
    if (_from case final from?) {
      _names.addAll(from.names);
      _widthsPicked.addAll(from.widths);
    }
  }

  /// Places the SVGs where the snapshot's were, moving and turned as they
  /// were, and counts its collisions.
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
