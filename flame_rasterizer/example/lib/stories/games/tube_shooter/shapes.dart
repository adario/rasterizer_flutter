import 'dart:math' as math;
import 'dart:ui';

/// The game's colours, on black.
///
/// The first tube, the ship and the enemies take colours of
/// `ExampleColors.dynamics`, except the edge-walker's fuchsia. The other tubes
/// are orange, lime and slate. The shots, explosions, stars and texts are
/// white.
abstract final class TubeColors() {
  static const tube = Color(0xFFA78BFA);
  static const tubeOrange = Color(0xFFF97316);
  static const tubeLime = Color(0xFFA3E635);
  static const tubeSlate = Color(0xFF94A3B8);
  static const ship = Color(0xFF38BDF8);
  static const climber = Color(0xFFFBBF24);
  static const splitter = Color(0xFFFB7185);
  static const seeder = Color(0xFF7C9CFF);
  static const spikes = seeder;
  static const zapper = Color(0xFF34D399);
  static const bolts = zapper;
  static const edgeWalker = Color(0xFFE879F9);
  static const shot = Color(0xFFFFFFFF);
  static const explosion = Color(0xFFFFFFFF);
  static const star = Color(0xFFFFFFFF);
  static const text = Color(0xFFFFFFFF);
}

/// The game's shapes: straight lines, stroked with miter joins, except for
/// the dot, which is filled.
///
/// Each shape is one path, which all its components share, so it costs one
/// import. Shapes are in lane units: a lane is 1 wide along x, with its middle
/// at the origin, and y grows toward the tube's axis, deeper.
abstract final class Shapes() {
  /// The ship: a manta, with its prongs pointing out of the tube.
  static final ship = _polygon(const [
    Offset(-0.5, 0),
    Offset(-0.22, -0.2),
    Offset(0, -0.06),
    Offset(0.22, -0.2),
    Offset(0.5, 0),
    Offset(0, 0.28),
  ]);

  /// A climber: a hooked Z across its lane, which looks the same turned half
  /// a turn, as it is after a flip.
  static final climber = Path()
    ..addPolygon(const [
      Offset(-0.5, 0.06),
      Offset(-0.5, -0.16),
      Offset(0.18, -0.16),
      Offset(-0.18, 0.16),
      Offset(0.5, 0.16),
      Offset(0.5, -0.06),
    ], false);

  /// A splitter: a diamond, with its diagonals.
  static final splitter =
      _polygon(const [
          Offset(-0.42, 0),
          Offset(0, -0.26),
          Offset(0.42, 0),
          Offset(0, 0.26),
        ])
        ..addPolygon(const [Offset(-0.42, 0), Offset(0.42, 0)], false)
        ..addPolygon(const [Offset(0, -0.26), Offset(0, 0.26)], false);

  /// A seeder: an arrow pointing out of the tube, with its tail toward the
  /// spike it lays.
  static final seeder = _polygon(const [
    Offset(-0.24, 0.08),
    Offset(0, -0.26),
    Offset(0.24, 0.08),
  ])..addPolygon(const [Offset(0, 0.08), Offset(0, 0.3)], false);

  /// A zapper: a zigzag across its lane, which looks the same turned half a
  /// turn, as it is after a flip.
  static final zapper = Path()
    ..addPolygon(const [
      Offset(-0.5, 0),
      Offset(-0.3, -0.16),
      Offset(-0.1, 0.16),
      Offset(0.1, -0.16),
      Offset(0.3, 0.16),
      Offset(0.5, 0),
    ], false);

  /// An edge-walker: a spark of three lines crossing at its middle, which it
  /// spins about.
  static final edgeWalker = () {
    final path = Path();
    for (var i = 0; i < 3; i++) {
      final direction = Offset.fromDirection(i * math.pi / 3, 0.2);
      path.addPolygon([-direction, direction], false);
    }
    return path;
  }();

  /// The ship's shot: a small diamond.
  static final shot = _polygon(const [
    Offset(0, -0.12),
    Offset(0.08, 0),
    Offset(0, 0.12),
    Offset(-0.08, 0),
  ]);

  /// An enemy's shot: a small cross.
  static final enemyShot = Path()
    ..addPolygon(const [Offset(-0.1, -0.1), Offset(0.1, 0.1)], false)
    ..addPolygon(const [Offset(0.1, -0.1), Offset(-0.1, 0.1)], false);

  /// An explosion: 8 rays.
  static final burst = () {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      _addRay(path, i * math.pi / 4);
    }
    return path;
  }();

  /// One of the rays that fly out of an explosion: the same as a ray of
  /// [burst], but halfway between its first two.
  static final ray = _addRay(Path(), math.pi / 8);

  /// Adds to [path] a ray at [angle], from 0.12 to 0.4 away from the origin,
  /// and returns [path].
  static Path _addRay(Path path, double angle) {
    final direction = Offset.fromDirection(angle);
    return path..addPolygon([direction * 0.12, direction * 0.4], false);
  }

  /// A dot, for the enemies still to come and for the stars: a regular
  /// octagon, 1 across between opposite sides, centred on the origin.
  ///
  /// Its contour stays open, as the fill closes it anyway. For each of its
  /// components, Flame's `PathComponent` would walk a closed contour into
  /// polygons, which the game doesn't use.
  static final dot = Path()
    ..addPolygon([
      for (var k = 0; k < 8; k++)
        Offset.fromDirection(
          (2 * k + 1) * math.pi / 8,
          0.5 / math.cos(math.pi / 8),
        ),
    ], false);

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);
}
