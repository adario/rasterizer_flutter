import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/outlined.dart';

/// A slide down to a flipper, with a recess for it.
class GuideComponent(@override final List<Vector2> outline)
    extends BodyComponent
    with GlowingBody, Outlined {
  this : super(paint: Paint()..color = ExampleColors.slate);

  @override
  Body createBody() {
    final body = world.createBody(BodyDef());
    addPieces(
      body,
      ShapeDef(
        material: SurfaceMaterial(friction: 0.3),
        enableHitEvents: true,
      ),
    );
    return body;
  }
}
