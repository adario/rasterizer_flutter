import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';

/// The ship, which moves round the tube's ring at the ship as Tube Shooter's
/// moves round the rim: see [PlayerComponent], whose numbers it shares.
///
/// The eye looks at that ring as Tube Shooter's looks at the rim, so the ship
/// is where Tube Shooter's is on screen.
class ShipComponent()
    extends PositionComponent
    with HasGameRef<TubeRunnerExample> {
  this : super(priority: 4);

  static const stepsPerLane = PlayerComponent.stepsPerLane;

  late int step =
      gameRef.view.tube.bottomLane * stepsPerLane + PlayerComponent.startStep;

  /// The fraction of a step it has moved, short of a whole step.
  double _partStep = 0;

  /// How long a key has moved it without a stop.
  double _keyTime = 0;

  /// The component that draws its shape.
  late final PathComponent drawing;

  int get lane => step ~/ stepsPerLane;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.ship, TubeColors.ship));
    place();
  }

  /// Moves it [lanes] round the tube, in whole steps.
  void moveBy(double lanes) {
    final moved = _partStep + lanes * stepsPerLane;
    final whole = moved.truncate();
    _partStep = moved - whole;
    step = (step + whole) % (stepsPerLane * gameRef.view.tube.laneCount);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final direction = gameRef.keyDirection;
    if (direction != 0) {
      _keyTime += dt;
      final (:first, :most) = PlayerComponent.keySpeed;
      final speed = math.min(
        most,
        first + PlayerComponent.keyAcceleration * _keyTime,
      );
      moveBy(direction * speed * dt);
    } else {
      _keyTime = 0;
    }
    place();
    gameRef.keepStroke(drawing);
  }

  /// Places it on the ring at the ship, at the angle of
  /// [PlayerComponent.headingOn].
  void place() {
    final view = gameRef.view;
    final tube = view.tube;
    final lane = this.lane;
    final along = (step % stepsPerLane + 0.5) / stepsPerLane;
    final at =
        Offset.lerp(
          tube.points[lane],
          tube.points[tube.pointAfter(lane)],
          along,
        )! *
        view.rimScale;
    position.setValues(at.dx, at.dy);
    angle = PlayerComponent.headingOn(tube, step);
    scale.splat(tube.laneWidth * view.rimScale);
  }
}
