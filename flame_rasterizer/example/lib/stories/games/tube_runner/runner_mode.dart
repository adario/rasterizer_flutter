import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/flight_stars_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/ship_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

/// The game's states, as Tube Shooter's. The tube flies down in all of them,
/// but once the game is over.
enum RunnerState() {
  /// READY shows until a tap or a key starts the game, or resumes it after a
  /// lost ship.
  ready,

  /// The game is on: enemies come, and touch the ship.
  play,

  /// The ship was destroyed. Next, it comes back, or the game ends.
  dying,

  /// The game is over, and stands still until a tap, or Enter, starts a new
  /// one.
  over,
}

/// A run down a stretch of tube between two of another mode's rounds, which
/// a [RunnerMode] plays rather than a game of its own.
///
/// The ship flies down [tube] from [from] once the run begins, with
/// [RunnerMode.beginRun], and only while the game is on, so that the run's
/// play lasts as long however many ships it loses. No enemy comes from past
/// [playEnd], so that all are gone once the ship gets there. The tube shows
/// from [from] to its [exit], in [color], with the ship's lane fading in to
/// the ship's colour, and the next round's tube, [next], in [nextColor], once
/// it's no farther ahead than the tube goes. As many of
/// [RunnerMode.enemyKinds] as [kinds] come, from the first.
class RunnerRun({
  required final EndlessTube tube,
  required final double from,
  required final double playEnd,
  required final double exit,
  required final Color color,
  required final NextTube next,
  required final Color nextColor,
  required final int kinds,
});

/// Tube Runner's rules, and the components that play by them, under it in
/// the world, but for the stars, in the camera's backdrop.
///
/// The ship flies down an endless tube, the view's, which it makes as the
/// ship gets there. In the world, the ring at the ship is centred on the
/// origin, where the camera looks. Its game, a [TubeHost] such as
/// `TubeRunnerExample`, hands it the player's input, and has the score, the
/// lives and the texts at the bottom.
///
/// Given a [run], it plays that, for another mode that hands it the input,
/// and has no stars of its own. Once the game is over, the other mode starts
/// the next.
class RunnerMode({
  /// The run it plays between another mode's rounds, if any.
  final RunnerRun? run,
}) extends Component with HasGameRef<TubeHost> {
  /// How fast the ship flies, in tube units a second.
  static const flightSpeed = 2.0;

  /// When the first enemy comes, and how often the others do, in seconds of
  /// the game.
  static const firstEnemy = 4.0;
  static const enemyPeriod = 4.0;

  /// The kinds of enemy that come, in the order they join: the first from
  /// the start, and one more after every [unlockTime] seconds in the tube.
  static const enemyKinds = [
    EnemyKind.seeder,
    EnemyKind.climber,
    EnemyKind.zapper,
    EnemyKind.splitter,
  ];
  static const unlockTime = 30.0;

  /// How far the glow of an enemy's lane and a seeder's spike, and of the
  /// enemy, reach as it comes, in line widths, as Tube Shooter's `tubeGlow`
  /// and `lineGlow` do.
  static const laneGlowWidths = 2.0;
  static const shapeGlowWidths = 3.0;

  /// The alpha of the wider copies that stand for the glow with the renderers
  /// that don't draw it, as an enemy comes.
  static const haloAlpha = 0.3;

  final EndlessTube endlessTube = run?.tube ?? EndlessTube();

  /// The game's view of the tube.
  TubeView get view => gameRef.view;

  /// The game's random numbers.
  math.Random get random => gameRef.random;

  /// The tube it flies down: the view's.
  Tube get tube => view.tube;

  /// Goes on down the view's new tube, from [from], without a stop: the ship
  /// goes on at the same angle round the axis, in the new tube's nearest
  /// step. The enemies, spikes, shots and explosions go, and the time in the
  /// tube starts again.
  void switchTube(Tube from) {
    if (ship.isLoaded) {
      ship.switchFrom(from);
    }
    _clearEnemies();
    _clearBlasts();
    _tubeTime = 0;
  }

  final tubeGroup = Component();
  final ship = ShipComponent();
  final explosionGroup = Component(priority: 5);

  RunnerState get state => _state;
  var _state = RunnerState.ready;

  /// How long the game has been in its state, in seconds of the game.
  double _stateTime = 0;

  /// How long the game has been on in the tube, in seconds of the game: since
  /// the last change of tube, or the last new game.
  double get tubeTime => _tubeTime;
  double _tubeTime = 0;

  /// Whether the ship moves at the player's will.
  bool get canMove => _state == RunnerState.play;

  /// Whether the game waits for the player, at READY or Game Over.
  bool get isWaiting => isReady || isOver;

  /// Whether the game waits at READY.
  bool get isReady => _state == RunnerState.ready;

  /// Whether the game is over, and the world stands still.
  bool get isOver => _state == RunnerState.over;

  /// How long since the ship last fired, in seconds of the game.
  double _sinceShot = PlayerComponent.firePeriod;

  late final stars = FlightStarsComponent(this);

  /// How far the ship has flown along the tube's axis, in tube units.
  double get flown => _flown;
  double _flown = run?.from ?? 0;

  /// The components that draw the tube, and the ship's lane over it in the
  /// ship's colour, as Tube Shooter does, and the next round's tube, on a
  /// run.
  PositionComponent? _tube;
  PositionComponent? _lane;
  PositionComponent? _spikesDrawing;
  PositionComponent? _next;

  /// The components that draw the lane of the enemy that just came, and a
  /// seeder's spike, as it flashes, and their halo, if the renderer doesn't
  /// draw glows.
  PositionComponent? _flashLane;
  PositionComponent? _flashSpike;
  PositionComponent? _halo;

  /// The enemies climbing the tube, in the order they came, which is nearest
  /// first, as they all climb as fast, and the spikes the seeders laid.
  final _enemies = <RunnerEnemyComponent>[];
  final _spikes = <Spike>[];

  /// The enemies climbing the tube, nearest first.
  Iterable<RunnerEnemyComponent> get enemies => _enemies;

  /// The seeders climbing the tube, nearest first.
  Iterable<RunnerSeederComponent> get seeders =>
      _enemies.whereType<RunnerSeederComponent>();

  /// The ship's shots, the climbers' shots, and the explosions of the
  /// enemies the ship's shots destroyed, in [explosionGroup].
  final _shots = <RunnerShotComponent>[];
  final _enemyShots = <RunnerEnemyShotComponent>[];
  final _blasts = <PlacedExplosionComponent>[];

  /// Whether enemies come; tests turn it off, as does a mode whose own
  /// tests do, for its run.
  bool spawning = true;

  /// How long the game has run since the last enemy came, or since
  /// [enemyPeriod] before [firstEnemy].
  double _enemyTime = enemyPeriod - firstEnemy;

  /// How far the ship had flown, the view's version, the ship's lane, and
  /// the flashing enemy and its flash, as the tube's paths were made last.
  double _tubeFlown = double.nan;
  int _tubeVersion = -1;
  int? _tubeLane;
  Color? _tubeLaneColor;
  RunnerEnemyComponent? _tubeFlasher;
  double _tubeFlash = 0;
  List<TubeBolt> _tubeBolts = const [];

  /// The components that draw the zappers' bolts, and their halo, if the
  /// renderer doesn't draw glows.
  PositionComponent? _bolts;
  PositionComponent? _boltHalo;

  /// For the bolts' zigzags, apart from [random], so that drawing doesn't
  /// change the game's random sequence, as in Tube Shooter.
  final _boltRandom = math.Random(0);

  /// Seconds into the zappers' pulse period, as Tube Shooter's first level
  /// has it. The pulse comes at the period's end.
  double _pulseClock = 0;

  /// Whether the zappers pulse now.
  bool get isPulsing => _pulseClock >= _level.pulsePeriod - _level.pulseTime;

  /// Whether the zappers flash white, just before a pulse.
  bool get isWarning {
    final pulse = _level.pulsePeriod - _level.pulseTime;
    return _pulseClock < pulse && _pulseClock >= pulse - _level.pulseWarning;
  }

  /// Tube Shooter's first level, whose pace the enemies go at.
  static final _level = levels.first;

  /// How many quads the tube's paths have.
  int _quads = 0;

  /// Returns the glow of an enemy that comes, reaching [widths] line widths
  /// with [strength], in its [color], or none for no [strength].
  static RasterizerGlow? flashGlow(
    double widths,
    double strength,
    Color color,
  ) => strength > 0
      ? RasterizerGlow.widths(widths, strength: strength, color: color)
      : null;

  /// How many quads the tube's paths have.
  int get quads => _quads;

  @override
  void onLoad() {
    addAll([tubeGroup, ship, explosionGroup]);
    if (run != null) {
      // Out of sight until the run begins.
      ship.isVisible = false;
      return;
    }
    endlessTube.advanceTo(_flown);
    // Under the world, as Tube Shooter's stars are.
    gameRef.camera.backdrop.add(stars);
    _waitForPlayer();
    _updateTube();
  }

  /// Begins the [run], with the ship at [step], in play at once, and flies
  /// [dt] seconds into it.
  void beginRun(int step, double dt) {
    ship
      ..step = step
      ..isVisible = true;
    _beginPlay();
    advance(dt);
  }

  /// Flies the ship, then applies the game's rules. On a [run], the ship
  /// flies only while the game is on.
  void advance(double dt) {
    if (run == null || _state == RunnerState.play) {
      _flown += flightSpeed * dt;
    }
    _step(dt);
    endlessTube.advanceTo(_flown);
    _updateTube();
  }

  /// Shows the time in the tube, once the components updated.
  void afterUpdate(double dt) {
    final seconds = _tubeTime.floor();
    gameRef.roundText.text =
        'TIME ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _setState(RunnerState state) {
    _state = state;
    _stateTime = 0;
    gameRef.forgetWaitPointers();
  }

  /// Applies the game's rules over [dt] seconds of the world's time, after
  /// the ship flew.
  void _step(double dt) {
    _stateTime += dt;
    switch (_state) {
      case RunnerState.play:
        _tubeTime += dt;
        _pulseClock = (_pulseClock + dt) % _level.pulsePeriod;
        _updateEnemies(dt);
        _updateShots(dt);
        _hit();
        _collide();
        _dropPassed();
      case RunnerState.dying:
        if (_stateTime >= TubeHost.respawnTime) {
          if (gameRef.lives == 0) {
            _gameOver();
          } else {
            ship.revive();
            _waitForPlayer();
          }
        }
      case RunnerState.ready || RunnerState.over:
        break;
    }
  }

  /// Destroys the ship if an enemy, a spike or a climber's shot touches it:
  /// one in its lane that reaches the ship's ring, however the ship got into
  /// the lane. Those that passed the ring before went with [_dropPassed]. A
  /// zapper's bolt down the ship's lane destroys it too.
  void _collide() {
    final lane = ship.lane;
    if (_spikes.any(
          (spike) =>
              spike.lane == lane && spike.near <= _flown && _flown <= spike.far,
        ) ||
        _enemies.any(
          (enemy) =>
              (enemy.currentLane == lane && enemy.at <= _flown) ||
              (enemy is RunnerZapperComponent &&
                  enemy.isZapping &&
                  enemy.lane == lane),
        ) ||
        _enemyShots.any((shot) => shot.lane == lane && shot.at <= _flown)) {
      _destroyShip();
    }
  }

  /// Drops the enemies and the climbers' shots that reached the ship's ring,
  /// and the spikes all past it.
  void _dropPassed() {
    bool drop(PositionComponent shape, double at) {
      final passed = at <= _flown;
      if (passed) {
        shape.removeFromParent();
      }
      return passed;
    }

    _enemies.removeWhere((enemy) => drop(enemy, enemy.at));
    _enemyShots.removeWhere((shot) => drop(shot, shot.at));
    _spikes.removeWhere((spike) => spike.far < _flown);
  }

  /// Fires a shot from [climber] down its lane, toward the ship, unless
  /// `maxEnemyShots` of Tube Shooter's first level are in the tube.
  void fireFrom(RunnerClimberComponent climber) {
    if (_state != RunnerState.play ||
        _enemyShots.length >= levels.first.maxEnemyShots) {
      return;
    }
    final shot = RunnerEnemyShotComponent(climber.currentLane, climber.at);
    _enemyShots.add(shot);
    add(shot);
    _tubeFlown = double.nan;
  }

  /// Over [dt] seconds of the game: fires a shot down the ship's lane every
  /// `PlayerComponent.firePeriod` while it fires, with at most
  /// `PlayerComponent.maxShots` in the tube, as in Tube Shooter, flies the
  /// shots, and drops those [RunnerShotComponent.range] ahead of the ship.
  void _updateShots(double dt) {
    for (final shot in _shots) {
      shot.fly(dt);
    }
    _shots.removeWhere((shot) {
      final gone = shot.at > _flown + RunnerShotComponent.range;
      if (gone) {
        shot.removeFromParent();
      }
      return gone;
    });
    _sinceShot += dt;
    if (gameRef.isFiring &&
        _sinceShot >= PlayerComponent.firePeriod &&
        _shots.length < PlayerComponent.maxShots) {
      _sinceShot = 0;
      final shot = RunnerShotComponent(ship.lane, _flown);
      _shots.add(shot);
      add(shot);
      // Places it now, even if nothing else moved.
      _tubeFlown = double.nan;
    }
  }

  /// Resolves the shots' hits, as in Tube Shooter: each shot hits the
  /// nearest spike, enemy or climber's shot in its lane that it reached or
  /// passed since it last flew. A seeder is at its spike's near end, so the
  /// spike stands for it. The shot destroys an enemy, and scores, a seeder
  /// leaving its spike, cuts a spike back by `ShooterMode.spikeHit`
  /// from its near end, and scores, or destroys a climber's shot.
  void _hit() {
    for (final shot in [..._shots]) {
      Object? target;
      var nearest = double.infinity;
      void aim(Object at, double distance) {
        if (distance < nearest) {
          target = at;
          nearest = distance;
        }
      }

      for (final spike in _spikes) {
        if (spike.lane == shot.lane &&
            spike.near <= shot.at &&
            spike.far >= shot.previousAt) {
          aim(spike, spike.near);
        }
      }
      for (final enemy in _enemies) {
        if (enemy is! RunnerSeederComponent &&
            enemy.currentLane == shot.lane &&
            _meet(shot, enemy.previousAt, enemy.at)) {
          aim(enemy, enemy.at);
        }
      }
      for (final enemyShot in _enemyShots) {
        if (enemyShot.lane == shot.lane &&
            _meet(shot, enemyShot.previousAt, enemyShot.at)) {
          aim(enemyShot, enemyShot.at);
        }
      }
      if (target == null) {
        continue;
      }
      _shots.remove(shot);
      shot.removeFromParent();
      switch (target) {
        case final Spike spike:
          _hitSpike(spike);
        case final RunnerEnemyComponent enemy:
          _destroyEnemy(enemy);
        case final RunnerEnemyShotComponent enemyShot:
          _enemyShots.remove(enemyShot);
          enemyShot.removeFromParent();
      }
    }
  }

  /// Whether [shot] met something that climbed from [previousAt] to [at]
  /// as both last moved: it was behind the shot, and now it isn't.
  static bool _meet(RunnerShotComponent shot, double previousAt, double at) =>
      shot.previousAt <= previousAt && shot.at >= at;

  /// Destroys the seeder at [spike]'s near end, if it's there, or else cuts
  /// [spike] back, and scores.
  void _hitSpike(Spike spike) {
    final seeder = seeders
        .where((seeder) => identical(seeder.spike, spike))
        .firstOrNull;
    if (seeder != null) {
      _destroyEnemy(seeder);
      return;
    }
    spike.near = math.min(spike.near + ShooterMode.spikeHit, spike.far);
    gameRef.score += ShooterMode.spikeScore;
    if (spike.near >= spike.far) {
      _spikes.remove(spike);
    }
  }

  /// Blows [enemy] up where it is along the tube, and adds its score. A
  /// seeder's spike stays, and a splitter splits, as in Tube Shooter.
  void _destroyEnemy(RunnerEnemyComponent enemy) {
    gameRef.score += enemy.kind.score;
    final blast = PlacedExplosionComponent(
      enemy.mark,
      rayColor: enemy.kind.color,
    );
    _blasts.add(blast);
    explosionGroup.add(blast);
    _tubeFlown = double.nan;
    if (enemy is RunnerSplitterComponent) {
      _split(enemy);
    } else {
      _enemies.remove(enemy);
      enemy.removeFromParent();
    }
  }

  /// Removes the enemies' explosions.
  void _clearBlasts() {
    for (final blast in _blasts) {
      blast.removeFromParent();
    }
    _blasts.clear();
  }

  /// Blows the ship up, fades it out, and takes a life. The enemies, spikes
  /// and shots go.
  void _destroyShip() {
    gameRef.lives--;
    explosionGroup.add(
      RunnerExplosionComponent(
        position: ship.position.clone(),
        angle: ship.angle,
        scale: ship.scale.clone(),
        color: TubeColors.ship,
      ),
    );
    ship.fadeOut();
    _clearEnemies();
    _setState(RunnerState.dying);
  }

  /// Shows READY, until a tap or a key.
  void _waitForPlayer() {
    gameRef.camera.viewport.add(gameRef.readyText);
    _setState(RunnerState.ready);
  }

  /// Starts the game, or resumes it after a lost ship, with the first enemy
  /// [firstEnemy] away.
  void _beginPlay() {
    gameRef.readyText.removeFromParent();
    _enemyTime = enemyPeriod - firstEnemy;
    _setState(RunnerState.play);
  }

  /// Stops the world, whatever the game's speed is, and shows Game Over
  /// until a tap or Enter.
  void _gameOver() {
    gameRef.world.timeScale = 0;
    _setState(RunnerState.over);
    ship.isVisible = false;
    gameRef.camera.viewport.add(gameRef.gameOverText);
  }

  /// Starts a new game in this one: no explosions, all lives, the time in the
  /// tube and the score from 0, and the world at the game's speed, waiting
  /// at READY.
  void _newGame() {
    explosionGroup.removeAll(explosionGroup.children.toList());
    _blasts.clear();
    gameRef.lives = TubeHost.startLives;
    _tubeTime = 0;
    gameRef.score = 0;
    gameRef.gameOverText.removeFromParent();
    gameRef.world.timeScale = gameRef.speed;
    ship.revive();
    _waitForPlayer();
  }

  /// Ends a wait: starts a new game once it's over, or else plays.
  void endWait() {
    if (_state == RunnerState.over) {
      _newGame();
    } else {
      _beginPlay();
    }
  }

  /// Makes the tube's paths again if the ship flew or changed lanes, an
  /// enemy's flash changed, or the view changed, and places the enemies,
  /// shots and explosions where they show.
  ///
  /// As the last enemy comes, the lane it came in flashes: over its
  /// [RunnerEnemyComponent.flashTime], the lane fades from the enemy's
  /// colour to its own, or, if it's the ship's, from the ship's colour with
  /// the enemy's added, and its lines and a seeder's spike glow, fading out.
  /// With the renderers that don't draw glows, wider, see-through copies of
  /// them in the enemy's colour stand for the glow.
  ///
  /// While the zappers pulse, their bolts zigzag down their lanes to the
  /// ship's ring, glowing in their colour, or with wider, see-through copies.
  void _updateTube() {
    // The ship knows its lane once loaded. Its lane shows while it's in play,
    // as in Tube Shooter.
    final lane = ship.isLoaded && canMove ? ship.lane : null;
    var flasher = _enemies.lastOrNull;
    final flash = flasher?.flash ?? 0;
    if (flash == 0) {
      flasher = null;
    }
    final bolts = <TubeBolt>[
      for (final enemy in _enemies)
        if (enemy is RunnerZapperComponent && enemy.isZapping)
          (lane: enemy.lane, far: enemy.at),
    ];
    final run = this.run;
    final tubeColor = run?.color ?? TubeColors.tube;
    // On a run, the ship's lane fades in as it does in Tube Shooter's play.
    final laneColor = run == null
        ? TubeColors.ship
        : Color.lerp(
            tubeColor,
            TubeColors.ship,
            math.min(1.0, _tubeTime / ShooterMode.laneFadeTime),
          )!;
    if (_flown == _tubeFlown &&
        view.version == _tubeVersion &&
        lane == _tubeLane &&
        laneColor == _tubeLaneColor &&
        flasher == _tubeFlasher &&
        flash == _tubeFlash &&
        listEquals(bolts, _tubeBolts)) {
      return;
    }
    _tubeFlown = _flown;
    _tubeVersion = view.version;
    _tubeLane = lane;
    _tubeLaneColor = laneColor;
    _tubeFlasher = flasher;
    _tubeFlash = flash;
    _tubeBolts = bolts;
    // The explosions remove themselves once they're done.
    _blasts.removeWhere((blast) => blast.isRemoving || blast.isRemoved);
    final placed = <TubePlaced>[
      ..._enemies,
      ..._shots,
      ..._enemyShots,
      ..._blasts,
    ];
    final color = flasher?.kind.color ?? TubeColors.seeder;
    final quads = endlessTube.quadsAt(
      _flown,
      view,
      lane: lane,
      spikes: _spikes,
      marks: [for (final shape in placed) shape.mark],
      flashLane: flasher?.spawnLane,
      flashSpike: flasher is RunnerSeederComponent ? flasher.spike : null,
      halo: gameRef.rendererGlows ? null : 2 * laneGlowWidths,
      bolts: bolts,
      random: _boltRandom,
      from: run?.from ?? double.negativeInfinity,
      until: run?.exit ?? double.infinity,
      next: run != null && run.next.rim - _flown <= EndlessTube.ahead
          ? run.next
          : null,
    );
    _quads =
        quads.tube.vertexCounts.length +
        quads.lane.vertexCounts.length +
        quads.next.vertexCounts.length +
        quads.spikes.vertexCounts.length +
        quads.flashLane.vertexCounts.length +
        quads.flashSpike.vertexCounts.length +
        quads.halo.vertexCounts.length +
        quads.bolts.vertexCounts.length +
        quads.boltHalo.vertexCounts.length;
    // Under the lines it stands for the glow of, over the others, as a glow
    // is.
    _tube = _replaceQuads(_tube, quads.tube, tubeColor);
    _lane = _replaceQuads(_lane, quads.lane, laneColor);
    _next = _replaceQuads(
      _next,
      quads.next,
      run?.nextColor ?? TubeColors.tube,
    );
    _spikesDrawing = _replaceQuads(
      _spikesDrawing,
      quads.spikes,
      TubeColors.spikes,
    );
    _halo = _replaceQuads(
      _halo,
      quads.halo,
      color.withValues(alpha: haloAlpha * flash),
    );
    final glow = gameRef.rendererGlows
        ? flashGlow(laneGlowWidths, flash, color)
        : null;
    _flashLane = _replaceQuads(
      _flashLane,
      quads.flashLane,
      flasher?.spawnLane == lane
          ? _addLight(TubeColors.ship, color, flash)
          : Color.lerp(color, tubeColor, 1 - flash)!,
      glow: glow,
    );
    _flashSpike = _replaceQuads(
      _flashSpike,
      quads.flashSpike,
      TubeColors.spikes,
      glow: glow,
    );
    _boltHalo = _replaceQuads(
      _boltHalo,
      quads.boltHalo,
      TubeColors.bolts.withValues(alpha: haloAlpha),
    );
    _bolts = _replaceQuads(
      _bolts,
      quads.bolts,
      TubeColors.bolts,
      glow: gameRef.rendererGlows
          ? flashGlow(laneGlowWidths, 1, TubeColors.bolts)
          : null,
    );
    for (var i = 0; i < placed.length; i++) {
      placed[i].placeAt(quads.places[i]);
    }
  }

  /// Over [dt] seconds of the game: brings an enemy at [firstEnemy], then
  /// every [enemyPeriod], of a kind picked at random among the [enemyKinds]
  /// that joined, or the [run]'s kinds, on a lane picked at random, climbs
  /// the enemies and the climbers' shots, and splits the splitters that got
  /// [RunnerSplitterComponent.splitAhead] of the ship. On a run, none comes
  /// from past where its play ends.
  void _updateEnemies(double dt) {
    _enemyTime += dt;
    if (_enemyTime >= enemyPeriod) {
      _enemyTime -= enemyPeriod;
      if (spawning && _farRing <= (run?.playEnd ?? double.infinity)) {
        final kinds = (run?.kinds ?? 1 + _tubeTime ~/ unlockTime).clamp(
          1,
          enemyKinds.length,
        );
        // Picking among one kind would take a number from [random], and
        // change what comes until the second kind joins.
        final kind = enemyKinds[kinds == 1 ? 0 : random.nextInt(kinds)];
        addEnemy(kind, random.nextInt(tube.laneCount));
      }
    }
    for (final enemy in _enemies) {
      enemy.climb(dt);
    }
    for (final shot in _enemyShots) {
      shot.climb(dt);
    }
    final near = _flown + RunnerSplitterComponent.splitAhead;
    _enemies
        .whereType<RunnerSplitterComponent>()
        .where((splitter) => splitter.at <= near)
        .toList()
        .forEach(_split);
  }

  /// Replaces [splitter] with two climbers where it is, which flip from its
  /// lane onto the lanes on either side, as in Tube Shooter. A climber with
  /// no lane on its side, at an open tube's end, stays in the splitter's
  /// lane. They don't flash, as they didn't come down the tube.
  void _split(RunnerSplitterComponent splitter) {
    final index = _enemies.indexOf(splitter);
    _enemies.removeAt(index);
    splitter.removeFromParent();
    final climbers = <RunnerClimberComponent>[];
    for (final side in [-1, 1]) {
      final climber = RunnerClimberComponent(
        splitter.lane,
        splitter.at,
        flashes: false,
      );
      final to = tube.neighbour(splitter.lane, side);
      if (to != null) {
        climber.flip(to, tube);
      }
      climbers.add(climber);
    }
    // Where the splitter was, so that they stay nearest first.
    _enemies.insertAll(index, climbers);
    addAll(climbers);
    _tubeFlown = double.nan;
  }

  /// Brings an enemy of [kind], one of [enemyKinds], at the farthest ring
  /// across the tube, in [lane].
  @visibleForTesting
  void addEnemy(EnemyKind kind, int lane) {
    final far = _farRing;
    final RunnerEnemyComponent enemy;
    switch (kind) {
      case EnemyKind.seeder:
        final spike = Spike(lane, far);
        _spikes.add(spike);
        enemy = RunnerSeederComponent(spike);
      case EnemyKind.climber:
        enemy = RunnerClimberComponent(lane, far);
      case EnemyKind.zapper:
        enemy = RunnerZapperComponent(lane, far);
      case EnemyKind.splitter:
        enemy = RunnerSplitterComponent(lane, far);
      case EnemyKind.edgeWalker:
        throw ArgumentError.value(kind, 'kind', "doesn't come here");
    }
    _enemies.add(enemy);
    add(enemy);
  }

  /// The farthest ring across the tube, where the enemies come.
  double get _farRing {
    const spacing = EndlessTube.ringSpacing;
    return ((_flown + EndlessTube.ahead) / spacing).floor() * spacing;
  }

  /// Removes all the enemies, spikes and shots.
  void _clearEnemies() {
    for (final shape in [..._enemies, ..._shots, ..._enemyShots]) {
      shape.removeFromParent();
    }
    _enemies.clear();
    _spikes.clear();
    _shots.clear();
    _enemyShots.clear();
  }

  /// Returns [base] with [light] added to it, [amount] times as strong, as
  /// lights add up: channel by channel, up to full.
  static Color _addLight(Color base, Color light, double amount) => Color.from(
    alpha: base.a,
    red: math.min(1, base.r + amount * light.r),
    green: math.min(1, base.g + amount * light.g),
    blue: math.min(1, base.b + amount * light.b),
  );

  /// Removes [old], if any, and returns a component that fills [quads] in
  /// [color], with [glow], added to [tubeGroup], if there are any.
  PositionComponent? _replaceQuads(
    PositionComponent? old,
    RasterizerPolygons quads,
    Color color, {
    RasterizerGlow? glow,
  }) {
    old?.removeFromParent();
    if (quads.bounds.isEmpty) {
      return null;
    }
    gameRef.countPath();
    final component = gameRef.quadsComponent(quads, color, glow: glow);
    tubeGroup.add(component);
    return component;
  }

  /// Moves the ship [lanes] round the tube.
  void moveShipBy(double lanes) => ship.moveBy(lanes);
}

/// A component under a [RunnerMode], which plays by its rules.
mixin InRunnerMode on Component {
  /// The mode that it's under, or was under when it [findRunner].
  RunnerMode get runner => _runner ??= findParent<RunnerMode>()!;
  RunnerMode? _runner;

  /// Finds the mode that it's under, so that [runner] is still its mode once
  /// it's gone from it, as when it finishes loading after it went.
  void findRunner() => _runner ??= findParent<RunnerMode>();
}
