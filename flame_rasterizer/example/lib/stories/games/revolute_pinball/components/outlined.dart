import 'package:flame/extensions.dart';
import 'package:flame/geometry.dart' show convexPieces;
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer_example/commons/forge2d.dart';

/// A body drawn as its [outline], in its own coordinates, whose collision
/// shapes are the outline's convex pieces.
mixin Outlined on GlowingBody {
  List<Vector2> get outline;

  @override
  Path get glowPath =>
      Path()..addPolygon([for (final v in outline) v.toOffset()], true);

  void addPieces(Body body, ShapeDef def) {
    for (final piece in convexPieces(
      outline,
      minDistance: 4 * linearSlop,
      minWidth: 2 * linearSlop,
    )) {
      body.createShape(Polygon(piece), def);
    }
  }
}
