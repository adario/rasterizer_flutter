import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// What the ship in a game for another renderer goes on from: its step and
/// the fraction of a step past it, its depth, the seconds since its last
/// shot, whether it's visible, and how faded out it is.
typedef PlayerSnapshot = ({
  int step,
  double partStep,
  double depth,
  double sinceShot,
  bool isVisible,
  double opacity,
});

/// The ship, which moves round the rim and fires down its lane.
///
/// It moves round the tube in [stepsPerLane] steps a lane. While firing, it
/// fires a shot every [firePeriod] seconds, with at most [maxShots] in the
/// tube. Its [depth] is the rim's, 0, except while it drops down its lane.
///
/// Given [from], it goes on from there. The keys and the drags, which the new
/// game hasn't seen go down, don't move it or fire.
class PlayerComponent({final PlayerSnapshot? from})
    extends PositionComponent
    with HasGameRef<TubeHost>, InShooterMode, HasVisibility {
  this : super(priority: 4);

  static const stepsPerLane = 16;
  // Long enough that a held key's sweep at top speed doesn't put a shot in
  // every lane.
  static const firePeriod = 0.15;
  static const maxShots = 8;

  /// Its speed while a key is held, in lanes a second: at first, and at most.
  static const keySpeed = (first: 3.0, most: 10.0);

  /// How fast a held key speeds it up to its top [keySpeed], in lanes a
  /// second per second.
  static const keyAcceleration = 14.0;

  /// Where it starts in its lane: the middle.
  static const startStep = stepsPerLane ~/ 2;

  /// Seconds it takes to fade out once destroyed.
  static const fadeTime = TubeHost.respawnTime * 2 / 3;

  int step = startStep;
  double depth = 0;

  /// The fraction of a step it has moved, short of a whole step.
  double _partStep = 0;

  /// How long a key has moved it without a stop.
  double _keyTime = 0;

  double _sinceShot = firePeriod;
  bool _firing = false;

  /// The component that draws its shape.
  late final PathComponent drawing;

  int get lane => step ~/ stepsPerLane;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.ship, TubeColors.ship));
    if (from case final from?) {
      step = from.step;
      _partStep = from.partStep;
      depth = from.depth;
      _sinceShot = from.sinceShot;
      isVisible = from.isVisible;
      if (from.opacity < 1) {
        fadeOut(from: from.opacity);
      }
    }
    place();
  }

  /// What a game with another renderer goes on from.
  PlayerSnapshot get snapshot => (
    step: step,
    partStep: _partStep,
    depth: depth,
    sinceShot: _sinceShot,
    isVisible: isVisible,
    opacity: isLoaded ? drawing.opacity : 1,
  );

  /// Fades it out over [fadeTime], or, [from] an opacity, over the time
  /// left.
  void fadeOut({double from = 1}) {
    drawing.opacity = from;
    if (from > 0) {
      drawing.add(
        OpacityEffect.fadeOut(EffectController(duration: fadeTime * from)),
      );
    }
  }

  /// Moves it [lanes] round the tube, in whole steps, stopping at an open
  /// tube's ends.
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

  /// Puts it on [tube]'s bottom lane.
  void startOn(Tube tube) {
    step = tube.bottomLane * stepsPerLane + startStep;
    _partStep = 0;
  }

  void beginFire() => _firing = true;

  void stopFire() => _firing = false;

  @override
  void update(double dt) {
    super.update(dt);
    final direction = gameRef.keyDirection;
    if (direction != 0 && gameRef.canMove) {
      _keyTime += dt;
      final (:first, :most) = keySpeed;
      final speed = math.min(most, first + keyAcceleration * _keyTime);
      moveBy(direction * speed * dt);
    } else {
      _keyTime = 0;
    }
    _sinceShot += dt;
    if (_firing &&
        _sinceShot >= firePeriod &&
        shooter.canFire &&
        shooter.shots.length < maxShots) {
      _sinceShot = 0;
      shooter.fire(lane, depth);
    }
    place();
    gameRef.keepStroke(drawing);
  }

  /// Returns its angle at [step] round [tube], unwound as [Tube.headingAt].
  static double headingOn(Tube tube, int step) => tube.headingAt(
    step ~/ stepsPerLane,
    (step % stepsPerLane + 0.5) / stepsPerLane,
  );

  /// Places it on the rim, or as far down its lane as it has dropped, at the
  /// angle of [headingOn].
  void place() {
    final view = gameRef.view;
    final tube = view.tube;
    final scale = view.scaleAt(depth);
    final lane = this.lane;
    final along = (step % stepsPerLane + 0.5) / stepsPerLane;
    final at =
        Offset.lerp(
          tube.points[lane],
          tube.points[tube.pointAfter(lane)],
          along,
        )! *
        scale;
    position.setValues(at.dx, at.dy);
    angle = headingOn(tube, step);
    this.scale.splat(tube.laneWidth * scale);
  }

  /// Brings it back at the rim, clearing its fade out from when it was
  /// destroyed.
  void revive() {
    depth = 0;
    if (isLoaded) {
      drawing.opacity = 1;
    }
  }
}
