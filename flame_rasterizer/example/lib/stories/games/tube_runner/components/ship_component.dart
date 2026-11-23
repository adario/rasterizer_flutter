import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

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

  /// Moves it onto the view's tube, to the step nearest the angle round the
  /// axis at which it was on [from], its tube before, and places it there.
  void switchFrom(Tube from) {
    final angle = _pointAt(from, step).direction;
    final tube = gameRef.view.tube;
    var nearest = 0;
    var least = double.infinity;
    for (var i = 0; i < stepsPerLane * tube.laneCount; i++) {
      final turn =
          (_pointAt(tube, i).direction - angle + math.pi) % (2 * math.pi);
      final off = (turn - math.pi).abs();
      if (off < least) {
        nearest = i;
        least = off;
      }
    }
    step = nearest;
    _partStep = 0;
    place();
  }

  /// Places it on the ring at the ship, at the angle of
  /// [PlayerComponent.headingOn].
  void place() {
    final view = gameRef.view;
    final tube = view.tube;
    final at = _pointAt(tube, step) * view.rimScale;
    position.setValues(at.dx, at.dy);
    angle = PlayerComponent.headingOn(tube, step);
    scale.splat(tube.laneWidth * view.rimScale);
  }

  /// Returns where [step] is on [tube]'s outline, in tube units.
  static Offset _pointAt(Tube tube, int step) {
    final lane = step ~/ stepsPerLane;
    return Offset.lerp(
      tube.points[lane],
      tube.points[tube.pointAfter(lane)],
      (step % stepsPerLane + 0.5) / stepsPerLane,
    )!;
  }
}
