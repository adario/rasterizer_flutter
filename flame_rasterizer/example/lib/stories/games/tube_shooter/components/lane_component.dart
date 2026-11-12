import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// Something in a [lane] of the tube, at a [depth], drawn as [shape] in
/// [color].
///
/// It moves by its transform alone (see [place]), so its path is never
/// imported again.
abstract class LaneComponent(
  final Path shape,
  final Color color, {
  required int lane,
  required double depth,
}) extends PositionComponent with HasGameRef<TubeShooterExample> {
  int lane = lane;
  double depth = depth;

  /// Its depth before its last update, so that two things that pass each
  /// other within one frame still hit.
  late double previousDepth = depth;

  /// The component that draws its [shape].
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(shape, color));
    place();
  }

  @override
  void update(double dt) {
    super.update(dt);
    previousDepth = depth;
    move(dt);
    place();
    gameRef.keepStroke(drawing);
  }

  /// Moves it over [dt] seconds.
  void move(double dt) {}

  /// Places it in the middle of its lane at its depth, turned as the lane and
  /// scaled to the lane's width there.
  void place() {
    final view = gameRef.view;
    final tube = view.tube;
    final scale = view.scaleAt(depth);
    final middle = tube.middles[lane] * scale;
    position.setValues(middle.dx, middle.dy);
    angle = tube.angles[lane];
    this.scale.splat(tube.laneWidth * scale);
  }

  @override
  void onRemove() {
    gameRef.forget(this);
    super.onRemove();
  }
}
