import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// What the ship resumes from when the game switches to another renderer:
/// its step and the fraction of a step past it, whether it's visible, and how
/// far it has faded out.
typedef ShipSnapshot = ({
  int step,
  double partStep,
  bool isVisible,
  double opacity,
});

/// The ship, which moves round the tube's ring at the ship as Tube Shooter's
/// ship moves round the rim: see [PlayerComponent], whose numbers it shares.
///
/// The eye looks at that ring as Tube Shooter's eye looks at the rim, so the
/// ship shows where Tube Shooter's ship does on screen. It moves only while
/// the game is on, and fades out when destroyed.
///
/// Given [from], it resumes from that snapshot. Keys held down before don't
/// move it, as the new game hasn't seen them go down.
class ShipComponent({final ShipSnapshot? from})
    extends PositionComponent
    with HasGameRef<TubeHost>, HasVisibility {
  this : super(priority: 4);

  static const stepsPerLane = PlayerComponent.stepsPerLane;

  late int step =
      from?.step ??
      gameRef.view.tube.bottomLane * stepsPerLane + PlayerComponent.startStep;

  /// The fraction of a step it has moved, short of a whole step.
  double _partStep = from?.partStep ?? 0;

  /// How long a key has moved it without stopping.
  double _keyTime = 0;

  /// The component that draws its shape.
  late final PathComponent drawing;

  int get lane => step ~/ stepsPerLane;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.ship, TubeColors.ship));
    if (from case final from?) {
      isVisible = from.isVisible;
      if (from.opacity < 1) {
        fadeOut(from: from.opacity);
      }
    }
    place();
  }

  /// What a game with another renderer resumes from.
  ShipSnapshot get snapshot => (
    step: step,
    partStep: _partStep,
    isVisible: isVisible,
    opacity: isLoaded ? drawing.opacity : 1,
  );

  /// Moves it [lanes] round the tube, in whole steps, stopping at an open
  /// tube's ends, as [PlayerComponent.moveBy] does.
  void moveBy(double lanes) {
    final moved = _partStep + lanes * stepsPerLane;
    final whole = moved.truncate();
    _partStep = moved - whole;
    final tube = gameRef.view.tube;
    final steps = stepsPerLane * tube.laneCount;
    step = tube.isOpen
        ? (step + whole).clamp(0, steps - 1)
        : (step + whole) % steps;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final direction = gameRef.canMove ? gameRef.keyDirection : 0;
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

  /// Fades it out over [PlayerComponent.fadeTime], as Tube Shooter's ship
  /// does when destroyed. Starting [from] a lower opacity, it fades out over
  /// the time that is left.
  void fadeOut({double from = 1}) {
    drawing.opacity = from;
    if (from > 0) {
      drawing.add(
        OpacityEffect.fadeOut(
          EffectController(duration: PlayerComponent.fadeTime * from),
        ),
      );
    }
  }

  /// Shows it again, fully opaque, after [fadeOut].
  void revive() {
    isVisible = true;
    drawing
      ..removeAll(drawing.children.whereType<OpacityEffect>().toList())
      ..opacity = 1;
  }

  /// Moves it onto the view's tube and places it there, on the step nearest
  /// the angle round the axis that it had on [from], its previous tube.
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
