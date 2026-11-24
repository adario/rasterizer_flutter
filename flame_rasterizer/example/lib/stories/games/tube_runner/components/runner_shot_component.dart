import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A shot from the ship, which flies down its [lane] from [at], as Tube
/// Shooter's `ShotComponent` does, with the same shape, colour and speed
/// ahead of the ship, and is gone [range] ahead of it.
///
/// The game moves it with [fly].
class RunnerShotComponent(final int lane, var double at)
    extends PositionComponent
    with HasGameRef<TubeRunnerExample>, HasVisibility, TubePlaced {
  this : super(priority: 2);

  /// How fast it flies ahead of the ship, in tube units a second: across
  /// Tube Shooter's tube in its `ShotComponent.crossTime`.
  static const speed = Tube.depth / ShotComponent.crossTime;

  /// How far ahead of the ship it goes, in tube units.
  static const range = 8.0;

  /// Where it was along the axis before it last flew.
  late double previousAt = at;

  @override
  TubeMark get mark => (lane: lane, at: at);

  /// The component that draws its shape.
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.shot, TubeColors.shot));
  }

  @override
  void update(double dt) {
    super.update(dt);
    gameRef.keepStroke(drawing);
  }

  /// Flies over [dt] seconds, with the ship and [speed] ahead of it.
  void fly(double dt) {
    previousAt = at;
    at += (TubeRunnerExample.flightSpeed + speed) * dt;
  }
}
