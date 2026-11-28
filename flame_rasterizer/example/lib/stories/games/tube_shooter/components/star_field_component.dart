import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_glow.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// The stars around the tube, never inside it.
///
/// [TubeHost.starCount] stars lie [radii] from the axis through the
/// viewport's centre, and up to [far] from the eye, in tube units (see
/// [StarComponent]). Each frame, they come closer by as much as the eye went
/// deeper, so during the zoom and the drop they stream outward as streaks. A
/// star that passes the tube's near plane goes back to the farthest distance
/// and shows up somewhere else as a dot.
///
/// The stars always come at least at a drift speed: [cruise] at the round's
/// pace, plus [killSpeedUp] for each of [ShooterMode.kills]. While the eye
/// moves slower than that, the stars come at the drift speed with short
/// streaks, and a star that's wholly off screen also goes back.
///
/// During play, as the ship moves round the tube, the stars turn about the
/// axis the other way, easing in over about [turnLag]. Round a closed tube,
/// they turn by an equal share of a full turn for each lane. Along an open
/// tube, they turn as much as the ship's heading does, so not at all along a
/// straight part. On a run, they turn toward the run's bends instead, as Tube
/// Runner's stars do (see [bendTurnOver]). Nearer stars turn more, for
/// parallax: each star scales a base turn, the turn of a star that turns as
/// much as the ship, by its distance (see [turnRatio]). Only their places
/// across the axis turn, not their distances from the eye.
///
/// Stars are invisible at the farthest distance and fully bright from
/// [bright] inward. [show] fades them in over [fadeTime]. When
/// [TubeHost.starCount] changes, stars are removed or added at once, the new
/// ones at random distances, as at the start.
///
/// It sits in the camera's backdrop, under the world, so that the camera's
/// post process (the Glow knob's [TubeGlow]) leaves the stars out. Even so, it
/// draws through the viewfinder's transform and updates at the world's time
/// scale, as if it were in the world.
class StarFieldComponent(
  /// The mode whose ship the stars turn with, and whose pace they follow.
  final ShooterMode shooter,
) extends Component with HasGameRef<TubeHost>, CustomTraversal {
  static const far = 10.0;
  static const bright = 4.0;
  static const radii = (inner: 1.2, outer: 5.0);
  static const fadeTime = 0.3;

  /// The slowest speed at which the stars come in the first round, in tube
  /// units a second: 5% more than a tenth of the eye's top speed on the drop.
  /// Later rounds speed it up along with the rest of the game.
  static const cruise = 1.05 * 0.1 * 2 * Tube.depth / ShooterMode.dropTime;

  /// How much faster the stars come for each enemy that the ship has
  /// destroyed in the round since it was last lost, as a fraction of [cruise]
  /// at the round's pace.
  static const killSpeedUp = 0.025;

  /// How much a star at [bright] from the eye turns for each turn of the
  /// ship, either round a closed tube or in its heading along an open one.
  ///
  /// A star turns by the base turn times this ratio times [bright] over its
  /// distance from the eye, so nearer stars turn more. Their movement on
  /// screen, both sideways and outward, then grows with the inverse square of
  /// their distance.
  static const turnRatio = 0.5;

  /// How long the stars take to close most of the gap to their target turn,
  /// in seconds. In each [turnLag], they close about two thirds of the gap
  /// that's left.
  static const turnLag = 0.2;

  /// How far ahead of the ship the stars look for an [EndlessTube]'s bends,
  /// in tube units: see [bendTurnOver].
  static const bendAhead = 8.0;

  /// The base turn for each tube unit that the ship flies, where the tube
  /// [bendAhead] ahead points wholly sideways (see [bendTurnOver]).
  static const bendTurn = 0.4;

  /// Returns the base turn, clockwise on screen, as the ship flies [closer]
  /// along [tube] from [flown] along it.
  ///
  /// The stars turn toward the side that the tube bends to [bendAhead] ahead,
  /// by [bendTurn] times how far the tube's direction there points to that
  /// side. So they turn faster where the tube bends more, and not at all
  /// where it goes straight on or bends only up or down.
  static double bendTurnOver(EndlessTube tube, double flown, double closer) =>
      bendTurn * tube.bendAt(flown, bendAhead) * closer;

  /// The stars, while they're shown or fading out.
  final stars = <StarComponent>[];

  bool _shown = false;

  /// How faded in they are, from 0 to 1.
  double _fade = 0;

  /// The view's eye shift at the last update.
  double _eyeShift = 0;

  /// The base turn that the stars ease toward, and the base turn they have
  /// made so far, clockwise on screen.
  double _turnTarget = 0;
  double _turned = 0;

  /// The ship's step at the last update, and its tube.
  int _step = 0;
  Tube? _tube;

  /// The base turn for each lane that the ship moves round [_tube], if it's
  /// closed.
  double _turnPerLane = 0;

  /// Shows the stars, fading them in, or at once while the world is paused.
  void show() {
    if (_shown) {
      return;
    }
    _shown = true;
    _fade = gameRef.world.timeScale == 0 ? 1 : 0;
    _eyeShift = gameRef.view.eyeShift;
    // The first update only notes where the ship is.
    _tube = null;
    _turnTarget = _turned;
    _matchCount();
  }

  /// Follows a change of [by] in the view's eye shift that doesn't move the
  /// eye, such as when the tube that the eye shift counts from changes after
  /// a run.
  void shiftEye(double by) => _eyeShift += by;

  /// Adds or removes stars so that there are [TubeHost.starCount]. It removes
  /// the last ones and adds new ones at random distances.
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
  StarComponent _star() {
    final distance =
        TubeView.near + (far - TubeView.near) * gameRef.random.nextDouble();
    return StarComponent(_point(), distance)
      ..brightness = _brightnessAt(distance);
  }

  /// Returns how bright a star [distance] from the eye is, given the fade.
  double _brightnessAt(double distance) =>
      _fade * ((far - distance) / (far - bright)).clamp(0.0, 1.0);

  /// Returns a random place across the axis for a star, spread evenly over the
  /// area.
  Offset _point() {
    final random = gameRef.random;
    final (:inner, :outer) = radii;
    final radius = math.sqrt(
      inner * inner + (outer * outer - inner * inner) * random.nextDouble(),
    );
    return Offset.fromDirection(2 * math.pi * random.nextDouble(), radius);
  }

  /// Follows the ship's moves round the rim during play, and returns the base
  /// turn over [dt] seconds, clockwise on screen.
  ///
  /// On a run, the stars turn toward the bends instead, as the ship flies
  /// [deeper].
  double _turn(double dt, double deeper) {
    final tube = gameRef.view.tube;
    final step = shooter.player.step;
    final runner = shooter.state == TubeState.run ? shooter.runner : null;
    final turns = shooter.state == TubeState.play;
    if (!identical(tube, _tube)) {
      _tube = tube;
      _turnPerLane = _turnPerLaneOn(tube);
    } else if (turns && tube.isOpen) {
      _turnTarget -=
          PlayerComponent.headingOn(tube, step) -
          PlayerComponent.headingOn(tube, _step);
    } else if (turns) {
      const stepsPerLane = PlayerComponent.stepsPerLane;
      final steps = stepsPerLane * tube.laneCount;
      var moved = step - _step;
      // The short way round, across the step where the lanes start again.
      moved -= steps * (moved / steps).round();
      _turnTarget += moved / stepsPerLane * _turnPerLane;
    }
    _step = step;
    final turned = _turned;
    _turned += (_turnTarget - _turned) * (1 - math.exp(-dt / turnLag));
    // The runner makes the run's rings once it's loaded.
    final bend = runner != null && runner.isLoaded && deeper > 0
        ? bendTurnOver(runner.endlessTube, runner.flown, deeper)
        : 0.0;
    return _turned - turned + bend;
  }

  /// Returns the base turn for each lane that the ship moves round closed
  /// [tube], against the direction its lanes go round the axis.
  static double _turnPerLaneOn(Tube tube) {
    var sweep = 0.0;
    for (var lane = 0; lane < tube.laneCount; lane++) {
      final from = tube.points[lane].direction;
      final to = tube.points[tube.pointAfter(lane)].direction;
      var angle = to - from;
      angle -= 2 * math.pi * (angle / (2 * math.pi)).roundToDouble();
      sweep += angle;
    }
    return -sweep.sign * 2 * math.pi / tube.laneCount;
  }

  /// Moves [star] to a new place, [distance] from the eye, as a dot with no
  /// streak.
  void _renew(StarComponent star, double distance) => star
    ..eyeDistance = distance
    ..cameFrom = distance
    ..point = _point();

  /// Updates it and the stars at the world's time scale, as the world updates
  /// its components, so not at all while the world is paused. Even then, it
  /// adds or removes stars when [TubeHost.starCount] changes.
  @override
  void updateSubtree(double dt) {
    if (_shown) {
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
    if (stars.isEmpty) {
      return;
    }
    _fade = math.min(1, _fade + dt / fadeTime);
    // The eye only goes deeper, except at the cut from a drop to the next
    // zoom, where it jumps back. The stars then come at the drift speed.
    final view = gameRef.view;
    final eyeShift = view.eyeShift;
    final deeper = eyeShift - _eyeShift;
    _eyeShift = eyeShift;
    final drift =
        cruise * shooter.pace * (1 + killSpeedUp * shooter.kills) * dt;
    final isSlow = deeper <= drift;
    final closer = isSlow ? drift : deeper;
    // The screen round the viewport's centre, as the stars lie, grown by the
    // farthest a star reaches from its middle: half the longest slow streak,
    // which is centred on the star.
    final camera = gameRef.camera;
    final screen = camera.visibleWorldRect
        .shift(-camera.viewfinder.position.toOffset())
        .inflate(
          StarComponent.widthScale * TubeView.rimPixels * view.devicePixel +
              StarComponent.slowLength / camera.viewfinder.zoom / 2,
        );
    final turn = _turn(dt, deeper);
    for (final star in stars) {
      star
        ..cameFrom = star.eyeDistance
        ..eyeDistance -= closer
        ..isSlow = isSlow;
      if (isSlow &&
          !screen.contains(star.point * view.scaleOf(star.eyeDistance))) {
        _renew(star, far);
      }
      while (star.eyeDistance < TubeView.near) {
        _renew(star, star.eyeDistance + far - TubeView.near);
      }
      // Past the near plane, so never too close to the eye.
      if (turn != 0) {
        final ratio = turnRatio * bright / star.eyeDistance;
        star.point = Tube.rotate(star.point, turn * ratio);
      }
      star.brightness = _brightnessAt(star.eyeDistance);
    }
  }
}
