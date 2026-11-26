part of 'shooter_mode.dart';

/// A run between two rounds, with [ShooterMode.runs] on: after the round's
/// drop, the ship flies on down an endless tube, by Tube Runner's rules,
/// then out of it, onto the next round's rim. The camera keeps looking where
/// the round's does, then turns, on the arrival, to look where the next
/// round's does.
///
/// Its distances are along the run's axis, in tube units, from the rim of
/// the round's tube, which leads straight into the run's: the drop is the
/// first [Tube.depth] of the run. The drop speeds up to Tube Runner's
/// [flightSpeed] by its end, as [dropDepth] says. There, [runner] takes over
/// the ship, where it is, and the run's tube: the ship flies on, as far as
/// it would in [ShooterMode.runTime] of play at [flightSpeed], as enemies
/// come, and faster for each it destroys. Its tube eases into Tube Runner's
/// bends past the drop, and out of them by the end of the run's play, then
/// goes straight on to its [exit]. The round's rules take over again there,
/// and the ship slows down evenly to a stop on the next round's rim, [rim]
/// along the axis, as far as it would in [ShooterMode.arriveTime] from
/// [flightSpeed].
///
/// [EndlessTube] draws the run's tube past the round's far end, which grows
/// from there to the full length ahead on the drop, and the next round's
/// tube, as its walls hide it. The round's tube draws itself on, as the eye
/// leaves it behind. Once the ship is out of the run's tube, it glides onto
/// the next round's tube, at the step nearest its angle round the axis.
class _Run(
  /// The round's tube, and its colour.
  final Tube tube,
  final Color color,

  /// The next round's level.
  final Level next, {

  /// How fast the runner's ship flies at first, in tube units a second.
  required final double flightSpeed,

  /// The enemies that come on the run, in order: the round's, as they came.
  required final List<EnemyKind> sequence,

  /// The snapshot of the runner of a game with another renderer that the
  /// run goes on from, if any.
  final RunnerSnapshot? from,
}) {
  /// Where the run's bends end, where the next round's rim is, and where
  /// the run's tube ends: endless, until the runner sets them with [endAt].
  double playEnd = double.infinity;
  double rim = double.infinity;
  double exit = double.infinity;

  /// Sets [playEnd], and from it [rim], as far past as the ship flies while
  /// it slows down evenly from [flightSpeed] to a stop over
  /// [ShooterMode.arriveTime], and [exit], on a ring, far enough before
  /// [rim] to be behind the eye once the ship is there. Returns [exit] and
  /// [rim].
  ({double exit, double rim}) endAt(double playEnd) {
    this.playEnd = playEnd;
    rim = playEnd + flightSpeed * ShooterMode.arriveTime / 2;
    exit = math.max(
      playEnd,
      (rim - Tube.eye - TubeView.near - EndlessTube.step).floorToDouble(),
    );
    endless.course = (
      bendFrom: Tube.depth,
      bendTo: playEnd,
      ease: ShooterMode.runEase,
    );
    return (exit: exit, rim: rim);
  }

  /// How far the ship has dropped at [progress] of the drop: from a stop,
  /// speeding up, and flying at [flightSpeed] at its end. If that's too slow
  /// to drop [Tube.depth] in [ShooterMode.dropTime], it flies faster on the
  /// way, then slows down to it.
  double dropDepth(double progress) {
    final p = progress;
    final end = flightSpeed * ShooterMode.dropTime;
    return Tube.depth * p * p * (3 - 2 * p) + end * p * p * (p - 1);
  }

  /// Returns [t], from 0 to 1, eased in and out, as [EndlessTube]'s course
  /// eases its bends.
  static double eased(double t) => t * t * t * (t * (6 * t - 15) + 10);

  late final endless = EndlessTube(
    course: (
      bendFrom: Tube.depth,
      bendTo: double.infinity,
      ease: ShooterMode.runEase,
    ),
  );

  /// The view that [endless] draws the run's tube for on the drop and the
  /// arrival: the game's, but for its tube, which is the next round's once
  /// the ship arrives.
  late final view = TubeView()..tube = tube;

  /// Plays the run, from the drop's end to where its play ends. It loads on
  /// the drop, so that it's ready by then.
  late final runner = RunnerMode(
    run: RunnerRun(
      tube: endless,
      from: Tube.depth,
      playEnd: playEnd,
      exit: exit,
      color: color,
      next: (tube: next.tube, rim: rim),
      nextColor: next.color,
      sequence: sequence,
      endAt: endAt,
    ),
    from: from,
  );

  /// How far along the run the ship is.
  double flown = 0;

  /// How fast the ship flew as the run's play ended, in tube units a second.
  double arriveSpeed = flightSpeed;

  /// The components that draw the run's tube and the next round's tube, on
  /// the drop and the arrival.
  PositionComponent? tubeDrawing;
  PositionComponent? nextDrawing;

  /// The explosions that [runner] left as the run's play ended, which go on
  /// where they are along the run, on the arrival, until they're done.
  final blasts = <PlacedExplosionComponent>[];

  /// Where the ship was in the world, its angle and its scale, as it began
  /// to arrive.
  Vector2? shipFrom;
  double angleFrom = 0;
  Vector2? scaleFrom;

  /// Removes its drawings.
  void removeDrawings() {
    for (final drawing in [tubeDrawing, nextDrawing]) {
      drawing?.removeFromParent();
    }
    tubeDrawing = nextDrawing = null;
  }

  /// Removes its drawings, its [blasts] and [runner], with what's left on
  /// the run.
  void clear() {
    removeDrawings();
    for (final blast in blasts) {
      blast.removeFromParent();
    }
    blasts.clear();
    runner.removeFromParent();
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

/// The runs, with [ShooterMode.runs] on: see [_Run].
extension on ShooterMode {
  /// Makes the run that the round's drop flies on down, with its runner,
  /// which loads on the drop, or goes on [from] a runner's snapshot.
  void _makeRun({RunnerSnapshot? from}) {
    final run = _run = _Run(
      view.tube,
      level.color,
      levels[(_levelIndex + 1) % levels.length],
      flightSpeed: gameRef.flightSpeed,
      sequence: [..._appeared],
      from: from,
    );
    add(run.runner..spawning = spawning);
  }

  /// Starts the run, the drop's overshoot into it: its runner takes over the
  /// ship, where it is, and the drawing of the run's tube.
  void _beginRun() {
    final run = _run!;
    final over = _stateTime - ShooterMode.dropTime;
    _setState(TubeState.run);
    run.removeDrawings();
    player.isVisible = false;
    run.runner.beginRun(player.step, over);
    _followRunner();
  }

  /// Plays the run over [dt] seconds of the world's time.
  void _stepRun(double dt) {
    final runner = _run!.runner;
    // A run that goes on from a snapshot waits for its runner to load.
    if (!runner.isLoaded) {
      return;
    }
    runner.advance(dt);
    _followRunner();
  }

  /// Keeps the eye, and the hidden ship, where the runner's ship is, and
  /// once the run's play is over, starts the next round as it arrives.
  void _followRunner() {
    final run = _run!;
    final runner = run.runner;
    run.flown = runner.flown;
    // The round's tube goes on behind the eye, and the stars turn as the
    // runner's ship moves round.
    player
      ..depth = run.flown
      ..step = runner.ship.step;
    view.eyeShift = run.flown;
    if (run.flown >= run.playEnd) {
      _beginArrive();
    }
  }

  /// Starts the next round as the ship arrives on its rim, the run's
  /// overshoot into the arrival: the round's ship takes over from the
  /// runner's, where it is, and the round its explosions, where they are.
  void _beginArrive() {
    final run = _run!;
    final ship = run.runner.ship;
    final over = (run.flown - run.playEnd) / run.runner.speed;
    run
      ..arriveSpeed = run.runner.speed
      ..shipFrom = ship.position.clone()
      ..angleFrom = ship.angle
      ..scaleFrom = ship.scale.clone();
    // Moved before the runner goes, so that they don't go with it.
    for (final blast in run.runner.blasts) {
      run.blasts.add(blast);
      blast.parent = explosionGroup;
    }
    run.runner.removeFromParent();
    player.isVisible = true;
    _nextRound(arriving: true);
    _stateTime = over;
    _stepArrive();
  }

  /// Slows the ship down evenly, from as fast as it flew, to a stop on the
  /// next round's rim, as the camera turns to look where the round's does,
  /// and then waits for the player, as at the end of a zoom.
  void _stepArrive() {
    final run = _run!;
    final way = run.rim - run.playEnd;
    final time = 2 * way / run.arriveSpeed;
    final progress = math.min(1.0, _stateTime / time);
    run.flown = run.playEnd + way * progress * (2 - progress);
    player.depth = view.eyeShift = progress == 1 ? 0 : run.flown - run.rim;
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

  /// Draws the run's tube on the drop and the arrival, if there's a run, and
  /// the next round's tube, once it's no farther ahead than the run's tube
  /// goes, and places the run's [_Run.blasts] where they show. On the run,
  /// its runner draws and places them.
  void _drawRun() {
    final run = _run;
    if (run == null || !isLoaded || _state == TubeState.run) {
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
                  math.min(1.0, _stateTime / ShooterMode.dropTime)
        : run.exit;
    final nextColor = arriving ? level.color : run.next.color;
    // The explosions remove themselves once they're done.
    run.blasts.removeWhere((blast) => blast.isRemoving || blast.isRemoved);
    final quads = run.endless.quadsAt(
      distance,
      run.view,
      marks: [for (final blast in run.blasts) blast.mark],
      from: Tube.depth,
      until: math.min(until, run.exit),
      next: run.rim - distance <= EndlessTube.ahead
          ? (tube: arriving ? view.tube : run.next.tube, rim: run.rim)
          : null,
    );
    final glow = gameRef.linesGlow;
    PositionComponent? replace(
      PositionComponent? old,
      RasterizerPolygons quads,
      Color color,
    ) {
      old?.removeFromParent();
      if (quads.bounds.isEmpty) {
        return null;
      }
      gameRef.countPath();
      final component = gameRef.quadsComponent(quads, color, glow: glow);
      tubeGroup.add(component);
      return component;
    }

    run
      ..tubeDrawing = replace(run.tubeDrawing, quads.tube, run.color)
      ..nextDrawing = replace(run.nextDrawing, quads.next, nextColor);
    for (final (i, blast) in run.blasts.indexed) {
      blast.placeAt(quads.places[i]);
    }
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
      ((run.flown - run.exit) / (run.rim - run.exit)).clamp(0.0, 1.0),
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
