import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// The stars around the tube, never inside it.
///
/// [count] stars lie [radii] from the axis through the viewport's centre,
/// and up to [far] from the eye, in tube units: see [StarComponent]. Each
/// frame, they come closer by as much as the eye went deeper, so on the zoom
/// and the drop they stream outward as streaks. A star that passes the
/// tube's near plane goes back to the farthest distance, as a dot somewhere
/// else.
///
/// While the eye goes slower than [cruise], at the round's pace, the stars
/// come at that speed instead, with short streaks, and a star wholly off
/// screen goes back too.
///
/// In play, as the ship moves round the rim, the stars turn about the axis the
/// other way, easing in over about [turnLag]. Nearer stars turn more, as with
/// parallax: see [turnRatio]. Their places turn, not their distances from the
/// eye.
/// Stars are unseen at the farthest, and at their brightest from [bright] in.
/// [show] fades them in over [fadeTime], and [hide] fades them out, then
/// removes them.
class StarFieldComponent()
    extends Component
    with HasGameRef<TubeShooterExample> {
  this : super(priority: -1);

  static const count = 200;
  static const far = 10.0;
  static const bright = 4.0;
  static const radii = (1.2, 5.0);
  static const fadeTime = 0.3;

  /// The slowest the stars come in the first round, in tube units a second: a
  /// tenth of the eye's top speed on the drop. Later rounds speed it up, as
  /// they do the game.
  static const cruise = 0.1 * 2 * Tube.depth / TubeShooterExample.dropTime;

  /// How much a star [bright] from the eye turns for each turn of the ship
  /// round a closed tube. On any tube, a lane turns it by this much of a
  /// closed tube's lane.
  ///
  /// A star's turn is this times [bright] over its distance from the eye, so
  /// nearer stars turn more. Their moves on screen, sideways as outward, then
  /// both grow as the square of how near they are.
  static const turnRatio = 0.5;

  /// How long the stars take to close most of the gap to their turn, in
  /// seconds: about two thirds of it, then two thirds of the rest, and so on.
  static const turnLag = 0.2;

  /// The stars, while they're shown or fading out.
  final stars = <StarComponent>[];

  bool _shown = false;

  /// How faded in they are, from 0 to 1.
  double _fade = 0;

  /// The view's eye shift at the last update.
  double _eyeShift = 0;

  /// The angle the stars turn toward, and the angle they have turned so far,
  /// clockwise on screen, for a star that turns as much as the ship.
  double _turnTarget = 0;
  double _turned = 0;

  /// The ship's step at the last update, and its tube.
  int _step = 0;
  Tube? _tube;

  /// How far a star that turns as much as the ship turns for each lane that
  /// the ship moves along [_tube].
  double _turnPerLane = 0;

  /// Shows the stars, fading them in, or at once in a still world.
  ///
  /// Stars that are fading out fade in again.
  void show() {
    _shown = true;
    if (stars.isNotEmpty) {
      return;
    }
    _fade = gameRef.world.timeScale == 0 ? 1 : 0;
    _eyeShift = gameRef.view.eyeShift;
    // The first update only notes where the ship is.
    _tube = null;
    _turnTarget = _turned;
    for (var i = 0; i < count; i++) {
      final distance =
          TubeView.near + (far - TubeView.near) * gameRef.random.nextDouble();
      stars.add(
        StarComponent(_point(), distance)..brightness = _brightnessAt(distance),
      );
    }
    addAll(stars);
  }

  /// Hides the stars, fading them out.
  void hide() => _shown = false;

  /// Removes the stars at once.
  void stop() {
    _shown = false;
    removeAll(stars);
    stars.clear();
  }

  /// How bright a star [distance] from the eye is, given the fade.
  double _brightnessAt(double distance) =>
      _fade * ((far - distance) / (far - bright)).clamp(0.0, 1.0);

  /// A random place across the axis for a star, spread evenly over the area.
  Offset _point() {
    final random = gameRef.random;
    final (inner, outer) = radii;
    final radius = math.sqrt(
      inner * inner + (outer * outer - inner * inner) * random.nextDouble(),
    );
    return Offset.fromDirection(2 * math.pi * random.nextDouble(), radius);
  }

  /// Follows the ship's moves round the rim in play, and returns the angle by
  /// which a star that turns as much as the ship turns over [dt] seconds,
  /// clockwise on screen.
  double _turn(double dt) {
    final tube = gameRef.view.tube;
    final step = gameRef.player.step;
    if (!identical(tube, _tube)) {
      _tube = tube;
      _turnPerLane = _turnPerLaneOn(tube);
    } else if (gameRef.state == TubeState.play) {
      const stepsPerLane = PlayerComponent.stepsPerLane;
      final steps = stepsPerLane * tube.laneCount;
      var moved = step - _step;
      if (!tube.isOpen) {
        // The short way round, across the step where the lanes start again.
        moved -= steps * (moved / steps).round();
      }
      _turnTarget += moved / stepsPerLane * _turnPerLane;
    }
    _step = step;
    final turned = _turned;
    _turned += (_turnTarget - _turned) * (1 - math.exp(-dt / turnLag));
    return _turned - turned;
  }

  /// How far a star that turns as much as the ship turns for each lane that
  /// the ship moves along [tube]: against the way its lanes go round the
  /// axis.
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

  @override
  void update(double dt) {
    super.update(dt);
    if (stars.isEmpty) {
      return;
    }
    _fade = (_fade + (_shown ? dt : -dt) / fadeTime).clamp(0.0, 1.0);
    if (_fade == 0 && !_shown) {
      stop();
      return;
    }
    // The eye only goes deeper, but for the cut from a drop to the next zoom,
    // where it jumps back: the stars then come at the cruise speed.
    final view = gameRef.view;
    final eyeShift = view.eyeShift;
    final deeper = eyeShift - _eyeShift;
    _eyeShift = eyeShift;
    final drift = cruise * gameRef.pace * dt;
    final isSlow = deeper <= drift;
    final closer = isSlow ? drift : deeper;
    // Round the viewport's centre, as the stars lie, and larger by the widest
    // a star can be: half the longest slow streak, which is centred on the
    // star.
    final camera = gameRef.camera;
    final screen = camera.visibleWorldRect
        .shift(-camera.viewfinder.position.toOffset())
        .inflate(
          StarComponent.widthScale * TubeView.rimPixels * view.devicePixel +
              StarComponent.slowLength / camera.viewfinder.zoom / 2,
        );
    final turn = _turn(dt);
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
