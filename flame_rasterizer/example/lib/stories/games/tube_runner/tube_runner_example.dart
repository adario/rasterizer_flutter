import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/flight_stars_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_shot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/ship_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;

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

/// A prototype of an endless runner, where running is flying: see
/// [description].
///
/// It borrows Tube Shooter's tube, ship, stars and view. In the world, the
/// ring at the ship is centred on the origin, where the camera looks.
/// Subclasses pick the component that draws a path: see [pathComponent].
abstract class TubeRunnerExample({
  required super.status,
  math.Random? random,
  Tube? tube,
}) extends ExampleGame
    with
        DragCallbacks,
        ScrollCallbacks,
        KeyboardEvents,
        PathComponents<ExampleWorld> {
  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG, down [tube], one of [tubes], or the hexagon.
  factory TubeRunnerExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    Tube? tube,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeRunnerExample(status: status, random: random, tube: tube)
      : RasterizerTubeRunnerExample(
          status: status,
          renderer: renderer,
          random: random,
          tube: tube,
        );

  /// The tubes it can fly down: Tube Shooter's closed ones, as the ship
  /// goes round and round, in the order of its levels.
  static final tubes = [
    for (final level in levels)
      if (!level.tube.isOpen) level.tube,
  ];

  static const description = '''
    A prototype of an endless runner in vector lines, where running is flying.
    The ship flies down an endless tube that bends as it goes, and that the
    game makes as the ship gets there. RasterizerPolygonsComponent draws the
    tube's quads, and RasterizerPathComponent the other paths, with the
    renderer that the Renderer knob picks; with Flame SVG, Flame's
    PathComponent draws them all.

    Move the ship round the tube with the arrow keys, A and D, by dragging
    left and right, or a lane per scroll of the mouse wheel. Fire down its
    lane with the space bar, or while dragging, as in Tube Shooter. The Tube
    knob picks one of Tube Shooter's closed tubes, which the ship goes on
    down without a stop. The ship's lane shows in the ship's colour, as in
    Tube Shooter.

    READY shows until a tap or a key starts the game. After 4 seconds, and
    every 4 seconds from then on, an enemy comes at the farthest ring across
    the tube, on a lane picked at random: a seeder at first, and after 30
    seconds in the tube, a seeder or a climber. For a second and a half, its
    lane flashes in the enemy's colour, added to the ship's in the ship's
    lane, and glows with the enemy and a seeder's spike, fading out: the mesh
    renderer draws the glow with RasterizerGlow, only on them, and with the
    other renderers, wider, see-through copies of them stand for it. Enemies
    climb their lanes toward the ship, and go once they pass it. A seeder lays
    a spike behind it, which goes once all of it passes the ship. A climber
    flips onto a neighbouring lane every 2 to 4 seconds, and fires down its
    lane every 3 to 5 seconds, with at most 2 of its kind's shots in the tube,
    as on Tube Shooter's first level; its shots climb half as fast again as
    it does.

    The ship's shots fly as fast as Tube Shooter's ahead of it, and go 8
    units down the tube. As in Tube Shooter, a shot destroys a seeder for 50
    points, and leaves its spike, cuts a spike back from its near end for 2
    points, destroys a climber for 100, and destroys a climber's shot. An
    enemy, a spike or a climber's shot that touches the ship, in its lane at
    the ship's ring, destroys it, and takes a life, as in Tube Shooter: the
    enemies, spikes and shots go, and READY shows again. Once the lives are
    gone, Game Over stops the game until a tap, or Enter, starts a new one.
    The bottom left shows the tube's name and how long the game has gone on
    in it, and the bottom right the lives left and the score.

    The game makes the tube's quads again every frame. The mesh renderer fills
    each quad on its own, as a fan of triangles, rather than their union. The
    bar under the game shows the renderer, the frame times, the renderer's own
    numbers, the tube's quads and the paths made each second.
  ''';

  /// How fast the ship flies, in tube units a second.
  static const flightSpeed = 2.0;

  /// When the first enemy comes, and how often the others do, in seconds of
  /// the game.
  static const firstEnemy = 4.0;
  static const enemyPeriod = 4.0;

  /// The kinds of enemy that come, in the order they join: the first from
  /// the start, and one more after every [unlockTime] seconds in the tube.
  static const enemyKinds = [EnemyKind.seeder, EnemyKind.climber];
  static const unlockTime = 30.0;

  /// How far the glow of an enemy's lane and a seeder's spike, and of the
  /// enemy, reach as it comes, in line widths, as Tube Shooter's `tubeGlow`
  /// and `lineGlow` do.
  static const laneGlowWidths = 2.0;
  static const shapeGlowWidths = 3.0;

  /// The alpha of the wider copies that stand for the glow with the renderers
  /// that don't draw it, as an enemy comes.
  static const haloAlpha = 0.3;

  /// The seconds from the ship's destruction to its return, as in Tube
  /// Shooter.
  static const respawnTime = 1.5;

  static const startLives = 3;

  /// The cap heights, in logical pixels, of the texts at the bottom, and of
  /// READY and Game Over, at the middle, as in Tube Shooter.
  static const hudCap = 12.0;
  static const bannerCap = VectorTextComponent.maxCapHeight;

  /// How far a drag goes to move the ship one lane, in logical pixels.
  static const dragPerLane = 40.0;

  final math.Random random = random ?? math.Random();

  final view = TubeView()..tube = tube ?? Tubes.hexagon;

  final endlessTube = EndlessTube();

  /// The tube it flies down, one of [tubes].
  Tube get tube => view.tube;

  /// Changes the tube where the ship is, without a stop: the ship goes on at
  /// the same angle round the axis, in the new tube's nearest step. The
  /// enemies, spikes, shots and explosions go, and the time in the tube
  /// starts again.
  set tube(Tube value) {
    final from = view.tube;
    if (value == from) {
      return;
    }
    view.tube = value;
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

  int get lives => _lives;
  int _lives = startLives;

  /// How long the game has been on in the tube, in seconds of the game: since
  /// the last change of tube, or the last new game.
  double get tubeTime => _tubeTime;
  double _tubeTime = 0;

  /// The game's score, from the shots' hits, as in Tube Shooter.
  int get score => _score;
  int _score = 0;

  final _tubeText = VectorTextComponent(capHeight: hudCap, line: 1, left: true);
  final _timeText = VectorTextComponent(capHeight: hudCap, line: 0, left: true);
  final _livesText = VectorTextComponent(capHeight: hudCap, line: 1);
  final _scoreText = VectorTextComponent(capHeight: hudCap, line: 0);

  /// READY, in the camera's viewport while the game waits for the player.
  final readyText = VectorTextComponent(text: 'READY', capHeight: bannerCap);

  /// Game Over, in the camera's viewport once the game is over.
  final gameOverText = VectorTextComponent(
    text: 'GAME OVER',
    capHeight: bannerCap,
  );

  /// The Speed knob's value. It sets the world's time scale, except while the
  /// game is over and the world stands still.
  @override
  double get speed => _speed;
  double _speed = 1;

  @override
  set speed(double value) {
    _speed = value;
    if (_state != RunnerState.over) {
      world.timeScale = value;
    }
  }

  /// Whether the ship moves at the player's will.
  bool get canMove => _state == RunnerState.play;

  /// Whether a tap ends a wait.
  bool get _isWaiting =>
      _state == RunnerState.ready || _state == RunnerState.over;

  /// The pointers that went down while the game waits, at READY or Game
  /// Over. Each ends the wait when it goes up, as a tap; pointers that were
  /// already down don't.
  final _waitPointers = <int>{};

  /// The pointers that went down while the game didn't wait. The ship fires
  /// while any of them is down, or while [_fireKey] is held, as in Tube
  /// Shooter.
  final _firePointers = <int>{};

  /// How long since the ship last fired, in seconds of the game.
  double _sinceShot = PlayerComponent.firePeriod;

  final stars = FlightStarsComponent();

  /// How far the ship has flown along the tube's axis, in tube units.
  double get flown => _flown;
  double _flown = 0;

  /// The components that draw the tube, and the ship's lane over it in the
  /// ship's colour, as Tube Shooter does.
  PositionComponent? _tube;
  PositionComponent? _lane;
  PositionComponent? _spikesDrawing;

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

  /// How long the game has run since the last enemy came, or since
  /// [enemyPeriod] before [firstEnemy].
  double _enemyTime = enemyPeriod - firstEnemy;

  /// How far the ship had flown, the view's version, the ship's lane, and
  /// the flashing enemy and its flash, as the tube's paths were made last.
  double _tubeFlown = double.nan;
  int _tubeVersion = -1;
  int? _tubeLane;
  RunnerEnemyComponent? _tubeFlasher;
  double _tubeFlash = 0;

  /// How many quads the tube's paths have.
  int _quads = 0;

  /// How many paths the game made in the last second, as the status bar
  /// shows.
  int _pathsPerSecond = 0;
  int _paths = 0;
  double _pathsTime = 0;

  /// The keys that move the ship, by their places on the keyboard, whatever
  /// its layout.
  static final _leftKeys = {
    PhysicalKeyboardKey.arrowLeft,
    PhysicalKeyboardKey.keyA,
  };
  static final _rightKeys = {
    PhysicalKeyboardKey.arrowRight,
    PhysicalKeyboardKey.keyD,
  };
  static const _fireKey = PhysicalKeyboardKey.space;

  static final _newGameKeys = {
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

  /// Creates a component that draws [shape], one of `Shapes`, stroked in
  /// [color] about its origin, as Tube Shooter does, [widths] times as wide.
  PathComponent shapeComponent(Path shape, Color color, {double widths = 1}) {
    final bounds = shape.getBounds();
    return pathComponent(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widths * view.shapeStroke
        ..color = color,
      anchor: Anchor(-bounds.left / bounds.width, -bounds.top / bounds.height),
      maxSize: Tubes.widestLane * view.rimScale / view.devicePixel,
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

  /// Gives [drawing], made by [shapeComponent], the view's stroke width,
  /// [widths] times as wide. If the width changed, this imports the shape
  /// again.
  void keepStroke(PathComponent drawing, {double widths = 1}) {
    final width = widths * view.shapeStroke;
    if (drawing.paint.strokeWidth != width) {
      drawing.paint.strokeWidth = width;
    }
  }

  /// Whether the renderer draws glows, as the mesh renderer does. Otherwise,
  /// wider, see-through copies stand for them.
  bool get rendererGlows => false;

  /// Returns the glow of an enemy that comes, reaching [widths] line widths
  /// with [strength], in its [color], or none for no [strength].
  static RasterizerGlow? flashGlow(
    double widths,
    double strength,
    Color color,
  ) => strength > 0
      ? RasterizerGlow.widths(widths, strength: strength, color: color)
      : null;

  /// Gives [drawing], made by [shapeComponent], the glow of an enemy that
  /// comes, with [strength], in its [color], if [rendererGlows]. If the glow
  /// changed, this imports the shape again.
  void glowShape(PathComponent drawing, double strength, Color color) {}

  @override
  Future<void> onLoad() async {
    // Before the ship loads: it sizes its import for the view.
    _fitView();
    endlessTube.advanceTo(_flown);
    world.addAll([tubeGroup, ship, explosionGroup]);
    // Under the world, as Tube Shooter's stars are.
    camera.backdrop.add(stars);
    // In the camera's viewport, as StoryGame's FPS counter is: above the
    // world, and unzoomed.
    camera.viewport.addAll([_tubeText, _timeText, _livesText, _scoreText]);
    _waitForPlayer();
    _updateTube();
    startStatus();
  }

  @override
  Iterable<String> get exampleStats => [
    '$_quads quads',
    '$_pathsPerSecond paths/s',
  ];

  @override
  void update(double dt) {
    _pathsTime += dt;
    if (_pathsTime >= 1) {
      _pathsTime -= 1;
      _pathsPerSecond = _paths;
      _paths = 0;
    }
    // A key released after a knob took the focus is no longer held.
    _heldKeys.retainWhere(
      HardwareKeyboard.instance.physicalKeysPressed.contains,
    );
    _fitView();
    final worldDt = dt * world.timeScale;
    _flown += flightSpeed * worldDt;
    _step(worldDt);
    endlessTube.advanceTo(_flown);
    _updateTube();
    super.update(dt);
    _tubeText.text = tube.name.toUpperCase();
    final seconds = _tubeTime.floor();
    _timeText.text =
        'TIME ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    _livesText.text = 'LIVES $_lives';
    _scoreText.text = 'SCORE $_score';
  }

  void _setState(RunnerState state) {
    _state = state;
    _stateTime = 0;
    _waitPointers.clear();
  }

  /// Applies the game's rules over [dt] seconds of the world's time, after
  /// the ship flew.
  void _step(double dt) {
    _stateTime += dt;
    switch (_state) {
      case RunnerState.play:
        _tubeTime += dt;
        _updateEnemies(dt);
        _updateShots(dt);
        _hit();
        _collide();
        _dropPassed();
      case RunnerState.dying:
        if (_stateTime >= respawnTime) {
          if (_lives == 0) {
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
  /// the lane. Those that passed the ring before went with [_dropPassed].
  void _collide() {
    final lane = ship.lane;
    if (_spikes.any(
          (spike) =>
              spike.lane == lane && spike.near <= _flown && _flown <= spike.far,
        ) ||
        _enemies.any(
          (enemy) => enemy.currentLane == lane && enemy.at <= _flown,
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
    world.add(shot);
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
    if ((_firePointers.isNotEmpty || _heldKeys.contains(_fireKey)) &&
        _sinceShot >= PlayerComponent.firePeriod &&
        _shots.length < PlayerComponent.maxShots) {
      _sinceShot = 0;
      final shot = RunnerShotComponent(ship.lane, _flown);
      _shots.add(shot);
      world.add(shot);
      // Places it now, even if nothing else moved.
      _tubeFlown = double.nan;
    }
  }

  /// Resolves the shots' hits, as in Tube Shooter: each shot hits the
  /// nearest spike, enemy or climber's shot in its lane that it reached or
  /// passed since it last flew. A seeder is at its spike's near end, so the
  /// spike stands for it. The shot destroys an enemy, and scores, a seeder
  /// leaving its spike, cuts a spike back by `TubeShooterExample.spikeHit`
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
    spike.near = math.min(spike.near + TubeShooterExample.spikeHit, spike.far);
    _score += TubeShooterExample.spikeScore;
    if (spike.near >= spike.far) {
      _spikes.remove(spike);
    }
  }

  /// Blows [enemy] up where it is along the tube, and adds its score. A
  /// seeder's spike stays.
  void _destroyEnemy(RunnerEnemyComponent enemy) {
    _enemies.remove(enemy);
    enemy.removeFromParent();
    _score += enemy.kind.score;
    final blast = PlacedExplosionComponent(
      enemy.mark,
      rayColor: enemy.kind.color,
    );
    _blasts.add(blast);
    explosionGroup.add(blast);
    _tubeFlown = double.nan;
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
    _lives--;
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
    camera.viewport.add(readyText);
    _setState(RunnerState.ready);
  }

  /// Starts the game, or resumes it after a lost ship, with the first enemy
  /// [firstEnemy] away.
  void _beginPlay() {
    readyText.removeFromParent();
    _enemyTime = enemyPeriod - firstEnemy;
    _setState(RunnerState.play);
  }

  /// Stops the world, whatever [speed] is, and shows Game Over until a tap or
  /// Enter.
  void _gameOver() {
    world.timeScale = 0;
    _setState(RunnerState.over);
    ship.isVisible = false;
    camera.viewport.add(gameOverText);
  }

  /// Starts a new game in this one: no explosions, all lives, the time in the
  /// tube and the score from 0, and the world at [speed], waiting at READY.
  void _newGame() {
    explosionGroup.removeAll(explosionGroup.children.toList());
    _blasts.clear();
    _lives = startLives;
    _tubeTime = 0;
    _score = 0;
    gameOverText.removeFromParent();
    world.timeScale = _speed;
    ship.revive();
    _waitForPlayer();
  }

  /// Ends a wait: starts a new game once it's over, or else plays.
  void _endWait() {
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
  void _updateTube() {
    // The ship knows its lane once loaded. Its lane shows while it's in play,
    // as in Tube Shooter.
    final lane = ship.isLoaded && canMove ? ship.lane : null;
    var flasher = _enemies.lastOrNull;
    final flash = flasher?.flash ?? 0;
    if (flash == 0) {
      flasher = null;
    }
    if (_flown == _tubeFlown &&
        view.version == _tubeVersion &&
        lane == _tubeLane &&
        flasher == _tubeFlasher &&
        flash == _tubeFlash) {
      return;
    }
    _tubeFlown = _flown;
    _tubeVersion = view.version;
    _tubeLane = lane;
    _tubeFlasher = flasher;
    _tubeFlash = flash;
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
      halo: rendererGlows ? null : 2 * laneGlowWidths,
    );
    _quads =
        quads.tube.vertexCounts.length +
        quads.lane.vertexCounts.length +
        quads.spikes.vertexCounts.length +
        quads.flashLane.vertexCounts.length +
        quads.flashSpike.vertexCounts.length +
        quads.halo.vertexCounts.length;
    // Under the lines it stands for the glow of, over the others, as a glow
    // is.
    _tube = _replaceQuads(_tube, quads.tube, TubeColors.tube);
    _lane = _replaceQuads(_lane, quads.lane, TubeColors.ship);
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
    final glow = rendererGlows ? flashGlow(laneGlowWidths, flash, color) : null;
    _flashLane = _replaceQuads(
      _flashLane,
      quads.flashLane,
      flasher?.spawnLane == lane
          ? _addLight(TubeColors.ship, color, flash)
          : Color.lerp(color, TubeColors.tube, 1 - flash)!,
      glow: glow,
    );
    _flashSpike = _replaceQuads(
      _flashSpike,
      quads.flashSpike,
      TubeColors.spikes,
      glow: glow,
    );
    for (var i = 0; i < placed.length; i++) {
      placed[i].placeAt(quads.places[i]);
    }
  }

  /// Over [dt] seconds of the game: brings an enemy at [firstEnemy], then
  /// every [enemyPeriod], of a kind picked at random among the [enemyKinds]
  /// that joined, on a lane picked at random, and climbs the enemies and the
  /// climbers' shots.
  void _updateEnemies(double dt) {
    _enemyTime += dt;
    if (_enemyTime >= enemyPeriod) {
      _enemyTime -= enemyPeriod;
      final kinds = math.min(enemyKinds.length, 1 + _tubeTime ~/ unlockTime);
      // Picking among one kind would take a number from [random], and change
      // what comes until the second kind joins.
      final kind = enemyKinds[kinds == 1 ? 0 : random.nextInt(kinds)];
      addEnemy(kind, random.nextInt(tube.laneCount));
    }
    for (final enemy in _enemies) {
      enemy.climb(dt);
    }
    for (final shot in _enemyShots) {
      shot.climb(dt);
    }
  }

  /// Brings an enemy of [kind], one of [enemyKinds], at the farthest ring
  /// across the tube, in [lane].
  @visibleForTesting
  void addEnemy(EnemyKind kind, int lane) {
    const spacing = EndlessTube.ringSpacing;
    final far = ((_flown + EndlessTube.ahead) / spacing).floor() * spacing;
    final RunnerEnemyComponent enemy;
    switch (kind) {
      case EnemyKind.seeder:
        final spike = Spike(lane, far);
        _spikes.add(spike);
        enemy = RunnerSeederComponent(spike);
      case EnemyKind.climber:
        enemy = RunnerClimberComponent(lane, far);
      case EnemyKind.splitter || EnemyKind.zapper || EnemyKind.edgeWalker:
        throw ArgumentError.value(kind, 'kind', "doesn't come here yet");
    }
    _enemies.add(enemy);
    world.add(enemy);
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
    _paths++;
    final component = quadsComponent(quads, color, glow: glow);
    tubeGroup.add(component);
    return component;
  }

  /// Creates a component that fills [quads] in [color], where they are in
  /// the world, with [glow] if [rendererGlows].
  PositionComponent quadsComponent(
    RasterizerPolygons quads,
    Color color, {
    RasterizerGlow? glow,
  });

  /// Returns the most device pixels that [quads]' longer side spans.
  double maxSizeOf(RasterizerPolygons quads) =>
      math.max(quads.bounds.width, quads.bounds.height) / view.devicePixel;

  /// Fits the ring at the ship in 90% of the game's shorter side, as Tube
  /// Shooter fits its rim, with its lines' widths in device pixels, whatever
  /// the zoom.
  void _fitView() {
    if (size.x <= 0 || size.y <= 0) {
      return;
    }
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

  /// Takes note of a pointer that goes down while the game waits, at READY
  /// or Game Over: it ends the wait when it goes up, as a tap. Otherwise,
  /// the ship fires while it's down, as in Tube Shooter.
  @override
  void onDragStart(DragStartEvent event) {
    if (_isWaiting) {
      _waitPointers.add(event.pointerId);
    } else {
      _firePointers.add(event.pointerId);
    }
    super.onDragStart(event);
  }

  /// Moves the ship a lane every [dragPerLane] logical pixels left or right,
  /// whatever the zoom.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (canMove) {
      ship.moveBy(event.canvasDelta.x / dragPerLane);
    }
    super.onDragUpdate(event);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    _firePointers.remove(event.pointerId);
    if (_waitPointers.remove(event.pointerId)) {
      _endWait();
    }
    super.onDragEnd(event);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    _firePointers.remove(event.pointerId);
    _waitPointers.remove(event.pointerId);
    super.onDragCancel(event);
  }

  /// Moves the ship a lane for each scroll, whatever its size: clockwise for
  /// a scroll down, and as a drag would for one sideways.
  @override
  void onScroll(ScrollEvent event) {
    final delta = event.raw.scrollDelta;
    if (canMove) {
      if (delta.dy != 0) {
        ship.moveBy(-delta.dy.sign);
      } else if (delta.dx != 0) {
        ship.moveBy(delta.dx.sign);
      }
    }
    super.onScroll(event);
  }

  /// Handles a key: at READY, any key but a modifier starts the game, and
  /// once it's over, Enter starts a new one. The keys that move the ship or
  /// fire count as held while down, and it ignores the others.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.physicalKey;
    if (_state == RunnerState.ready &&
        event is KeyDownEvent &&
        !_modifierKeys.contains(key)) {
      _beginPlay();
      return KeyEventResult.handled;
    }
    if (_newGameKeys.contains(key)) {
      if (event is KeyDownEvent && _state == RunnerState.over) {
        _newGame();
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
    return KeyEventResult.handled;
  }
}

/// The example with flame_rasterizer: [RasterizerPathComponent]s draw its
/// paths, with the renderer that the Renderer knob picks.
class RasterizerTubeRunnerExample({
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.tube,
}) extends TubeRunnerExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerPathComponents<ExampleWorld> {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  /// Fills the quads separate, which the mesh renderer imports much faster
  /// than their union. The tube is opaque, so their overlaps don't show,
  /// but where glows overlap, they add up, as in Tube Shooter.
  @override
  PositionComponent quadsComponent(
    RasterizerPolygons quads,
    Color color, {
    RasterizerGlow? glow,
  }) => RasterizerPolygonsComponent(
    polygons: quads,
    paint: Paint()..color = color,
    position: Vector2(quads.bounds.left, quads.bounds.top),
    maxSize: maxSizeOf(quads),
    glow: glow,
    separate: true,
  );

  /// Whether the Renderer knob picked the mesh renderer, which draws glows.
  @override
  bool get rendererGlows => renderer == SvgRenderer.rasterizer;

  @override
  void glowShape(PathComponent drawing, double strength, Color color) {
    (drawing as RasterizerPathComponent).glow = TubeRunnerExample.flashGlow(
      TubeRunnerExample.shapeGlowWidths,
      strength,
      color,
    );
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeRunnerExample({
  required super.status,
  super.random,
  super.tube,
}) extends TubeRunnerExample with FlamePathComponents<ExampleWorld> {
  @override
  String get rendererText => "Flame's PathComponent";

  /// None: Flame's PathComponents keep no numbers to show.
  @override
  Iterable<String> get rendererStats => const [];

  /// Fills a path of the quads, without [glow], which Flame doesn't draw.
  ///
  /// Its contours stay open, as the fill closes them anyway. Flame's
  /// `PathComponent` would walk each closed contour into a polygon, which the
  /// game doesn't use, as [RasterizerPolygons.path]'s are.
  @override
  PositionComponent quadsComponent(
    RasterizerPolygons quads,
    Color color, {
    RasterizerGlow? glow,
  }) {
    final path = Path();
    final points = quads.vertices;
    for (var i = 0; i < points.length; i += 8) {
      path.addPolygon([
        for (var k = i; k < i + 8; k += 2) Offset(points[k], points[k + 1]),
      ], false);
    }
    return pathComponent(
      path,
      Paint()..color = color,
      position: Vector2(quads.bounds.left, quads.bounds.top),
    );
  }
}
