import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// What a shot resumes from when the game switches to another renderer: its
/// lane, where it is along the axis, and where it was before it last moved.
typedef RunnerShotSnapshot = ({int lane, double at, double previousAt});

/// A shot from the ship that flies down its [lane] from [at], as Tube
/// Shooter's `ShotComponent` does.
///
/// It has the same shape and colour, and flies ahead of the ship at the same
/// speed. It is gone when it gets [range] ahead of the ship.
///
/// The game moves it with [fly].
class RunnerShotComponent(final int lane, var double at)
    extends PositionComponent
    with HasGameRef<TubeHost>, HasVisibility, TubePlaced {
  this : super(priority: 2);

  /// How fast it flies ahead of the ship, in tube units a second: fast
  /// enough to cross Tube Shooter's tube in `ShotComponent.crossTime`.
  static const speed = Tube.depth / ShotComponent.crossTime;

  /// How far ahead of the ship it goes, in tube units.
  static const range = 8.0;

  /// Where it was along the axis before it last flew.
  late double previousAt = at;

  /// What a game with another renderer goes on from.
  RunnerShotSnapshot get snapshot =>
      (lane: lane, at: at, previousAt: previousAt);

  @override
  TubeMark get mark => (lane: lane, at: at, flip: null, across: null);

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

  /// Flies over [dt] seconds at the ship's [shipSpeed] plus its own
  /// [speed].
  void fly(double dt, double shipSpeed) {
    previousAt = at;
    at += (shipSpeed + speed) * dt;
  }
}

/// A shot from a climber that climbs its [lane] toward the ship from [at],
/// at [speed] along the axis.
///
/// It has the shape and colour of Tube Shooter's `EnemyShotComponent`. The
/// game moves it with [climb], and removes it when it reaches the ship. If
/// the ship is in its lane, the shot destroys it.
class RunnerEnemyShotComponent(final int lane, var double at)
    extends PositionComponent
    with HasGameRef<TubeHost>, HasVisibility, TubePlaced {
  this : super(priority: 2);

  /// How fast it climbs its lane along the axis, in tube units a second:
  /// faster than the climber that fires it, which climbs at
  /// `RunnerEnemyComponent.climbSpeed`.
  static const speed = 1.5;

  /// Where it was along the axis before it last climbed.
  late double previousAt = at;

  /// What a game with another renderer goes on from.
  RunnerShotSnapshot get snapshot =>
      (lane: lane, at: at, previousAt: previousAt);

  @override
  TubeMark get mark => (lane: lane, at: at, flip: null, across: null);

  /// The component that draws its shape.
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.enemyShot, TubeColors.shot));
  }

  @override
  void update(double dt) {
    super.update(dt);
    gameRef.keepStroke(drawing);
  }

  /// Climbs over [dt] seconds.
  void climb(double dt) {
    previousAt = at;
    at -= speed * dt;
  }
}
