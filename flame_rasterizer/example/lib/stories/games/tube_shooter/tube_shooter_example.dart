import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
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
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;

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

  /// The game is over, and stands still until a tap, or Enter, starts a new
  /// one.
  over,
}

/// A tube shooter inspired by Atari's Tempest, drawn entirely with paths: see
/// [description].
///
/// In the world, the tube's axis is at the origin. The camera looks at it, or
/// at the middle of an open tube's drawing. Each round plays on the next
/// level's tube, starting from [firstLevel]. Subclasses pick the component
/// that draws a path: see [pathComponent].
abstract class TubeShooterExample({
  required super.status,
  math.Random? random,

  /// Which of the [levels] a new game starts at.
  final int firstLevel = 0,
}) extends ExampleGame with DragCallbacks, KeyboardEvents {
  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG.
  factory TubeShooterExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    int firstLevel = 0,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeShooterExample(
          status: status,
          random: random,
          firstLevel: firstLevel,
        )
      : RasterizerTubeShooterExample(
          status: status,
          renderer: renderer,
          random: random,
          firstLevel: firstLevel,
        );

  static const description = '''
    A tube shooter in vector lines. Everything in the game, text included, is
    a Flutter Path. RasterizerPathComponent draws them with the renderer that
    the Renderer knob picks; with Flame SVG, Flame's PathComponent does.

    Move the ship round the rim of the tube with the arrow keys, A and D, or by
    dragging left and right. Fire down its lane with the space bar, or while
    dragging. Enter, or a double tap, purges the tube once a round. Tap or
    press a key to start a round, and to go on after losing a ship.

    Five kinds of enemies climb the tube. Once they're gone, the ship drops
    down its lane to the next of eight tubes, and any spike left in that lane
    destroys it. Each round is 5% faster than the last.

    The game makes some paths again every frame, such as the tube's during the
    zoom. It shares others among many components, such as the enemies'
    shapes. With the mesh renderer, the Glow knob makes the lines glow. The
    other knobs pick the first level, keep the stars drifting, zoom the camera
    and change the game's speed. The bar under the game shows the renderer,
    the frame times, the renderer's own numbers and the paths made each
    second.

    Inspired by Atari's Tempest (1981).
  ''';

  /// How long the zoom takes, in seconds.
  static const zoomTime = 1.0;

  /// How far in front of the tube the eye starts the zoom, in tube units.
  static const zoomDistance = 12.0;

  /// How long the drop takes, in seconds.
  static const dropTime = 2.0;

  /// The seconds from the ship's destruction to its return.
  static const respawnTime = 1.5;

  static const startLives = 3;

  /// The cap height, in logical pixels, of the round, lives, purge and score,
  /// at the bottom right.
  static const hudCap = 12.0;

  /// The cap height, in logical pixels, of the round's number on the zoom
  /// and Game Over, at the middle.
  static const bannerCap = 40.0;

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

  /// How far a drag goes to move the ship one lane, in logical pixels.
  static const dragPerLane = 40.0;

  /// The longest a drag can last and still count as a tap, in seconds.
  static const tapTime = 0.25;

  /// The farthest a drag can move and still count as a tap, in logical
  /// pixels.
  static const tapSlop = 10.0;

  /// The most seconds between the two taps of a double tap.
  static const doubleTapTime = 0.35;

  final math.Random random = random ?? math.Random();
  final view = TubeView();

  final tubeGroup = Component();
  final spawnGroup = Component(priority: 1);
  final enemyGroup = Component(priority: 1);
  final shotGroup = Component(priority: 2);
  final explosionGroup = Component(priority: 5);
  final player = PlayerComponent();
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

  /// Whether the ship was destroyed on its drop, so that the next round comes
  /// rather than the same one again.
  bool _dyingOnDrop = false;

  int round = 0;
  int score = 0;
  int lives = startLives;
  bool purgeReady = true;

  /// The round's level.
  Level get level => _level;
  late Level _level = levels[firstLevel];

  /// Where the camera looks, in tube units.
  Offset _look = Offset.zero;

  /// Where the camera looked as the zoom began, in tube units.
  Offset _lookFrom = Offset.zero;

  /// Where the camera looks, in the world's units.
  Offset _aim = Offset.zero;

  /// The view's version at the last update.
  int _lastVersion = -1;

  /// How fast the round goes: 1 in the first round, faster in each later one.
  double get pace => math.pow(roundSpeedUp, round - 1).toDouble();

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

  final _roundText = VectorTextComponent(capHeight: hudCap, line: 3);
  final _livesText = VectorTextComponent(capHeight: hudCap, line: 2);
  final _purgeText = VectorTextComponent(capHeight: hudCap, line: 1);
  final _scoreText = VectorTextComponent(capHeight: hudCap, line: 0);
  final _roundBanner = VectorTextComponent(capHeight: bannerCap);

  /// READY, in the camera's viewport while the game waits for the player.
  final readyText = VectorTextComponent(text: 'READY', capHeight: bannerCap);

  /// Game Over, in the camera's viewport once the game is over.
  final gameOverText = VectorTextComponent(
    text: 'GAME OVER',
    capHeight: bannerCap,
  );

  /// How many paths the game made in the last second, for the tube, its lane,
  /// the spikes and the bolts, as the status bar shows.
  int get pathsPerSecond => _pathsPerSecond;
  int _pathsPerSecond = 0;
  int _paths = 0;
  double _pathsTime = 0;

  /// The game's own time, which the Speed knob doesn't scale, to time taps.
  double _clock = 0;

  /// Each drag's start time and distance moved, to tell taps from drags.
  final _drags = <int, ({double start, double distance})>{};

  /// When the last tap was, for double taps.
  double _lastTap = double.negativeInfinity;

  /// The pointers that went down while the game waits, at READY or Game
  /// Over. Each ends the wait when it goes up, as a tap; pointers that were
  /// already down don't.
  final _waitPointers = <int>{};

  /// The pointers that went down while the game wasn't waiting. The ship
  /// fires while any of them is down, or while [_fireKey] is held.
  final _firePointers = <int>{};

  /// The keys that move the ship, fire and purge, by their places on the
  /// keyboard, whatever its layout.
  static final _leftKeys = {
    PhysicalKeyboardKey.arrowLeft,
    PhysicalKeyboardKey.keyA,
  };
  static final _rightKeys = {
    PhysicalKeyboardKey.arrowRight,
    PhysicalKeyboardKey.keyD,
  };
  static const _fireKey = PhysicalKeyboardKey.space;
  static final _purgeKeys = {
    PhysicalKeyboardKey.enter,
    PhysicalKeyboardKey.numpadEnter,
  };

  /// The keys that don't end a wait for the player on their own.
  static final _modifierKeys = {
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
    PhysicalKeyboardKey.capsLock,
    PhysicalKeyboardKey.fn,
  };

  /// The keys held that went down while the game had the focus.
  final _heldKeys = <PhysicalKeyboardKey>{};

  /// Where the keys held move the ship: 1 to the right along the bottom, -1
  /// to the left, or 0.
  int get keyDirection =>
      (_heldKeys.any(_rightKeys.contains) ? 1 : 0) -
      (_heldKeys.any(_leftKeys.contains) ? 1 : 0);

  bool get canMove => _state == TubeState.play;
  bool get canFire => _state == TubeState.play || _state == TubeState.drop;

  /// Whether a tap ends a wait, rather than firing.
  bool get _isWaiting => _state == TubeState.ready || _state == TubeState.over;

  /// The Speed knob's value. It sets the world's time scale, except while the
  /// game is over and the world stands still.
  @override
  double get speed => _speed;
  double _speed = 1;

  @override
  set speed(double value) {
    _speed = value;
    if (_state != TubeState.over) {
      world.timeScale = value;
    }
  }

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

  /// The Glow knob's value: whether the lines glow, with [lineGlow] and
  /// [tubeGlow]. Only the mesh renderer draws glows.
  ///
  /// A change imports the lines again: the tube's paths, as a change of the
  /// view does, and the shapes in [keepStroke]. In a still world, where
  /// nothing updates, this happens at once.
  bool get glow => _glow;
  bool _glow = false;

  set glow(bool value) {
    if (value != _glow) {
      _glow = value;
      view.invalidate();
      if (isLoaded && world.timeScale == 0) {
        _updateStillLines();
      }
    }
  }

  /// The shapes' glow, if the Glow knob is on.
  RasterizerGlow? get _shapeGlow => _glow ? lineGlow : null;

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
    for (final group in [player, enemyGroup, shotGroup, explosionGroup]) {
      group.descendants().whereType<PathComponent>().forEach(keepStroke);
    }
  }

  /// Creates a component of the game's renderer that draws [path] with
  /// [paint], and with [glow] if the renderer draws glows.
  PathComponent pathComponent(
    Path path,
    Paint paint, {
    Vector2? position,
    Anchor? anchor,
    double? maxSize,
    int? priority,
    RasterizerGlow? glow,
  });

  /// Creates a component that draws [shape], one of `Shapes`, stroked in
  /// [color] about its origin.
  ///
  /// All the components of a shape share one import of it, until the view
  /// changes.
  PathComponent shapeComponent(Path shape, Color color) {
    final bounds = shape.getBounds();
    return pathComponent(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = view.shapeStroke
        ..color = color,
      anchor: Anchor(-bounds.left / bounds.width, -bounds.top / bounds.height),
      // Twice the widest lane, a shape's longest side, as explosions grow to
      // twice their size.
      maxSize: 2 * Tubes.widestLane * view.rimScale / view.devicePixel,
      glow: _shapeGlow,
    );
  }

  /// Creates a component that draws `Shapes.dot`, filled in [color], about
  /// its middle.
  ///
  /// All the dots of a colour share one import, whatever their sizes.
  PathComponent dotComponent(Color color) => pathComponent(
    Shapes.dot,
    Paint()..color = color,
    anchor: Anchor.center,
    maxSize: TubeView.rimPixels,
  );

  /// Gives [drawing], made by [shapeComponent], the view's stroke width. If
  /// the width changed, this imports the shape again.
  void keepStroke(PathComponent drawing) {
    final width = view.shapeStroke;
    if (drawing.paint.strokeWidth != width) {
      drawing.paint.strokeWidth = width;
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
    _paths++;
    final component = pathComponent(
      path,
      Paint()..color = color,
      position: Vector2(bounds.left, bounds.top),
      maxSize: math.max(bounds.width, bounds.height) / view.devicePixel,
      priority: priority,
      glow: _glow ? tubeGlow : null,
    );
    tubeGroup.add(component);
    return component;
  }

  @override
  Future<void> onLoad() async {
    // Before the ship loads in addAll: it sizes its import for the view.
    _fitView();
    world.addAll([
      starField,
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
    // In the camera's viewport, as StoryGame's FPS counter is: above the
    // world, and unzoomed.
    camera.viewport.addAll([_roundText, _livesText, _purgeText, _scoreText]);
    _nextRound();
    startStatus();
  }

  @override
  Iterable<String> get exampleStats => ['$_pathsPerSecond paths/s'];

  @override
  void update(double dt) {
    _clock += dt;
    _pathsTime += dt;
    if (_pathsTime >= 1) {
      _pathsTime -= 1;
      _pathsPerSecond = _paths;
      _paths = 0;
    }
    // A key released after a knob took the focus is no longer held.
    final held = _heldKeys.length;
    _heldKeys.retainWhere(
      HardwareKeyboard.instance.physicalKeysPressed.contains,
    );
    if (_heldKeys.length != held) {
      _updateFire();
    }
    _fitView();
    // Before the world's components move, and before TubeComponent makes the
    // tube's paths for the view.
    _step(dt * world.timeScale);
    _aimCamera();
    tube.lane = _state == TubeState.play ? player.lane : null;
    // In a still world, where nothing updates, applies a change of the view,
    // such as a resize or a zoom.
    if (world.timeScale == 0 && view.version != _lastVersion) {
      _updateStillLines();
    }
    _lastVersion = view.version;
    super.update(dt);
    _roundText.text = 'ROUND $round';
    _livesText.text = 'LIVES $lives';
    _purgeText.text = 'PURGE ${purgeReady ? 'READY' : 'USED'}';
    _scoreText.text = 'SCORE $score';
  }

  /// Fits the tube's rim in 90% of the game's shorter side, with its lines'
  /// widths in device pixels, whatever the zoom.
  void _fitView() {
    if (size.x <= 0 || size.y <= 0) {
      return;
    }
    // The ratio the renderer uses: from the game's MediaQuery, which
    // Widgetbook's device frames set, read without depending on it.
    final ratio =
        buildContext
            ?.getInheritedWidgetOfExactType<MediaQuery>()
            ?.data
            .devicePixelRatio ??
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        1;
    view.fit(
      0.9 * math.min(size.x, size.y),
      1 / (ratio * camera.viewfinder.zoom),
    );
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
    _waitPointers.clear();
    _updateStars();
  }

  /// Shows the stars if they drift, on the zoom and the drop, and after a
  /// ship lost on the drop. Otherwise hides them, at once in a still world,
  /// where nothing fades.
  void _updateStars() {
    if (driftingStars ||
        _state == TubeState.zoom ||
        _state == TubeState.drop ||
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
          _waitForPlayer();
        }
      case TubeState.play:
        _pulseClock = (_pulseClock + dt * pace) % level.pulsePeriod;
        _spawn(dt);
        _collide();
        if (_state == TubeState.play && spawns.isEmpty && enemies.isEmpty) {
          for (final shot in [...enemyShots]) {
            discard(shot);
          }
          _setState(TubeState.drop);
        }
      case TubeState.drop:
        final progress = math.min(1.0, _stateTime / dropTime);
        player.depth = view.eyeShift = Tube.depth * progress * progress;
        _collide();
        if (_state == TubeState.drop && progress == 1) {
          _nextRound();
        }
      case TubeState.dying:
        if (_stateTime >= respawnTime) {
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
  /// end.
  void _addSpawn(EnemyKind kind, double at) {
    final spawn = SpawnDotComponent(kind, at: at);
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

  /// Whether [a] and [b], in the same lane, meet: within [hitWindow] in
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
  }

  /// Which way an enemy at the rim in [lane] goes toward the ship: 1 or -1,
  /// or 0 in the ship's lane.
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
    lives--;
    _explode(player, player.depth, color: TubeColors.ship);
    player.drawing.add(
      OpacityEffect.fadeOut(EffectController(duration: respawnTime * 2 / 3)),
    );
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

  /// Starts the next round, or the first, on the next level's tube.
  ///
  /// The round starts with its enemies at random round the far end, no
  /// spikes, the purge ready, and the ship on the tube's bottom lane. The tube
  /// zooms in through the stars, with the ship hidden until the zoom ends.
  void _nextRound() {
    round++;
    _level = levels[(firstLevel + round - 1) % levels.length];
    view.tube = _level.tube;
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
    player
      ..revive()
      ..startOn(view.tube)
      ..isVisible = false;
    view.eyeShift = -zoomDistance;
    _roundBanner.text = 'ROUND $round';
    camera.viewport.add(_roundBanner);
    _setState(TubeState.zoom);
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
    _lastTap = double.negativeInfinity;
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
  /// of 0, all lives, the first round, and the world at [speed].
  void _newGame() {
    for (final enemy in [...enemies]) {
      discard(enemy);
    }
    explosionGroup.removeAll(explosionGroup.children.toList());
    score = 0;
    lives = startLives;
    round = 0;
    gameOverText.removeFromParent();
    world.timeScale = _speed;
    _nextRound();
  }

  /// Starts firing, unless the game is waiting at READY or Game Over. Then
  /// the pointer only ends the wait when it goes up, as a tap: taps start
  /// drags too.
  @override
  void onDragStart(DragStartEvent event) {
    if (_isWaiting) {
      _waitPointers.add(event.pointerId);
    } else {
      _firePointers.add(event.pointerId);
      _updateFire();
    }
    _drags[event.pointerId] = (start: _clock, distance: 0);
    super.onDragStart(event);
  }

  /// Moves the ship a lane every [dragPerLane] logical pixels left or right,
  /// whatever the zoom.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    final delta = event.canvasDelta;
    if (canMove) {
      player.moveBy(delta.x / dragPerLane);
    }
    final drag = _drags[event.pointerId];
    if (drag != null) {
      _drags[event.pointerId] = (
        start: drag.start,
        distance: drag.distance + delta.length,
      );
    }
    super.onDragUpdate(event);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    _firePointers.remove(event.pointerId);
    _updateFire();
    final drag = _drags.remove(event.pointerId);
    if (_waitPointers.remove(event.pointerId)) {
      _endWait();
    } else if (drag != null &&
        _clock - drag.start <= tapTime &&
        drag.distance <= tapSlop) {
      _tap();
    }
    super.onDragEnd(event);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    _firePointers.remove(event.pointerId);
    _updateFire();
    _drags.remove(event.pointerId);
    _waitPointers.remove(event.pointerId);
    super.onDragCancel(event);
  }

  /// Ends a wait: starts a new game once it's over, or else the round.
  void _endWait() {
    if (_state == TubeState.over) {
      _newGame();
    } else {
      _beginPlay();
    }
  }

  /// Handles a tap: the second tap of a double tap purges.
  void _tap() {
    if (_clock - _lastTap <= doubleTapTime) {
      _lastTap = double.negativeInfinity;
      purge();
    } else {
      _lastTap = _clock;
    }
  }

  /// At READY, any key but a modifier starts the round. Otherwise, Enter
  /// purges, or starts a new game once it's over. The keys that move the ship
  /// or fire count as held while down, and the others are ignored.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.physicalKey;
    if (_state == TubeState.ready &&
        event is KeyDownEvent &&
        !_modifierKeys.contains(key)) {
      _beginPlay();
      return KeyEventResult.handled;
    }
    if (_purgeKeys.contains(key)) {
      if (event is KeyDownEvent) {
        if (_state == TubeState.over) {
          _newGame();
        } else {
          purge();
        }
      }
      return KeyEventResult.handled;
    }
    if (key != _fireKey &&
        !_leftKeys.contains(key) &&
        !_rightKeys.contains(key)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _heldKeys.add(key);
    } else if (event is KeyUpEvent) {
      _heldKeys.remove(key);
    }
    _updateFire();
    return KeyEventResult.handled;
  }

  /// Makes the ship fire while a drag is down or the fire key is held.
  void _updateFire() {
    if (_firePointers.isNotEmpty || _heldKeys.contains(_fireKey)) {
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
}) extends TubeShooterExample with HasRasterizer, ExampleRasterizer {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  PathComponent pathComponent(
    Path path,
    Paint paint, {
    Vector2? position,
    Anchor? anchor,
    double? maxSize,
    int? priority,
    RasterizerGlow? glow,
  }) => RasterizerPathComponent(
    path: path,
    paint: paint,
    position: position,
    anchor: anchor,
    maxSize: maxSize,
    priority: priority,
    glow: glow,
  );

  /// Also gives [drawing] the shapes' glow. If the Glow knob changed, this
  /// imports the shape again.
  @override
  void keepStroke(PathComponent drawing) {
    super.keepStroke(drawing);
    (drawing as RasterizerPathComponent).glow = _shapeGlow;
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeShooterExample({
  required super.status,
  super.random,
  super.firstLevel,
}) extends TubeShooterExample {
  @override
  String get rendererText => "Flame's PathComponent";

  /// None: Flame's PathComponents keep no numbers to show.
  @override
  Iterable<String> get rendererStats => const [];

  @override
  PathComponent pathComponent(
    Path path,
    Paint paint, {
    Vector2? position,
    Anchor? anchor,
    double? maxSize,
    int? priority,
    RasterizerGlow? glow,
  }) => PathComponent(
    path: path,
    paint: paint,
    position: position,
    anchor: anchor,
    priority: priority,
  );
}
