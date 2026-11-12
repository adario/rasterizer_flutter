import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A star: a white dot that streaks as it moves.
///
/// It lies [point] away from the tube's axis, and [eyeDistance] from the eye
/// along the axis, in tube units.
class StarComponent(Offset point, double eyeDistance) extends DotComponent {
  this : super(TubeColors.star);

  /// How many times as wide as the tube's lines at the same distance stars
  /// are.
  static const widthScale = 2.0;

  /// How many logical pixels longer a star is while [isSlow], so that drifting
  /// stars show as short streaks.
  static const slowLength = 1.0;

  Offset point = point;
  double eyeDistance = eyeDistance;

  /// Its distance from the eye the frame before, at least [eyeDistance].
  double cameFrom = eyeDistance;

  /// How bright it is, from 0, unseen, to 1: its opacity.
  double brightness = 0;

  /// Whether the star field moves slowly, which keeps the streaks short.
  bool isSlow = false;

  /// Places it as a streak from where it was the frame before to where it is.
  ///
  /// It's [widthScale] times as wide as the tube's lines at its distance, and
  /// at most [widthScale] times [TubeView.rimPixels]. While [isSlow], its
  /// streak is at most as long as it's wide, and [slowLength] longer. Its
  /// opacity is its [brightness], which doesn't import its path again.
  @override
  void place() {
    final view = gameRef.view;
    final scale = view.scaleOf(eyeDistance);
    final before = view.scaleOf(cameFrom);
    // The streak's middle, between where it was and where it is.
    final drawn = point * ((scale + before) / 2);
    final width =
        widthScale *
        math.min(
          TubeView.rimPixels * view.devicePixel,
          view.lineWidthOf(eyeDistance),
        );
    final streak = point.distance * (scale - before);
    position.setValues(drawn.dx, drawn.dy);
    angle = point.direction;
    // A logical pixel is a world unit at the camera's zoom of 1.
    final slow = slowLength / gameRef.camera.viewfinder.zoom;
    this.scale.setValues(
      width + (isSlow ? math.min(streak, width) + slow : streak),
      width,
    );
    drawing.opacity = brightness;
  }
}
