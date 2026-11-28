import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/flight_stars_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_edge_walker_component.dart';
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
import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

/// The game's states, as in Tube Shooter.
///
/// Outside a [RunnerRun], the ship flies down the tube in every state except
/// [over].
enum RunnerState() {
  /// READY shows until a tap or a key starts the game, or resumes it after
  /// the ship was lost.
  ready,

  /// The game is on: enemies come and can touch the ship.
  play,

  /// The ship was destroyed. Next, it comes back, or the game ends.
  dying,

  /// The game is over and stands still until a tap or Enter starts a new
  /// one.
  over,
}

/// A run down a stretch of tube between two rounds of another mode, which a
/// [RunnerMode] plays instead of a game of its own.
///
/// After [RunnerMode.beginRun] starts the run, the ship flies down [tube]
/// from [from], and only while the game is on. This way the run's play
/// covers the same stretch however many ships the player loses. No enemy
/// comes from past [playEnd], so all of them are gone by the time the ship
/// gets there.
///
/// The tube shows from [from] to its [exit] in [color], and the ship's lane
/// fades in to the ship's colour. The next round's tube, [next], shows in
/// [nextColor] when its rim is no farther ahead than the tube goes.
///
/// The enemies come in the order of [sequence]. The [playEnd] and [exit]
/// start infinite. When the sequence has nearly run out, the runner sets
/// them with [endAt], which takes the run's play end and returns its exit
/// and the next round's rim.
class RunnerRun({
  required final EndlessTube tube,
  required final double from,
  required var double playEnd,
  required var double exit,
  required final Color color,
  required var NextTube next,
  required final Color nextColor,
  required final List<EnemyKind> sequence,
  required final ({double exit, double rim}) Function(double playEnd) endAt,
});

/// What a [RunnerMode] resumes from when the game switches to another
/// renderer.
///
/// It holds:
/// - the state, and how long the game has been in it;
/// - the time in the tube, and how far the ship has flown;
/// - the seconds since the ship's last shot, and until the next enemy comes;
/// - how many enemies came, and the kind of the last one;
/// - how many enemies the ship's shots destroyed;
/// - on a run, the enemies still to come, and where its play ends;
/// - the zappers' pulse clock;
/// - the ship, the spikes, the enemies, the ship's shots and the climbers'
///   shots.
typedef RunnerSnapshot = ({
  RunnerState state,
  double stateTime,
  double tubeTime,
  double flown,
  double sinceShot,
  double untilEnemy,
  int spawned,
  EnemyKind? lastKind,
  int kills,
  List<EnemyKind> queue,
  double playEnd,
  double pulseClock,
  ShipSnapshot ship,
  List<({int lane, double far, double near})> spikes,
  List<RunnerEnemySnapshot> enemies,
  List<RunnerShotSnapshot> shots,
  List<RunnerShotSnapshot> enemyShots,
});

/// Tube Runner's rules, and the components that play by them.
///
/// The components sit under the mode in the world, except the stars, which
/// sit in the camera's backdrop.
///
/// The ship flies down an endless tube with the outline of the view's tube,
/// built as the ship gets there. In the world, the ring at the ship is
/// centred on the origin, where the camera looks. The game, a [TubeHost]
/// such as `TubeRunnerExample`, hands the mode the player's input, and holds
/// the score, the lives and the texts at the bottom.
///
/// Given a [run], the mode plays that run for another mode, which hands it
/// the input. It then has no stars of its own. When the game is over, the
/// other mode starts the next one.
///
/// Given [from], the mode resumes from that snapshot: see [snapshot]. The
/// explosions start again, and its random picks differ from those the old
/// mode would have made.
class RunnerMode({
  /// The run it plays between another mode's rounds, if any.
  final RunnerRun? run,

  /// The snapshot of a game with another renderer to resume from, if any.
  final RunnerSnapshot? from,
}) extends Component with HasGameRef<TubeHost> {
  this {
    if (from case final from?) {
      _goOnFrom(from);
    }
  }

  /// How fast the ship flies at first, in tube units a second: the game's
  /// [TubeHost.flightSpeed].
  double get flightSpeed => gameRef.flightSpeed;

  /// How much faster the ship flies for each enemy its shots destroyed, as a
  /// fraction of [flightSpeed], until the ship is lost.
  static const speedUp = 0.05;

  /// How many of the first enemies are seeders.
  static const firstSeeders = 2;

  /// When the first enemy comes, in seconds of the game.
  static const firstEnemy = 3.0;

  /// The kinds of enemy that come, except on a [run].
  static const enemyKinds = [
    EnemyKind.seeder,
    EnemyKind.climber,
    EnemyKind.zapper,
    EnemyKind.splitter,
    EnemyKind.edgeWalker,
  ];

  /// How far the glows reach as an enemy comes, in line widths: that of its
  /// lane and a seeder's spike, and that of the enemy itself. They match Tube
  /// Shooter's `tubeGlow` and `lineGlow`.
  static const laneGlowWidths = 2.0;
  static const shapeGlowWidths = 3.0;

  /// The alpha of the wider copies that stand in for the glow as an enemy
  /// comes, with the renderers that don't draw glows.
  static const haloAlpha = 0.3;

  final EndlessTube endlessTube = run?.tube ?? EndlessTube();

  /// The game's view of the tube.
  TubeView get view => gameRef.view;

  /// The game's random numbers.
  math.Random get random => gameRef.random;

  /// The tube the ship flies down: the view's.
  Tube get tube => view.tube;

  /// Switches from the tube [from] to the view's new tube without stopping.
  ///
  /// The ship keeps its angle round the axis, on the new tube's nearest
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
  late final ship = ShipComponent(from: from?.ship);
  final explosionGroup = Component(priority: 5);

  RunnerState get state => _state;
  var _state = RunnerState.ready;

  /// How long the game has been in its state, in seconds of the game.
  double _stateTime = 0;

  /// How long the game has been on in this tube, in seconds of the game:
  /// since the last change of tube or the last new game.
  double get tubeTime => _tubeTime;
  double _tubeTime = 0;

  /// Whether the player can move the ship.
  bool get canMove => _state == RunnerState.play;

  /// Whether the game waits for the player, at READY or Game Over.
  bool get isWaiting => isReady || isOver;

  /// Whether the game waits at READY.
  bool get isReady => _state == RunnerState.ready;

  /// Whether the game is over and the world stands still.
  bool get isOver => _state == RunnerState.over;

  /// How long since the ship last fired, in seconds of the game.
  double _sinceShot = PlayerComponent.firePeriod;

  late final stars = FlightStarsComponent(this);

  /// How far the ship has flown along the tube's axis, in tube units.
  double get flown => _flown;
  double _flown = run?.from ?? 0;

  /// The components that draw the tube, the ship's lane over it in the
  /// ship's colour as Tube Shooter does, the spikes, and on a run, the next
  /// round's tube.
  PositionComponent? _tube;
  PositionComponent? _lane;
  PositionComponent? _spikesDrawing;
  PositionComponent? _next;

  /// The components that draw the flash as an enemy comes: its lane, a
  /// seeder's spike, and their halo when the renderer doesn't draw glows.
  PositionComponent? _flashLane;
  PositionComponent? _flashSpike;
  PositionComponent? _halo;

  /// The enemies climbing the tube, and the spikes the seeders laid.
  ///
  /// The enemies are in the order they came. Since they all climb at the same
  /// speed, that order is also nearest first.
  final _enemies = <RunnerEnemyComponent>[];
  final _spikes = <Spike>[];

  /// The enemies climbing the tube, nearest first.
  Iterable<RunnerEnemyComponent> get enemies => _enemies;

  /// The seeders climbing the tube, nearest first.
  Iterable<RunnerSeederComponent> get seeders =>
      _enemies.whereType<RunnerSeederComponent>();

  /// The spikes the seeders laid, in the order they came.
  List<Spike> get spikes => UnmodifiableListView(_spikes);

  /// The ship's shots, the climbers' shots, and the explosions of the
  /// enemies the ship's shots destroyed, in [explosionGroup].
  final _shots = <RunnerShotComponent>[];
  final _enemyShots = <RunnerEnemyShotComponent>[];
  final _blasts = <PlacedExplosionComponent>[];

  /// The explosions of the enemies the ship's shots destroyed that still
  /// show.
  ///
  /// The mode that plays a run keeps placing them after the run's play is
  /// over.
  Iterable<PlacedExplosionComponent> get blasts =>
      _blasts.where((blast) => !blast.isRemoving && !blast.isRemoved);

  /// Whether enemies come.
  ///
  /// Tests turn it off, and so does a mode for its run when that mode's own
  /// tests turn its enemies off.
  bool spawning = true;

  /// How long until the next enemy comes, in seconds of the game.
  double _untilEnemy = firstEnemy;

  /// How many enemies came since play began or resumed, and the kind of the
  /// last one.
  int _spawned = 0;
  EnemyKind? _lastKind;

  /// On a run, the enemies still to come, in order.
  late final _queue = <EnemyKind>[...?run?.sequence];

  /// On a run, how many enemies are left to come when its end is set, and
  /// how far past the last one's ring the end goes.
  ///
  /// The margin covers the drift in the spacing of the spawns as the ship
  /// speeds up.
  static const endSpawns = 2;
  static const endMargin = 2.0;

  /// How many enemies the ship's shots destroyed since the game or the run
  /// began, or since the ship was last lost.
  int _kills = 0;

  /// How fast the ship flies now, in tube units a second.
  double get speed => flightSpeed * (1 + speedUp * _kills);

  /// How long after an enemy the next one comes, at the ship's [speed].
  ///
  /// It is shorter than [firstEnemyPeriod] by as much as the ship is faster
  /// than [flightSpeed], so the enemies stay the same distance apart along
  /// the tube.
  double get enemyPeriod => firstEnemyPeriod * flightSpeed / speed;
  static const firstEnemyPeriod = 4.0;

  /// The inputs of the last time the tube's paths were made: how far the
  /// ship had flown, the view's version, the ship's lane and its colour, the
  /// flashing enemy and its flash, and the bolts.
  double _tubeFlown = double.nan;
  int _tubeVersion = -1;
  int? _tubeLane;
  Color? _tubeLaneColor;
  RunnerEnemyComponent? _tubeFlasher;
  double _tubeFlash = 0;
  List<TubeBolt> _tubeBolts = const [];

  /// The components that draw the zappers' bolts, and their halo when the
  /// renderer doesn't draw glows.
  PositionComponent? _bolts;
  PositionComponent? _boltHalo;

  /// The random numbers for the bolts' zigzags.
  ///
  /// They are kept apart from [random] so that drawing doesn't change the
  /// game's random sequence, as in Tube Shooter.
  final _boltRandom = math.Random(0);

  /// How many seconds into the zappers' pulse period the game is, with the
  /// period of Tube Shooter's first level. The pulse comes at the period's
  /// end.
  double _pulseClock = 0;

  /// Whether the zappers are pulsing.
  bool get isPulsing => _pulseClock >= _level.pulsePeriod - _level.pulseTime;

  /// Whether the zappers flash white, just before a pulse.
  bool get isWarning {
    final pulse = _level.pulsePeriod - _level.pulseTime;
    return _pulseClock < pulse && _pulseClock >= pulse - _level.pulseWarning;
  }

  /// Tube Shooter's first level, which sets the enemies' pace.
  static final _level = levels.first;

  /// How many quads the tube's paths have.
  int _quads = 0;

  /// Returns the glow of a coming enemy in its [color], reaching [widths]
  /// line widths with [strength], or null when [strength] is 0.
  static RasterizerGlow? flashGlow(
    double widths,
    double strength,
    Color color,
  ) => strength > 0
      ? RasterizerGlow.widths(widths, strength: strength, color: color)
      : null;

  /// How many quads the tube's paths have.
  int get quads => _quads;

  /// What a game with another renderer resumes from.
  RunnerSnapshot get snapshot => (
    state: _state,
    stateTime: _stateTime,
    tubeTime: _tubeTime,
    flown: _flown,
    sinceShot: _sinceShot,
    untilEnemy: _untilEnemy,
    spawned: _spawned,
    lastKind: _lastKind,
    kills: _kills,
    queue: [..._queue],
    playEnd: run?.playEnd ?? double.infinity,
    pulseClock: _pulseClock,
    ship: ship.snapshot,
    spikes: [
      for (final spike in _spikes)
        (lane: spike.lane, far: spike.far, near: spike.near),
    ],
    enemies: [for (final enemy in _enemies) enemy.snapshot],
    shots: [for (final shot in _shots) shot.snapshot],
    enemyShots: [for (final shot in _enemyShots) shot.snapshot],
  );

  /// Resumes from the state, times, spikes, enemies and shots in [from], and
  /// makes the tube's rings again.
  void _goOnFrom(RunnerSnapshot from) {
    _state = from.state;
    _stateTime = from.stateTime;
    _tubeTime = from.tubeTime;
    _flown = from.flown;
    _sinceShot = from.sinceShot;
    _untilEnemy = from.untilEnemy;
    _spawned = from.spawned;
    _lastKind = from.lastKind;
    _kills = from.kills;
    _queue
      ..clear()
      ..addAll(from.queue);
    if (run != null) {
      _endRunAt(from.playEnd);
    }
    _pulseClock = from.pulseClock;
    for (final (:lane, :far, :near) in from.spikes) {
      _spikes.add(Spike(lane, far)..near = near);
    }
    for (final enemy in from.enemies) {
      final RunnerEnemySnapshot(:kind, :spawnLane, :at, :own) = enemy;
      final component = switch (kind) {
        EnemyKind.seeder => RunnerSeederComponent(
          _spikes[(own! as ({int spike})).spike],
          from: enemy,
        ),
        EnemyKind.climber => RunnerClimberComponent(spawnLane, at, from: enemy),
        EnemyKind.zapper => RunnerZapperComponent(spawnLane, at, from: enemy),
        EnemyKind.splitter => RunnerSplitterComponent(
          spawnLane,
          at,
          from: enemy,
        ),
        EnemyKind.edgeWalker => RunnerEdgeWalkerComponent(
          spawnLane,
          at,
          from: enemy,
        ),
      };
      _enemies.add(component);
      add(component);
    }
    for (final (:lane, :at, :previousAt) in from.shots) {
      final shot = RunnerShotComponent(lane, at)..previousAt = previousAt;
      _shots.add(shot);
      add(shot);
    }
    for (final (:lane, :at, :previousAt) in from.enemyShots) {
      final shot = RunnerEnemyShotComponent(lane, at)..previousAt = previousAt;
      _enemyShots.add(shot);
      add(shot);
    }
    // Each ring turns from the one before, so the rings are made again from
    // the first one, to come out as they were.
    endlessTube
      ..advanceTo(0)
      ..advanceTo(_flown);
  }

  @override
  void onLoad() {
    addAll([tubeGroup, ship, explosionGroup]);
    if (from != null && isReady) {
      gameRef.camera.viewport.add(gameRef.readyText);
    }
    if (run != null) {
      // The ship stays hidden until the run begins.
      if (from == null) {
        ship.isVisible = false;
      }
      return;
    }
    endlessTube.advanceTo(_flown);
    // Under the world, as Tube Shooter's stars are.
    gameRef.camera.backdrop.add(stars);
    if (from == null) {
      _waitForPlayer();
    } else if (isOver) {
      gameRef.world.timeScale = 0;
      gameRef.camera.viewport.add(gameRef.gameOverText);
    }
    _updateTube();
  }

  /// Begins the [run] with the ship at [step], straight into play, and flies
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
      _flown += speed * dt;
    }
    _step(dt);
    endlessTube.advanceTo(_flown);
    _updateTube();
  }

  /// Shows the time in the tube, after the components have updated.
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
        final wasPulsing = isPulsing;
        _pulseClock = (_pulseClock + dt) % _level.pulsePeriod;
        if (!wasPulsing &&
            isPulsing &&
            _enemies.any(
              (enemy) => enemy is RunnerZapperComponent && enemy.isZapping,
            )) {
          gameRef.play(Sound.zap);
        }
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

  /// Destroys the ship if an enemy, a spike or a climber's shot touches it.
  ///
  /// Any of them in the ship's lane touches it when it reaches the ship's
  /// ring, however the ship got into that lane. Those that passed the ring
  /// earlier are already gone, through [_dropPassed]. A zapper's bolt down
  /// the ship's lane destroys the ship too.
  void _collide() {
    final lane = ship.lane;
    if (_spikes.any(
          (spike) =>
              spike.lane == lane && spike.near <= _flown && _flown <= spike.far,
        ) ||
        _enemies.any(
          (enemy) =>
              (enemy.at <= _flown && enemy.hits(lane)) ||
              (enemy is RunnerZapperComponent &&
                  enemy.isZapping &&
                  enemy.lane == lane),
        ) ||
        _enemyShots.any((shot) => shot.lane == lane && shot.at <= _flown)) {
      _destroyShip();
    }
  }

  /// Drops the enemies and the climbers' shots that reached the ship's ring,
  /// and the spikes that are wholly behind it.
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

  /// Fires a shot from [climber] down its lane toward the ship, unless the
  /// tube already holds the `maxEnemyShots` of Tube Shooter's first level.
  void fireFrom(RunnerClimberComponent climber) {
    if (_state != RunnerState.play ||
        _enemyShots.length >= levels.first.maxEnemyShots) {
      return;
    }
    final shot = RunnerEnemyShotComponent(climber.currentLane, climber.at);
    _enemyShots.add(shot);
    add(shot);
    _tubeFlown = double.nan;
    gameRef.play(Sound.enemyFire);
  }

  /// Flies the ship's shots over [dt] seconds of the game, and fires new
  /// ones.
  ///
  /// It drops the shots that are [RunnerShotComponent.range] ahead of the
  /// ship, and those the tube hid when it last placed them, so they can't
  /// hit what doesn't show. While the player fires, a shot goes down the
  /// ship's lane every `PlayerComponent.firePeriod`, with at most
  /// `PlayerComponent.maxShots` in the tube, as in Tube Shooter.
  void _updateShots(double dt) {
    for (final shot in _shots) {
      shot.fly(dt, speed);
    }
    _shots.removeWhere((shot) {
      final gone =
          !shot.isVisible || shot.at > _flown + RunnerShotComponent.range;
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
      // Places the shot this frame, even if nothing else moved.
      _tubeFlown = double.nan;
      gameRef.play(Sound.fire);
    }
  }

  /// Resolves the shots' hits, as in Tube Shooter.
  ///
  /// Each shot hits the nearest spike, enemy or climber's shot in its lane
  /// that it reached or passed since it last flew. Only the enemies and
  /// shots that showed where the tube last placed them count. A seeder sits
  /// at its spike's near end, so the spike stands for it.
  ///
  /// A shot that hits an enemy destroys it and scores; a destroyed seeder
  /// leaves its spike behind. A shot that hits a spike cuts it back by
  /// `ShooterMode.spikeHit` from its near end and scores. A shot that hits a
  /// climber's shot destroys it.
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
            enemy.isVisible &&
            enemy.canBeShot &&
            enemy.currentLane == shot.lane &&
            _meet(shot, enemy.previousAt, enemy.at)) {
          aim(enemy, enemy.at);
        }
      }
      for (final enemyShot in _enemyShots) {
        if (enemyShot.lane == shot.lane &&
            enemyShot.isVisible &&
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
          destroyEnemy(enemy);
        case final RunnerEnemyShotComponent enemyShot:
          _enemyShots.remove(enemyShot);
          enemyShot.removeFromParent();
      }
    }
  }

  /// Whether [shot] met something that climbed from [previousAt] to [at]
  /// when both last moved: it was ahead of the shot before, and now it
  /// isn't.
  static bool _meet(RunnerShotComponent shot, double previousAt, double at) =>
      shot.previousAt <= previousAt && shot.at >= at;

  /// Destroys the seeder at [spike]'s near end if it is still there.
  /// Otherwise cuts [spike] back and scores.
  void _hitSpike(Spike spike) {
    final seeder = seeders
        .where((seeder) => identical(seeder.spike, spike))
        .firstOrNull;
    if (seeder != null) {
      destroyEnemy(seeder);
      return;
    }
    spike.near = math.min(spike.near + ShooterMode.spikeHit, spike.far);
    gameRef.score += ShooterMode.spikeScore;
    gameRef.play(Sound.spike);
    if (spike.near >= spike.far) {
      _spikes.remove(spike);
    }
  }

  /// Blows [enemy] up where it is along the tube and adds its score.
  ///
  /// As in Tube Shooter, a seeder's spike stays, and a splitter splits.
  @visibleForTesting
  void destroyEnemy(RunnerEnemyComponent enemy) {
    gameRef.score += enemy.kind.score;
    _kills++;
    gameRef.play(Sound.explosion);
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

  /// Sets the run's play end to [playEnd], along with its exit and the next
  /// round's rim.
  void _endRunAt(double playEnd) {
    final run = this.run!;
    final (:exit, :rim) = run.endAt(playEnd);
    run
      ..playEnd = playEnd
      ..exit = exit
      ..next = (tube: run.next.tube, rim: rim);
  }

  /// Blows the ship up, fades it out, and takes a life. The enemies, spikes
  /// and shots go, and the ship flies at [flightSpeed] again.
  void _destroyShip() {
    gameRef.lives--;
    gameRef.play(Sound.crash);
    explosionGroup.add(
      RunnerExplosionComponent(
        position: ship.position.clone(),
        angle: ship.angle,
        scale: ship.scale.clone(),
        color: TubeColors.ship,
      ),
    );
    ship.fadeOut();
    _kills = 0;
    // On a run, the enemies come again, unless the run's end already shows.
    if (run case final run?
        when run.playEnd - (run.tube.course?.ease ?? 0) > _farRing) {
      _queue.insertAll(0, [for (final enemy in _enemies) enemy.kind]);
      _endRunAt(double.infinity);
    }
    _clearEnemies();
    _setState(RunnerState.dying);
  }

  /// Shows READY, until a tap or a key.
  void _waitForPlayer() {
    gameRef.camera.viewport.add(gameRef.readyText);
    _setState(RunnerState.ready);
  }

  /// Starts the game, or resumes it after the ship was lost.
  ///
  /// The first enemy comes [firstEnemy] seconds later, and the
  /// [firstSeeders] come first again.
  void _beginPlay() {
    gameRef.readyText.removeFromParent();
    _untilEnemy = firstEnemy;
    _spawned = 0;
    _lastKind = null;
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

  /// Starts a new game in this mode, waiting at READY.
  ///
  /// The explosions go, the lives are full, the time in the tube and the
  /// score start from 0, and the world runs at the game's speed again.
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

  /// Ends a wait: starts a new game if the game is over, or else plays.
  void endWait() {
    if (_state == RunnerState.over) {
      _newGame();
    } else {
      _beginPlay();
    }
  }

  /// Makes the tube's paths again when something they show changed, and
  /// places the enemies, shots and explosions where they show.
  ///
  /// The paths change when the ship flies or changes lanes, an enemy's flash
  /// or a bolt changes, or the view changes.
  ///
  /// When the last enemy comes, the lane it came in flashes over the enemy's
  /// [RunnerEnemyComponent.flashTime]. The lane fades from the enemy's
  /// colour to its own. If it's the ship's lane, it fades instead from the
  /// ship's colour with the enemy's added. Its lines and a seeder's spike
  /// glow, and the glow fades out. With the renderers that don't draw glows,
  /// wider, see-through copies in the enemy's colour stand in for the glow.
  ///
  /// While the zappers pulse, their bolts zigzag down their lanes to the
  /// ship's ring. They glow in their colour, or have wider, see-through
  /// copies.
  void _updateTube() {
    // The ship knows its lane only after it loads. As in Tube Shooter, its
    // lane shows only during play.
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
    // The explosions remove themselves when they're done.
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
    // The halo goes under the lines whose glow it stands in for and over
    // the others, as a glow would.
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

  /// Brings, climbs and splits the enemies over [dt] seconds of the game.
  ///
  /// The first enemy comes at [firstEnemy]. After that, the next one comes
  /// [enemyPeriod] after the last, with the period it had then. Each
  /// comes in a random lane. Its kind is picked at random among the
  /// [enemyKinds], or on a [run], it is the next in the run's sequence. On
  /// a run, none comes from past where its play ends.
  ///
  /// The enemies and the climbers' shots climb, and the splitters split when
  /// they get within [RunnerSplitterComponent.splitAhead] of the ship.
  void _updateEnemies(double dt) {
    _untilEnemy -= dt;
    if (_untilEnemy <= 0) {
      _untilEnemy += enemyPeriod;
      final run = this.run;
      if (run != null) {
        if (spawning && _farRing <= run.playEnd && _queue.isNotEmpty) {
          addEnemy(_queue.removeAt(0), random.nextInt(tube.laneCount));
        }
      } else if (spawning) {
        // The first ones are seeders. After them, each enemy is of another
        // kind than the last one, except that seeders can follow seeders.
        final last = _lastKind;
        final picks = _spawned < firstSeeders
            ? const [EnemyKind.seeder]
            : [
                for (final kind in enemyKinds)
                  if (kind != last || kind == EnemyKind.seeder) kind,
              ];
        // Picking among a single kind would still take a number from
        // [random], and shift the random sequence for all that comes after.
        final kind =
            picks[picks.length == 1 ? 0 : random.nextInt(picks.length)];
        _spawned++;
        _lastKind = kind;
        addEnemy(kind, random.nextInt(tube.laneCount));
      }
    }
    // Sets the run's end when the last enemies' rings are near enough to
    // tell. The end goes past those rings, and past where the run's bends
    // still show.
    if (run case final run?
        when run.playEnd == double.infinity && _queue.length <= endSpawns) {
      final spacing = firstEnemyPeriod * flightSpeed;
      final ease = run.tube.course?.ease ?? 0;
      _endRunAt(
        _farRing + math.max(spacing * _queue.length + endMargin, ease),
      );
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

  /// Replaces [splitter] with two climbers where it is, as in Tube Shooter.
  ///
  /// The climbers flip from its lane onto the lanes on either side. At an
  /// open tube's end, a climber with no lane on its side stays in the
  /// splitter's lane. The climbers don't flash, as they didn't come down the
  /// tube.
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
    // In the splitter's place, so the enemies stay nearest first.
    _enemies.insertAll(index, climbers);
    addAll(climbers);
    _tubeFlown = double.nan;
  }

  /// Brings an enemy of [kind], one of [enemyKinds], in [lane].
  ///
  /// The enemy starts where it comes into sight as its flash ends. That is
  /// past the point where the tube will then hide the lane from the ship, at
  /// the ship's current speed, by as far as the enemy climbs over
  /// [RunnerEnemyComponent.flashTime]. If the farthest ring across the tube
  /// is nearer, the enemy starts there instead.
  @visibleForTesting
  void addEnemy(EnemyKind kind, int lane) {
    const flashTime = RunnerEnemyComponent.flashTime;
    final sight = endlessTube.sightAlong(
      lane,
      _flown + speed * flashTime,
      view,
      until: run?.exit ?? double.infinity,
    );
    final far = math.min(
      _farRing,
      sight + RunnerEnemyComponent.climbSpeed * flashTime,
    );
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
        enemy = RunnerEdgeWalkerComponent(lane, far);
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

  /// Returns [base] with [light] added to it at [amount] times its strength.
  ///
  /// The colours add up as lights do: channel by channel, up to full.
  static Color _addLight(Color base, Color light, double amount) => Color.from(
    alpha: base.a,
    red: math.min(1, base.r + amount * light.r),
    green: math.min(1, base.g + amount * light.g),
    blue: math.min(1, base.b + amount * light.b),
  );

  /// Removes [old], if any, and returns a new component that fills [quads]
  /// in [color] with [glow].
  ///
  /// The new component goes into [tubeGroup]. Returns null when [quads] is
  /// empty.
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

  /// The step round the tube that the ship is on.
  int get shipStep => ship.step;
}

/// A component under a [RunnerMode], which plays by its rules.
mixin InRunnerMode on Component {
  /// The mode that this component is under, or was under when it called
  /// [findRunner].
  RunnerMode get runner => _runner ??= findParent<RunnerMode>()!;
  RunnerMode? _runner;

  /// Finds the mode that this component is under.
  ///
  /// This way [runner] still returns that mode after the component has left
  /// it, as when the component finishes loading after it was removed.
  void findRunner() => _runner ??= findParent<RunnerMode>();
}
