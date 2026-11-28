import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_field_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// The stars, as on Tube Shooter's drop: see [StarFieldComponent], whose
/// numbers they share.
///
/// They lie round the eye's line of sight, not round the tube's axis, so they
/// don't bend with the tube. Each frame, they come closer by as far as
/// the ship flew, so they stream outward as streaks. A star that passes the
/// near plane goes back to the farthest distance, at a new random place. As
/// the ship flies, they turn toward the tube's bends ahead, as Tube Shooter's
/// stars do on a run: see [StarFieldComponent.bendTurnOver]. Nearer stars
/// turn more, as with parallax.
///
/// There are [TubeHost.starCount] of them. When that count changes, stars
/// go, or new ones come at random distances, as at the start.
///
/// It sits in the camera's backdrop, as Tube Shooter's stars do. It still
/// draws through the viewfinder's transform and updates at the world's time
/// scale, as if it were in the world.
class FlightStarsComponent(
  /// The mode whose ship the stars fly by.
  final RunnerMode runner,
) extends Component with HasGameRef<TubeHost>, CustomTraversal {
  final stars = <FlightStarComponent>[];

  /// How far the ship had flown at the last update.
  double _flown = 0;

  @override
  Future<void> onLoad() async {
    _flown = runner.flown;
    _matchCount();
  }

  /// Adds or removes stars, so that there are [TubeHost.starCount]: the last
  /// ones go, and new ones come at random distances.
  void _matchCount() {
    final count = gameRef.starCount;
    if (stars.length > count) {
      removeAll(stars.sublist(count));
      stars.removeRange(count, stars.length);
    }
    final added = [
      for (var i = stars.length; i < count; i++) _star(),
    ];
    stars.addAll(added);
    addAll(added);
  }

  /// Returns a new star, at a random distance from the eye.
  FlightStarComponent _star() {
    final distance =
        TubeView.near +
        (StarFieldComponent.far - TubeView.near) * gameRef.random.nextDouble();
    return FlightStarComponent(_point(), distance)
      ..brightness = _brightnessAt(distance);
  }

  /// Returns how bright a star [distance] from the eye is.
  static double _brightnessAt(double distance) =>
      ((StarFieldComponent.far - distance) /
              (StarFieldComponent.far - StarFieldComponent.bright))
          .clamp(0.0, 1.0);

  /// Returns a random place across the line of sight for a star, spread
  /// evenly over the area.
  Offset _point() {
    final random = gameRef.random;
    final (:inner, :outer) = StarFieldComponent.radii;
    final radius = math.sqrt(
      inner * inner + (outer * outer - inner * inner) * random.nextDouble(),
    );
    return Offset.fromDirection(2 * math.pi * random.nextDouble(), radius);
  }

  /// Updates it and the stars at the world's time scale, as the world
  /// updates its components, so not at all in a still world. Even then, it
  /// adds or removes stars as [TubeHost.starCount] changes.
  @override
  void updateSubtree(double dt) {
    if (isLoaded) {
      _matchCount();
    }
    final timeScale = gameRef.world.timeScale;
    if (timeScale > 0) {
      super.updateSubtree(dt * timeScale);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    canvas
      ..save()
      ..transform2D(gameRef.camera.viewfinder.transform);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final closer = runner.flown - _flown;
    _flown = runner.flown;
    final turn = StarFieldComponent.bendTurnOver(
      runner.endlessTube,
      runner.flown,
      closer,
    );
    for (final star in stars) {
      star
        ..cameFrom = star.eyeDistance
        ..eyeDistance -= closer;
      while (star.eyeDistance < TubeView.near) {
        star
          ..eyeDistance += StarFieldComponent.far - TubeView.near
          ..cameFrom = star.eyeDistance
          ..point = _point();
      }
      // The star is past the near plane, so it's never too close to the eye
      // for the ratio below.
      if (turn != 0) {
        final ratio =
            StarFieldComponent.turnRatio *
            StarFieldComponent.bright /
            star.eyeDistance;
        star.point = Tube.rotate(star.point, turn * ratio);
      }
      star.brightness = _brightnessAt(star.eyeDistance);
    }
  }
}

/// A star: a white dot that streaks as it moves, as [StarComponent] does on
/// Tube Shooter's drop.
///
/// It lies [point] away from the eye's line of sight, and [eyeDistance] from
/// the eye along it, in tube units.
class FlightStarComponent(Offset point, double eyeDistance)
    extends PositionComponent
    with HasGameRef<TubeHost> {
  Offset point = point;
  double eyeDistance = eyeDistance;

  /// Its distance from the eye the frame before, at least [eyeDistance].
  double cameFrom = eyeDistance;

  /// How bright it is, from 0, unseen, to 1: its opacity.
  double brightness = 0;

  /// The component that draws it.
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.dotComponent(TubeColors.star));
    place();
  }

  @override
  void update(double dt) {
    super.update(dt);
    place();
  }

  /// Places it as a streak from where it was the frame before to where it is,
  /// as wide as [StarComponent]s are.
  void place() {
    final view = gameRef.view;
    final scale = view.scaleOf(eyeDistance);
    final before = view.scaleOf(cameFrom);
    // The streak's middle, between where it was and where it is.
    final drawn = point * ((scale + before) / 2);
    final width =
        StarComponent.widthScale *
        math.min(
          TubeView.rimPixels * view.devicePixel,
          view.lineWidthOf(eyeDistance),
        );
    position.setValues(drawn.dx, drawn.dy);
    angle = point.direction;
    this.scale.setValues(width + point.distance * (scale - before), width);
    drawing.opacity = brightness;
  }
}
