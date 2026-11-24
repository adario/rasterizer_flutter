import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';

/// A shape down the middle of a lane of the tube, at its [mark], which the
/// game places with [placeAt] where the tube says it shows.
mixin TubePlaced on PositionComponent, HasVisibility {
  /// Where it is along the tube.
  TubeMark get mark;

  /// Shows it at [place], or hides it if null.
  void placeAt(ShapePlace? place) {
    isVisible = place != null;
    if (place == null) {
      return;
    }
    position.setValues(place.position.dx, place.position.dy);
    angle = place.angle;
    scale.splat(place.scale);
  }
}
