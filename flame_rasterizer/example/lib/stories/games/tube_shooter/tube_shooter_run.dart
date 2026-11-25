part of 'tube_shooter_example.dart';

/// A prototype of a run between two rounds, with [TubeShooterExample.runs]
/// on: after a closed tube's drop, the ship flies on down an endless tube,
/// as in Tube Runner, then out of it, onto the next round's rim.
///
/// Its distances are along the run's axis, in tube units, from the rim of
/// the round's tube, which leads straight into the run's: the drop is the
/// first [Tube.depth] of the run. The drop speeds up to Tube Runner's
/// [flightSpeed] by its end, as [dropDepth] says, and the ship flies on as
/// fast, moving round the tube as in play, for [TubeShooterExample.runTime].
/// Its tube eases into Tube Runner's bends past the drop, and out of them by
/// the end of the run, then goes straight on to its [exit]. The ship slows
/// down from there to a stop on the next round's rim, [rim] along the axis,
/// over [TubeShooterExample.arriveTime].
///
/// [EndlessTube] draws the run's tube past the round's far end, which grows
/// from there to the full length ahead on the drop, and the next round's
/// tube, as its walls hide it. The round's tube draws itself on, as the eye
/// leaves it behind. The ship's lane fades in on the run, as it shows in
/// play. Once the ship is out of the run's tube, it glides onto the next
/// round's tube, at the step nearest its angle round the axis.
class _Run(
  /// The round's tube, and its colour.
  final Tube tube,
  final Color color,

  /// The next round's level.
  final Level next,
) {
  static const flightSpeed = TubeRunnerExample.flightSpeed;

  /// Where the run's bends end: as far along as the ship flies on the drop
  /// and the run.
  static const playEnd = Tube.depth + flightSpeed * TubeShooterExample.runTime;

  /// Where the next round's rim is: as far past [playEnd] as the ship flies
  /// while it slows down evenly from [flightSpeed] to a stop.
  static const rim = playEnd + flightSpeed * TubeShooterExample.arriveTime / 2;

  /// Where the run's tube ends, with a ring across: on a ring, and far
  /// enough before [rim] to be behind the eye once the ship is there.
  static final exit = math.max(
    playEnd,
    (rim - Tube.eye - TubeView.near - EndlessTube.step).floorToDouble(),
  );

  /// How far the ship has dropped at [progress] of the drop: from a stop,
  /// speeding up to [flightSpeed] at its end.
  static double dropDepth(double progress) =>
      Tube.depth *
      math
          .pow(
            progress,
            flightSpeed * TubeShooterExample.dropTime / Tube.depth,
          )
          .toDouble();

  /// Returns [t], from 0 to 1, eased in and out, as [EndlessTube]'s course
  /// eases its bends.
  static double eased(double t) => t * t * t * (t * (6 * t - 15) + 10);

  late final endless = EndlessTube(
    course: (
      bendFrom: Tube.depth,
      bendTo: playEnd,
      ease: TubeShooterExample.runEase,
    ),
  );

  /// The view that [endless] draws the run's tube for: the game's, but for
  /// its tube, which is the next round's once the ship arrives.
  late final view = TubeView()..tube = tube;

  /// How far along the run the ship is.
  double flown = 0;

  /// The components that draw the run's tube, the ship's lane and the next
  /// round's tube.
  PositionComponent? tubeDrawing;
  PositionComponent? laneDrawing;
  PositionComponent? nextDrawing;

  /// Where the ship was in the world, its angle and its scale, as it began
  /// to arrive.
  Vector2? shipFrom;
  double angleFrom = 0;
  Vector2? scaleFrom;

  /// Removes its drawings.
  void clear() {
    for (final drawing in [tubeDrawing, laneDrawing, nextDrawing]) {
      drawing?.removeFromParent();
    }
    tubeDrawing = laneDrawing = nextDrawing = null;
  }

  /// Returns the step round [to] nearest the angle round the axis of [step]
  /// round [from], as Tube Runner's ship moves onto a new tube.
  static int nearestStep(Tube from, int step, Tube to) {
    final angle = _pointAt(from, step).direction;
    var nearest = 0;
    var least = double.infinity;
    for (var i = 0; i < PlayerComponent.stepsPerLane * to.laneCount; i++) {
      final turn =
          (_pointAt(to, i).direction - angle + math.pi) % (2 * math.pi);
      final off = (turn - math.pi).abs();
      if (off < least) {
        nearest = i;
        least = off;
      }
    }
    return nearest;
  }

  /// Returns where [step] is on [tube]'s outline, in tube units.
  static Offset _pointAt(Tube tube, int step) {
    const stepsPerLane = PlayerComponent.stepsPerLane;
    final lane = step ~/ stepsPerLane;
    return Offset.lerp(
      tube.points[lane],
      tube.points[tube.pointAfter(lane)],
      (step % stepsPerLane + 0.5) / stepsPerLane,
    )!;
  }
}

/// The runs, with [TubeShooterExample.runs] on: see [_Run].
extension on TubeShooterExample {
  /// Starts the run, the drop's overshoot into it.
  void _beginRun() {
    final over = _stateTime - TubeShooterExample.dropTime;
    _setState(TubeState.run);
    _stateTime = over;
    _stepRun();
  }

  /// Flies the ship down the run, and once the run is over, starts the next
  /// round as it arrives.
  void _stepRun() {
    final run = _run!;
    run.flown = Tube.depth + _Run.flightSpeed * _stateTime;
    // The round's tube goes on behind the eye.
    player.depth = view.eyeShift = run.flown;
    if (_stateTime >= TubeShooterExample.runTime) {
      _beginArrive();
    }
  }

  /// Starts the next round as the ship arrives on its rim, the run's
  /// overshoot into the arrival.
  void _beginArrive() {
    final run = _run!;
    final over = _stateTime - TubeShooterExample.runTime;
    run
      ..shipFrom = player.position.clone()
      ..angleFrom = player.angle
      ..scaleFrom = player.scale.clone();
    _nextRound(arriving: true);
    _stateTime = over;
    _stepArrive();
  }

  /// Slows the ship down evenly to a stop on the next round's rim, as the
  /// camera turns to look where the round's does, and then waits for the
  /// player, as at the end of a zoom.
  void _stepArrive() {
    final run = _run!;
    const time = TubeShooterExample.arriveTime;
    final progress = math.min(1.0, _stateTime / time);
    run.flown =
        _Run.playEnd +
        _Run.flightSpeed * time * (progress - progress * progress / 2);
    player.depth = view.eyeShift = progress == 1 ? 0 : run.flown - _Run.rim;
    _look = Offset.lerp(
      _lookFrom,
      view.tube.center,
      _Run.eased(progress),
    )!;
    if (progress == 1) {
      _endRun();
      _roundBanner.removeFromParent();
      _purgeReadyText.removeFromParent();
      _waitForPlayer();
    }
  }

  /// Ends the run, if any, and removes its drawings.
  void _endRun() {
    _run?.clear();
    _run = null;
  }

  /// The run's time so far, as Tube Runner shows its time in the tube.
  String get _runClock {
    final seconds = math.max(0, _stateTime).floor();
    return 'TIME ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// Draws the run's tube, if there's a run: the ship's lane in its colour,
  /// fading in, while the ship can move, and the next round's tube, once
  /// it's no farther ahead than the run's tube goes.
  void _drawRun() {
    final run = _run;
    if (run == null || !isLoaded) {
      return;
    }
    run.view.fit(2 * view.rimScale, view.devicePixel);
    final distance = run.flown;
    run.endless.advanceTo(distance);
    final dropping = _state == TubeState.drop;
    final arriving = _state == TubeState.arrive;
    final until = dropping
        ? Tube.depth +
              EndlessTube.ahead *
                  math.min(1.0, _stateTime / TubeShooterExample.dropTime)
        : _Run.exit;
    final nextColor = arriving ? level.color : run.next.color;
    final quads = run.endless.quadsAt(
      distance,
      run.view,
      lane: canMove ? player.lane : null,
      from: Tube.depth,
      until: math.min(until, _Run.exit),
      next: _Run.rim - distance <= EndlessTube.ahead
          ? (tube: arriving ? view.tube : run.next.tube, rim: _Run.rim)
          : null,
    );
    final glow = _glow && rendererGlows ? TubeShooterExample.tubeGlow : null;
    PositionComponent? replace(
      PositionComponent? old,
      RasterizerPolygons quads,
      Color color, {
      int? priority,
    }) {
      old?.removeFromParent();
      if (quads.bounds.isEmpty) {
        return null;
      }
      countPath();
      final component = quadsComponent(
        quads,
        color,
        priority: priority,
        glow: glow,
      );
      tubeGroup.add(component);
      return component;
    }

    final fade = math.min(1.0, _stateTime / TubeShooterExample.laneFadeTime);
    run
      ..tubeDrawing = replace(run.tubeDrawing, quads.tube, run.color)
      ..laneDrawing = replace(
        run.laneDrawing,
        quads.lane,
        Color.lerp(run.color, TubeColors.ship, fade)!,
        priority: 1,
      )
      ..nextDrawing = replace(run.nextDrawing, quads.next, nextColor);
  }

  /// Places the ship as it arrives: where it was as the run ended, until it
  /// leaves the run's tube, then gliding onto the rim, to where it's placed
  /// there.
  void _placeArriving() {
    final run = _run;
    final from = run?.shipFrom;
    if (_state != TubeState.arrive || run == null || from == null) {
      return;
    }
    final glide = _Run.eased(
      ((run.flown - _Run.exit) / (_Run.rim - _Run.exit)).clamp(0.0, 1.0),
    );
    var turn = (player.angle - run.angleFrom) % (2 * math.pi);
    if (turn > math.pi) {
      turn -= 2 * math.pi;
    }
    player
      ..position.setFrom(from + (player.position - from) * glide)
      ..angle = run.angleFrom + turn * glide
      ..scale.setFrom(run.scaleFrom! + (player.scale - run.scaleFrom!) * glide);
  }
}
