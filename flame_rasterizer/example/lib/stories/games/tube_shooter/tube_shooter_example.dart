import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/game_sounds.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/bolts_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/lane_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/spawn_dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/spikes_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_field_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/tube_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_glow.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

part 'tube_shooter_run.dart';
part 'tube_shooter_snapshot.dart';

/// The game's states.
enum TubeState() {
  /// The tube zooms in from afar.
  zoom,

  /// READY shows until a tap or a key starts the round, or resumes it after
  /// a lost ship.
  ready,

  /// The round is on.
  play,

  /// The ship was destroyed. Next, it comes back, or the game ends.
  dying,

  /// The round's enemies are gone, and the ship drops down its lane.
  drop,

  /// With [TubeShooterExample.runs] on, the ship flies on from the drop, down
  /// an endless tube.
  run,

  /// The run is over: the ship flies out of its tube, onto the next round's
  /// rim.
  arrive,

  /// The game is over, and stands still until a tap, or Enter, starts a new
  /// one.
  over,
}

/// A tube shooter inspired by Atari's Tempest, drawn entirely with paths: see
/// [description].
///
/// In the world, the tube's axis is at the origin. The camera looks at it, or
/// at the middle of an open tube's drawing. Each round plays on the next
/// level's tube, starting from [firstLevel]. A new game after Game Over
/// starts at the round reached. Subclasses pick the component that draws a
/// path: see [pathComponent].
///
/// Given the snapshot of a game with another renderer, it goes on from there:
/// see [TubeShooterSnapshots].
abstract class TubeShooterExample({
  required super.status,
  super.random,

  /// Which of the [levels] the first round plays.
  final int firstLevel = 0,
  TubeShooterSnapshot? from,
}) extends TubeHost {
  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG, which goes on from [from], if any, at its first level and pace.
  factory TubeShooterExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    int firstLevel = 0,
    TubeShooterSnapshot? from,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeShooterExample(
          status: status,
          random: random,
          firstLevel: from?.firstLevel ?? firstLevel,
          from: from,
        )
      : RasterizerTubeShooterExample(
          status: status,
          renderer: renderer,
          random: random,
          firstLevel: from?.firstLevel ?? firstLevel,
          from: from,
        );

  static const description = '''
    A tube shooter in vector lines. Everything in the game, text included, is
    a Flutter Path. RasterizerPathComponent draws them with the renderer that
    the Renderer knob picks; with Flame SVG, Flame's PathComponent does.

    Move the ship round the rim of the tube with the arrow keys, A and D, by
    dragging left and right, or a lane per scroll of the mouse wheel. On a
    Steam Deck, a trackpad set to Steam Input's Scroll Wheel mode turns it
    round as a finger circles. Fire down its lane with the space bar, or while
    dragging. Enter, or a double tap, purges the tube once a round. Tap or
    press a key to start a round, and to go on after losing a ship.

    Five kinds of enemies climb the tube. Once they're gone, the ship drops
    down its lane to the next of eight tubes, and any spike left in that lane
    destroys it. Each round is 5% faster than the last, and a game that starts
    at a later level goes as fast as if it had started at the first. After
    Game Over, a new game starts at the round reached, as fast.

    The game makes some paths again every frame, such as the tube's during the
    zoom. It shares others among many components, such as the enemies'
    shapes. The Glow knob makes the lines glow: the mesh renderer draws the
    glow with them, and the other renderers draw it with a shader over the
    world. The Level knob shows the round's level, and starts a new game at
    the level it picks. The other knobs keep the stars drifting, turn the
    sounds on and off, zoom the camera and change the game's speed. The Runs
    knob, a prototype, flies the ship on from a closed tube's drop down Tube
    Runner's endless tube, for 20 seconds, then out of it, onto the next
    round's rim. A new
    renderer's game goes on with the same round, ship, enemies and shots,
    from where they were. The bar under the game shows the renderer, the
    frame times, the renderer's own numbers and the paths made each second.

    Inspired by Atari's Tempest (1981).
  ''';

  /// How long the zoom takes, in seconds.
  static const zoomTime = 1.0;

  /// How far in front of the tube the eye starts the zoom, in tube units.
  static const zoomDistance = 12.0;

  /// How long the drop takes, in seconds.
  static const dropTime = 2.0;

  /// How long a run lasts, with [runs] on, once the drop is over, in seconds
  /// of the game: see [TubeState.run].
  static const runTime = 20.0;

  /// How far a run's tube eases into its bends, and out of them, in tube
  /// units.
  static const runEase = 8.0;

  /// How long the ship takes to arrive on the next round's rim after a run,
  /// in seconds of the game.
  static const arriveTime = 4.0;

  /// How long the ship's lane takes to fade in on a run, in seconds.
  static const laneFadeTime = 0.3;

  /// How long PURGE shows once the purge is used, in seconds.
  static const purgeTime = 1.0;

  /// The glow of the shapes' lines: 3 times as wide as the lines, and thinner
  /// with depth, as they are.
  static const lineGlow = RasterizerGlow.widths(3);

  /// The glow of the lines of the tube, its lane, the spikes and the bolts:
  /// twice as wide as the lines, and thinner with depth, as they are.
  static const tubeGlow = RasterizerGlow.widths(2);

  /// How close in depth a shot must be to what it hits.
  static const hitWindow = 0.04 * Tube.depth;

  /// How much a shot takes off a spike.
  static const spikeHit = 0.06 * Tube.depth;

  /// What a shot that hits a spike scores.
  static const spikeScore = 2;

  /// The snapshot that it goes on from, if any.
  final TubeShooterSnapshot? _from = from;

  final tubeGroup = Component();
  final spawnGroup = Component(priority: 1);
  final enemyGroup = Component(priority: 1);
  final shotGroup = Component(priority: 2);
  final explosionGroup = Component(priority: 5);
  final player = PlayerComponent(from: from?.player);
  final tube = TubeComponent();
  final spikes = SpikesComponent();
  final bolts = BoltsComponent();
  final starField = StarFieldComponent();

  /// The enemies in the tube, from when they're added until they're gone.
  final enemies = <EnemyComponent>{};

  /// The ship's shots in the tube.
  final shots = <ShotComponent>{};

  /// The enemies' shots in the tube.
  final enemyShots = <EnemyShotComponent>{};

  /// The enemies still to come this round, as dots at the far end, the next
  /// one last. Those arriving are among them.
  final spawns = <SpawnDotComponent>[];

  /// Whether enemies come; tests turn it off.
  @visibleForTesting
  bool spawning = true;

  TubeState get state => _state;
  TubeState _state = TubeState.zoom;
  double _stateTime = 0;

  /// The run, from the drop it starts with to the ship's arrival on the next
  /// round's rim, with [runs] on.
  _Run? _run;

  /// Whether the ship was destroyed on its drop, so that the next round comes
  /// rather than the same one again.
  bool _dyingOnDrop = false;

  int round = 0;
  bool purgeReady = true;

  /// The round's level.
  Level get level => levels[_levelIndex];

  /// The index of the round's level in [levels].
  int get levelIndex => _levelIndex;
  late int _levelIndex = firstLevel;

  /// Called with [levelIndex] each time a round starts.
  void Function(int levelIndex)? onLevel;

  /// Where the camera looks, in tube units.
  Offset _look = Offset.zero;

  /// Where the camera looked as the zoom began, in tube units.
  Offset _lookFrom = Offset.zero;

  /// Where the camera looks, in the world's units.
  Offset _aim = Offset.zero;

  /// The view's version at the last update.
  int _lastVersion = -1;

  /// How fast the round goes: as fast as if the game had started at the first
  /// level, so 1 on the first level's first round, and faster in each later
  /// round.
  double get pace => math.pow(roundSpeedUp, firstLevel + round - 1).toDouble();

  /// Seconds since the last enemy came, at the first round's pace.
  double _sinceSpawn = 0;

  /// Seconds into the zappers' pulse period, at the first round's pace. The
  /// pulse comes at the period's end.
  double _pulseClock = 0;

  /// Whether the zappers are pulsing, in play.
  bool get isPulsing =>
      _state == TubeState.play &&
      _pulseClock >= level.pulsePeriod - level.pulseTime;

  /// Whether the zappers flash white, just before a pulse.
  bool get isWarning {
    final pulse = level.pulsePeriod - level.pulseTime;
    return _state == TubeState.play &&
        _pulseClock < pulse &&
        _pulseClock >= pulse - level.pulseWarning;
  }

  /// The round's number, at the middle, on the zoom.
  final _roundBanner = VectorTextComponent(capHeight: TubeHost.bannerCap);

  /// PURGE READY, under the round's number on the zoom: each round recharges
  /// the purge.
  final _purgeReadyText = VectorTextComponent(
    text: 'PURGE READY',
    capHeight: TubeHost.hudCap,
    below: 1.2 * TubeHost.bannerCap,
  );

  /// PURGE, for [purgeTime] once the purge is used.
  final _purgeText = VectorTextComponent(
    text: 'PURGE',
    capHeight: TubeHost.bannerCap,
  );

  /// The seconds left before PURGE goes.
  double _purgeLeft = 0;

  @override
  bool get canMove =>
      _state == TubeState.play ||
      (_state == TubeState.run && _stateTime < runTime);
  bool get canFire => _state == TubeState.play || _state == TubeState.drop;

  @override
  bool get isWaiting => isReady || isOver;

  @override
  bool get isReady => _state == TubeState.ready;

  @override
  bool get isOver => _state == TubeState.over;

  /// The Drifting stars knob's value: whether the stars stay, drifting,
  /// between the zoom and the drop. If not, they only show during those.
  bool get driftingStars => _driftingStars;
  bool _driftingStars = true;

  set driftingStars(bool value) {
    if (value != _driftingStars) {
      _driftingStars = value;
      if (isLoaded) {
        _updateStars();
      }
    }
  }

  /// The Runs knob's value: whether, after a closed tube's drop, the ship
  /// flies on down an endless tube for [runTime], before it flies onto the
  /// next round's rim: see [TubeState.run]. A prototype, off by default.
  bool runs = false;

  /// The Glow knob's value: whether the lines glow.
  ///
  /// If [rendererGlows], the lines glow with [lineGlow] and [tubeGlow], so a
  /// change imports them again: the tube's paths, as a change of the view
  /// does, and the shapes in [keepStroke]. In a still world, where nothing
  /// updates, this happens at once. Otherwise, a [TubeGlow] is the camera's
  /// post process while it's on.
  bool get glow => _glow;
  bool _glow = false;

  set glow(bool value) {
    if (value != _glow) {
      _glow = value;
      if (rendererGlows) {
        view.invalidate();
        if (isLoaded && world.timeScale == 0) {
          _updateStillLines();
        }
      } else if (isLoaded) {
        _updateGlow();
      }
    }
  }

  /// Makes a [TubeGlow] the camera's post process if [glow] is on, or
  /// removes it.
  void _updateGlow() {
    camera.postProcess = _glow ? TubeGlow(this) : null;
  }

  /// The Sound knob's value: whether the game plays its sounds. Off by
  /// default, so that tests stay silent.
  ///
  /// The sounds load the first time it's on, and stay loaded when it's off.
  bool get sound => _sound;
  bool _sound = false;

  set sound(bool value) {
    _sound = value;
    if (value && isLoaded) {
      _loadSounds();
    }
  }

  /// The sounds, once [sound] was on.
  GameSounds? _sounds;

  /// Loads the sounds, unless they're loaded or loading.
  Future<void> _loadSounds() async {
    if (_sounds == null) {
      await (_sounds = GameSounds([
        for (final sound in Sound.values) sound.path,
      ])).load();
    }
  }

  /// Plays [sound], if the Sound knob is on and the sounds are loaded.
  void _play(Sound sound) {
    if (_sound) {
      _sounds?.play(sound.path);
    }
  }

  /// The shapes' glow, if the Glow knob is on and the renderer draws it.
  @override
  RasterizerGlow? get shapeGlow => _glow && rendererGlows ? lineGlow : null;

  /// Twice the widest lane, a shape's longest side, as explosions grow to
  /// twice their size.
  @override
  double get shapeGrowth => 2;

  /// Does what updates would do in a moving world: makes the tube's paths
  /// again for the view, places everything on the tube, and gives the shapes
  /// their stroke and glow.
  void _updateStillLines() {
    tube.update(0);
    spikes.update(0);
    bolts.update(0);
    for (final component in world.descendants()) {
      switch (component) {
        case final LaneComponent onLane:
          onLane.place();
        case final DotComponent dot:
          dot.place();
        case final PlayerComponent ship:
          ship.place();
      }
    }
    // In the camera's backdrop, out of the world.
    for (final star in starField.stars) {
      star.place();
    }
    for (final group in [player, enemyGroup, shotGroup, explosionGroup]) {
      group.descendants().whereType<PathComponent>().forEach(keepStroke);
    }
  }

  /// Replaces [old], if any, with a component that fills [path], if any, in
  /// [color], and returns it.
  ///
  /// The new component goes in the tube's group, at [priority]. The renderer
  /// imports a path only once, so a changed path needs a new component.
  PathComponent? replacePath(
    PathComponent? old,
    Path? path,
    Color color, {
    int priority = 0,
  }) {
    old?.removeFromParent();
    final bounds = path?.getBounds();
    if (path == null || bounds == null || bounds.isEmpty) {
      return null;
    }
    countPath();
    final component = pathComponent(
      path,
      Paint()..color = color,
      position: Vector2(bounds.left, bounds.top),
      maxSize: math.max(bounds.width, bounds.height) / view.devicePixel,
      priority: priority,
      glow: _glow && rendererGlows ? tubeGlow : null,
    );
    tubeGroup.add(component);
    return component;
  }

  @override
  Future<void> onLoad() async {
    // Fits the view before the ship loads in addAll: it sizes its import for
    // the view.
    await super.onLoad();
    world.addAll([
      tubeGroup,
      spawnGroup,
      enemyGroup,
      shotGroup,
      player,
      explosionGroup,
      tube,
      spikes,
      bolts,
    ]);
    // Under the world, out of the glow's post process.
    camera.backdrop.add(starField);
    if (_glow && !rendererGlows) {
      _updateGlow();
    }
    // Before the first round, so that its zoom sounds.
    if (_sound) {
      await _loadSounds();
    }
    if (_from case final from?) {
      _restoreRound(from);
    } else {
      _nextRound();
    }
    startStatus();
  }

  @override
  void onRemove() {
    _sounds?.dispose();
    super.onRemove();
  }

  @override
  void update(double dt) {
    _sounds?.nextFrame();
    super.update(dt);
  }

  /// Before the world's components move, and before [TubeComponent] makes the
  /// tube's paths for the view.
  @override
  void advance(double dt) {
    _step(dt);
    _aimCamera();
    _drawRun();
    tube.lane = _state == TubeState.play ? player.lane : null;
    // In a still world, where nothing updates, applies a change of the view,
    // such as a resize or a zoom.
    if (world.timeScale == 0 && view.version != _lastVersion) {
      _updateStillLines();
    }
    _lastVersion = view.version;
  }

  @override
  void afterUpdate(double dt) {
    _placeArriving();
    roundText.text = _state == TubeState.run ? _runClock : 'ROUND $round';
    // In real time, so that it goes in a still world too.
    if (_purgeLeft > 0) {
      _purgeLeft -= dt;
      if (_purgeLeft <= 0) {
        _purgeText.removeFromParent();
      }
    }
  }

  /// Points the camera at [_look].
  void _aimCamera() {
    final aim = _look * view.rimScale;
    if (aim != _aim) {
      _aim = aim;
      camera.viewfinder.position.setValues(aim.dx, aim.dy);
    }
  }

  void _setState(TubeState state) {
    _state = state;
    _stateTime = 0;
    forgetWaitPointers();
    _updateStars();
  }

  /// Shows the stars if they drift, on the zoom and the drop, and after a
  /// ship lost on the drop. Otherwise hides them, at once in a still world,
  /// where nothing fades.
  void _updateStars() {
    if (driftingStars ||
        _state == TubeState.zoom ||
        _state == TubeState.drop ||
        _state == TubeState.run ||
        _state == TubeState.arrive ||
        (_state == TubeState.dying && _dyingOnDrop)) {
      starField.show();
    } else if (world.timeScale == 0) {
      starField.stop();
    } else {
      starField.hide();
    }
  }

  /// Applies the game's rules over [dt] seconds of the world's time.
  void _step(double dt) {
    _stateTime += dt;
    switch (_state) {
      case TubeState.zoom:
        final progress = math.min(1.0, _stateTime / zoomTime);
        final left = math.pow(1 - progress, 3).toDouble();
        view.eyeShift = -zoomDistance * left;
        _look = Offset.lerp(view.tube.center, _lookFrom, left)!;
        if (progress == 1) {
          player.isVisible = true;
          _roundBanner.removeFromParent();
          _purgeReadyText.removeFromParent();
          _waitForPlayer();
        }
      case TubeState.play:
        final wasPulsing = isPulsing;
        _pulseClock = (_pulseClock + dt * pace) % level.pulsePeriod;
        if (!wasPulsing &&
            isPulsing &&
            enemies.any(
              (enemy) => enemy is ZapperComponent && enemy.isZapping,
            )) {
          _play(Sound.zap);
        }
        _spawn(dt);
        _collide();
        if (_state == TubeState.play && spawns.isEmpty && enemies.isEmpty) {
          for (final shot in [...enemyShots]) {
            discard(shot);
          }
          _setState(TubeState.drop);
          _play(Sound.drop);
          if (runs && !view.tube.isOpen) {
            _run = _Run(
              view.tube,
              level.color,
              levels[(_levelIndex + 1) % levels.length],
            );
          }
        }
      case TubeState.drop:
        final progress = math.min(1.0, _stateTime / dropTime);
        player.depth = view.eyeShift = _run == null
            ? Tube.depth * progress * progress
            : _Run.dropDepth(progress);
        _run?.flown = view.eyeShift;
        _collide();
        if (_state == TubeState.drop && progress == 1) {
          if (_run == null) {
            _nextRound();
          } else {
            _beginRun();
          }
        }
      case TubeState.run:
        _stepRun();
      case TubeState.arrive:
        _stepArrive();
      case TubeState.dying:
        if (_stateTime >= TubeHost.respawnTime) {
          if (lives == 0) {
            _gameOver();
          } else if (_dyingOnDrop) {
            _nextRound();
          } else {
            player.revive();
            _waitForPlayer();
          }
        }
      case TubeState.ready || TubeState.over:
        break;
    }
  }

  /// Replaces each dot that has arrived with its enemy, at the far end of its
  /// lane, and starts the next dot arriving.
  ///
  /// A dot starts arriving every level's `spawnPeriod`, while fewer than the
  /// level's `maxEnemies` are in the tube or arriving.
  void _spawn(double dt) {
    for (final spawn in spawns.where((spawn) => spawn.hasArrived).toList()) {
      spawns.remove(spawn);
      spawn.removeFromParent();
      addEnemy(spawn.kind.create(lane: spawn.lane, depth: Tube.depth));
    }
    _sinceSpawn += dt * pace;
    final waiting = spawns.where((spawn) => !spawn.isArriving);
    final arriving = spawns.length - waiting.length;
    if (!spawning ||
        waiting.isEmpty ||
        enemies.length + arriving >= level.maxEnemies ||
        _sinceSpawn < level.spawnPeriod) {
      return;
    }
    _sinceSpawn = 0;
    waiting.last.arrive();
  }

  /// Adds an enemy of [kind] to come next, as a dot [at] lanes round the far
  /// end, which goes on [from] a dot in a game with another renderer, if
  /// given.
  void _addSpawn(EnemyKind kind, double at, {SpawnSnapshot? from}) {
    final spawn = SpawnDotComponent(kind, at: at, from: from);
    spawns.add(spawn);
    spawnGroup.add(spawn);
  }

  /// Removes all the enemies still to come.
  void clearSpawns() {
    spawnGroup.removeAll(spawns);
    spawns.clear();
  }

  /// Resolves the hits between things in the same lane that [_meet].
  ///
  /// The ship's shots shorten spikes, and destroy enemies' shots and the
  /// enemies that can be shot. An enemy's shot at the rim, an enemy as its
  /// kind does, and a spike on the drop destroy the ship in their lane.
  void _collide() {
    for (final shot in [...shots]) {
      final tip = spikes.tipOf(shot.lane);
      if (tip != null && shot.depth >= tip) {
        spikes.shorten(shot.lane, spikeHit);
        score += spikeScore;
        _play(Sound.spike);
        discard(shot);
        continue;
      }
      final enemyShot = enemyShots
          .where((other) => other.lane == shot.lane && _meet(shot, other))
          .firstOrNull;
      if (enemyShot != null) {
        discard(enemyShot);
        discard(shot);
        continue;
      }
      final enemy = enemies
          .where(
            (other) =>
                other.canBeShot &&
                other.currentLane == shot.lane &&
                _meet(shot, other),
          )
          .firstOrNull;
      if (enemy != null) {
        discard(shot);
        destroy(enemy);
      }
    }
    for (final enemyShot in [...enemyShots]) {
      if (enemyShot.depth <= 0) {
        discard(enemyShot);
        if (enemyShot.lane == player.lane) {
          _destroyShip();
        }
      }
    }
    if (_state == TubeState.play &&
        enemies.any((enemy) => enemy.destroysShip(player.lane))) {
      _destroyShip();
    }
    final tip = spikes.tipOf(player.lane);
    if (_state == TubeState.drop && tip != null && tip <= player.depth) {
      _destroyShip();
    }
  }

  /// Returns whether [a] and [b], in the same lane, meet: within [hitWindow] in
  /// depth, or passing each other since their last update.
  static bool _meet(LaneComponent a, LaneComponent b) {
    final now = a.depth - b.depth;
    final before = a.previousDepth - b.previousDepth;
    return now.abs() <= hitWindow || now.sign != before.sign;
  }

  /// Adds [enemy] to the tube.
  void addEnemy(EnemyComponent enemy) {
    enemies.add(enemy);
    enemyGroup.add(enemy);
  }

  /// Fires a shot from the ship down [lane], from [depth].
  void fire(int lane, double depth) {
    final shot = ShotComponent(lane: lane, depth: depth);
    shots.add(shot);
    shotGroup.add(shot);
    _play(Sound.fire);
  }

  /// Fires a shot from [enemy] up its lane, if fewer than the level's
  /// `maxEnemyShots` are in the tube.
  void fireAt(EnemyComponent enemy) {
    if (_state != TubeState.play || enemyShots.length >= level.maxEnemyShots) {
      return;
    }
    final shot = EnemyShotComponent(
      lane: enemy.currentLane,
      depth: enemy.depth,
    );
    enemyShots.add(shot);
    shotGroup.add(shot);
    _play(Sound.enemyFire);
  }

  /// Returns which way an enemy at the rim in [lane] goes toward the ship: 1 or
  /// -1, or 0 in the ship's lane.
  int towardShip(int lane) {
    final tube = view.tube;
    final ahead = player.lane - lane;
    if (ahead == 0 || tube.isOpen) {
      return ahead.sign;
    }
    return ahead % tube.laneCount <= tube.laneCount ~/ 2 ? 1 : -1;
  }

  /// Replaces [splitter] with two climbers, which flip from its lane onto the
  /// lanes on either side. A climber with no lane on its side, at an open
  /// tube's end, stays in the splitter's lane.
  void split(SplitterComponent splitter) {
    if (!enemies.contains(splitter)) {
      return;
    }
    discard(splitter);
    final tube = view.tube;
    for (final side in [-1, 1]) {
      final climber = ClimberComponent(
        lane: splitter.lane,
        depth: splitter.depth,
      );
      final to = tube.neighbour(splitter.lane, side);
      if (to != null) {
        climber.flip(to, tube);
      }
      addEnemy(climber);
    }
  }

  /// Destroys [enemy] and adds its score. A splitter splits instead, unless
  /// [purged].
  void destroy(EnemyComponent enemy, {bool purged = false}) {
    if (!enemies.contains(enemy)) {
      return;
    }
    _explode(enemy, enemy.depth, rayColor: enemy.kind.color);
    _play(Sound.explosion);
    score += enemy.kind.score;
    if (enemy is SplitterComponent && !purged) {
      split(enemy);
    } else {
      discard(enemy);
    }
  }

  /// Removes [component] from the tube.
  void discard(LaneComponent component) {
    component.removeFromParent();
    forget(component);
  }

  /// Stops tracking [component], which is gone.
  void forget(LaneComponent component) {
    switch (component) {
      case EnemyComponent():
        enemies.remove(component);
      case ShotComponent():
        shots.remove(component);
      case EnemyShotComponent():
        enemyShots.remove(component);
    }
  }

  /// Adds an explosion where [component] is, [depth] deep in the tube, turned
  /// and scaled as it is, with its flying rays in [rayColor].
  void _explode(
    PositionComponent component,
    double depth, {
    Color? color,
    Color? rayColor,
  }) {
    explosionGroup.add(
      ExplosionComponent(
        position: component.position.clone(),
        angle: component.angle,
        scale: component.scale.clone(),
        depth: depth,
        color: color ?? TubeColors.explosion,
        rayColor: rayColor,
      ),
    );
  }

  /// Destroys every enemy in the tube, and their shots, once a round.
  void purge() {
    if (_state != TubeState.play || !purgeReady) {
      return;
    }
    purgeReady = false;
    if (!_purgeText.isMounted) {
      camera.viewport.add(_purgeText);
    }
    _purgeLeft = purgeTime;
    _play(Sound.purge);
    for (final enemy in [...enemies]) {
      destroy(enemy, purged: true);
    }
    for (final shot in [...enemyShots]) {
      discard(shot);
    }
  }

  /// Blows the ship up, fades it out, and takes a life.
  ///
  /// The enemies in the tube go back to the far end of their lanes, to come
  /// again, and all the shots go.
  void _destroyShip() {
    if (_state != TubeState.play && _state != TubeState.drop) {
      return;
    }
    _dyingOnDrop = _state == TubeState.drop;
    _endRun();
    lives--;
    _explode(player, player.depth, color: TubeColors.ship);
    _play(Sound.crash);
    player.fadeOut();
    for (final spawn in spawns) {
      spawn.wander();
    }
    for (final enemy in [...enemies]) {
      _addSpawn(enemy.kind, enemy.currentLane + 0.5);
      discard(enemy);
    }
    for (final shot in [...shots, ...enemyShots]) {
      discard(shot);
    }
    _setState(TubeState.dying);
  }

  /// Starts the next round on the next level's tube, or the first round on
  /// the round's level, [arriving] from a run if so.
  void _nextRound({bool arriving = false}) {
    if (round > 0) {
      _levelIndex = (_levelIndex + 1) % levels.length;
    }
    round++;
    _startRound(arriving: arriving);
  }

  /// Starts the round on its level's tube.
  ///
  /// The round starts with its enemies at random round the far end, no
  /// spikes, the purge ready, and the ship on the tube's bottom lane. The tube
  /// zooms in through the stars, with the ship hidden until the zoom ends.
  ///
  /// [arriving] from a run, the ship flies onto the rim instead, at the step
  /// nearest its angle round the axis: see [_beginArrive].
  void _startRound({bool arriving = false}) {
    final from = view.tube;
    view.tube = level.tube;
    _lookFrom = _look;
    spikes.clear();
    clearSpawns();
    final kinds = [
      for (var i = 0; i < level.climbers; i++) EnemyKind.climber,
      for (var i = 0; i < level.splitters; i++) EnemyKind.splitter,
      for (var i = 0; i < level.seeders; i++) EnemyKind.seeder,
      for (var i = 0; i < level.zappers; i++) EnemyKind.zapper,
      for (var i = 0; i < level.edgeWalkers; i++) EnemyKind.edgeWalker,
    ]..shuffle(random);
    for (final kind in kinds) {
      _addSpawn(kind, view.tube.laneCount * random.nextDouble());
    }
    purgeReady = true;
    _sinceSpawn = level.spawnPeriod;
    _pulseClock = 0;
    for (final shot in [...shots, ...enemyShots]) {
      discard(shot);
    }
    player.revive();
    if (arriving) {
      player.step = _Run.nearestStep(from, player.step, view.tube);
      // The eye goes on as fast, with the rim ahead now.
      starField.shiftEye(-_Run.rim);
      view.eyeShift = _run!.flown - _Run.rim;
    } else {
      player
        ..startOn(view.tube)
        ..isVisible = false;
      view.eyeShift = -zoomDistance;
    }
    _roundBanner.text = 'ROUND $round';
    camera.viewport.addAll([_roundBanner, _purgeReadyText]);
    _setState(arriving ? TubeState.arrive : TubeState.zoom);
    _play(Sound.zoom);
    onLevel?.call(_levelIndex);
  }

  /// Shows READY, until a tap or a key.
  void _waitForPlayer() {
    camera.viewport.add(readyText);
    _setState(TubeState.ready);
  }

  /// Starts the round, or resumes it after a lost ship. No tap before this
  /// counts toward a double tap.
  void _beginPlay() {
    readyText.removeFromParent();
    forgetTaps();
    _setState(TubeState.play);
  }

  /// Stops the world, whatever [speed] is, and shows Game Over until a tap or
  /// Enter.
  void _gameOver() {
    world.timeScale = 0;
    _setState(TubeState.over);
    player.isVisible = false;
    camera.viewport.add(gameOverText);
  }

  /// Starts a new game in this one: no enemies, shots or explosions, a score
  /// of 0, all lives, the round that the last game reached, at its pace, and
  /// the world at [speed].
  void _newGame() {
    for (final enemy in [...enemies]) {
      discard(enemy);
    }
    explosionGroup.removeAll(explosionGroup.children.toList());
    score = 0;
    lives = TubeHost.startLives;
    gameOverText.removeFromParent();
    world.timeScale = speed;
    _endRun();
    _startRound();
  }

  @override
  void moveShipBy(double lanes) => player.moveBy(lanes);

  /// Ends a wait: starts a new game once it's over, or else the round.
  @override
  void endWait() {
    if (_state == TubeState.over) {
      _newGame();
    } else {
      _beginPlay();
    }
  }

  /// Purges.
  @override
  void onDoubleTap() => purge();

  /// Purges.
  @override
  void onEnter() => purge();

  /// Makes the ship fire while the player fires.
  @override
  void onFiringChanged() {
    if (isFiring) {
      player.beginFire();
    } else {
      player.stopFire();
    }
  }
}

/// The example with flame_rasterizer: [RasterizerPathComponent]s draw its
/// paths, with the renderer that the Renderer knob picks.
class RasterizerTubeShooterExample({
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.firstLevel,
  super.from,
}) extends TubeShooterExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerPathComponents<ExampleWorld>,
        RasterizerTubeHost {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  /// Keeps [drawing]'s stroke, and gives it the shapes' glow too. If the Glow
  /// knob changed, it imports the shape again.
  @override
  void keepStroke(PathComponent drawing, {double widths = 1}) {
    super.keepStroke(drawing, widths: widths);
    (drawing as RasterizerPathComponent).glow = shapeGlow;
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeShooterExample({
  required super.status,
  super.random,
  super.firstLevel,
  super.from,
}) extends TubeShooterExample
    with FlamePathComponents<ExampleWorld>, FlameTubeHost;
