import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/particles.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/bottom_right_text.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/enemy_creator.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/game_over_text.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/star_background_creator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

/// Flame's Rogue Shooter, drawn with SVGs: see [description].
///
/// The world uses Rogue Shooter's coordinates, from the game's top left
/// corner. The camera looks at the middle of the play area, which is the
/// game's size. Subclasses pick what loads and draws the SVGs: see
/// [ExampleSvgs].
abstract class SvgShooterExample({required super.status, math.Random? random})
    extends ExampleGame
    with ExampleSvgs, HasCollisionDetection, DragCallbacks, KeyboardEvents {
  /// Creates the game for [renderer], with flame_svg's [cache] for Flame SVG.
  factory SvgShooterExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    SvgCache cache = defaultSvgCache,
    math.Random? random,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameSvgShooterExample(status: status, cache: cache, random: random)
      : RasterizerSvgShooterExample(
          status: status,
          renderer: renderer,
          random: random,
        );

  static const description = '''
    A vertical shooter drawn with SVGs. The player's spaceship is an SVG in
    colour, and the enemies and the missiles are wireframe SVGs.
    RasterizerSvgComponent draws them with the renderer that the Renderer knob
    picks; with Flame SVG, flame_svg's SvgComponent does.

    Move the spaceship by dragging anywhere, or with the arrow keys or WASD.
    Fire while dragging, or while holding the space bar. Once the game is over,
    tap to start a new one.

    Waves of enemies fall from the top: two kinds of spaceships, rockets and
    swinging robots, in random colours. Each enemy that hits the spaceship
    takes some of its health, which comes back after a while without a hit.
    The game is over when the health runs out.

    Hundreds of SVGs are on screen at once, each with an SvgHitbox in the shape
    of its paths. The stars are sprites, and the explosions are particles. The
    other knobs zoom the camera and change the game's speed; with Flame SVG,
    the cache knobs set flame_svg's cache. The health, the score and the number
    of components are at the bottom right. The bar under the game shows the
    renderer, the frame times and the renderer's own numbers.

    Based on Flame's Rogue Shooter example game.
  ''';

  final math.Random random = random ?? math.Random();

  /// The player's SVG.
  late final ExampleSvg playerSvg;

  /// The missiles' SVG, which all the missiles share.
  late final ExampleSvg missileSvg;

  /// The kinds of enemies. All the enemies of a kind share its SVG.
  late final List<EnemyKind> enemyKinds;

  /// Draws the particles of all the explosions.
  final explosionRenderer = CircleParticleRenderer(
    softness: 0.5,
    blendMode: BlendMode.plus,
  );

  /// The groups of stars, missiles, enemies and explosions, as in Rogue
  /// Shooter, but without its batching.
  final starGroup = Component(priority: -1);
  final missileGroup = Component();
  final enemyGroup = Component();
  final explosionGroup = Component();

  late final PlayerComponent player;
  final _enemyCreator = EnemyCreator();

  /// The image that every star draws, once loaded.
  Image? _starImage;

  final _healthText = BottomRightText(line: 2, text: 'Health: 100%');
  final _scoreText = BottomRightText(line: 1, text: 'Score: 0');
  final _componentCounter = BottomRightText(line: 0, text: 'Components: 0');
  final _gameOverText = GameOverText();

  int score = 0;

  /// Whether the player's health ran out. The game then stands still until a
  /// tap starts a new one.
  @visibleForTesting
  bool get isGameOver => _isGameOver;
  bool _isGameOver = false;

  /// The pointers that went down after the game was over. Each starts a new
  /// game as it goes up, like a tap. Pointers that went down before don't.
  final _newGamePointers = <int>{};

  /// The pointers that went down before the game was over, and drag. The
  /// player fires while any of them is down, or while [_fireKey] is held.
  final _firePointers = <int>{};

  /// The keys that move the player, each with its direction, and the key that
  /// fires: the arrows, WASD and the space bar. They're physical keys, so
  /// they stay in place whatever the keyboard's layout.
  static final _moveKeys = {
    PhysicalKeyboardKey.arrowLeft: Vector2(-1, 0),
    PhysicalKeyboardKey.arrowRight: Vector2(1, 0),
    PhysicalKeyboardKey.arrowUp: Vector2(0, -1),
    PhysicalKeyboardKey.arrowDown: Vector2(0, 1),
    PhysicalKeyboardKey.keyA: Vector2(-1, 0),
    PhysicalKeyboardKey.keyD: Vector2(1, 0),
    PhysicalKeyboardKey.keyW: Vector2(0, -1),
    PhysicalKeyboardKey.keyS: Vector2(0, 1),
  };
  static const _fireKey = PhysicalKeyboardKey.space;

  /// The keys above that are held, and went down while the game had the
  /// focus.
  final _heldKeys = <PhysicalKeyboardKey>{};

  /// Whether a key or a drag came before the player loaded. [_updateFire]
  /// applies it once the player has.
  bool _fireDeferred = false;

  /// The direction that the held keys move the player in: a unit vector, or
  /// zero.
  Vector2 get keyDirection {
    final direction = Vector2.zero();
    for (final key in _heldKeys) {
      direction.add(_moveKeys[key] ?? Vector2.zero());
    }
    direction.clampScalar(-1, 1);
    if (direction.length2 > 1) {
      direction.normalize();
    }
    return direction;
  }

  /// The Speed knob's value. It sets the world's time scale, except while the
  /// game is over and the world stands still.
  @override
  double get speed => _speed;
  double _speed = 1;

  @override
  set speed(double value) {
    _speed = value;
    if (!_isGameOver) {
      world.timeScale = value;
    }
  }

  @override
  Future<void> onLoad() async {
    playerSvg = await loadSvg('assets/svgs/spaceship_game.svg');
    missileSvg = await loadSvg('assets/svgs/wireframe/missile.svg');
    enemyKinds = [
      (
        svg: await loadSvg('assets/svgs/wireframe/spaceship.svg'),
        turned: true,
        swings: false,
      ),
      (
        svg: await loadSvg('assets/svgs/wireframe/spaceship_2.svg'),
        turned: true,
        swings: false,
      ),
      (
        svg: await loadSvg('assets/svgs/wireframe/rocket_ship.svg'),
        turned: true,
        swings: false,
      ),
      (
        svg: await loadSvg('assets/svgs/wireframe/robot.svg'),
        turned: false,
        swings: true,
      ),
    ];
    await explosionRenderer.onLoad();
    final starImage = await StarBackgroundCreator.starImage();
    // The game was removed while it loaded. Its SVGs are freed already, so
    // free the stars' image too.
    if (isRemoved) {
      starImage.dispose();
      return;
    }
    _starImage = starImage;
    world.addAll([starGroup, missileGroup, enemyGroup, explosionGroup]);
    world.add(player = PlayerComponent(playerSvg));
    // Like StoryGame's FPS text, these go in the viewport, so that they're
    // drawn above the world and not zoomed.
    camera.viewport.addAll([_healthText, _scoreText, _componentCounter]);
    world.addAll([_enemyCreator, StarBackgroundCreator(starImage)]);
    startStatus();
  }

  /// Frees the stars' image. Removing a game doesn't remove its components,
  /// so their own `onRemove` doesn't run.
  @override
  void onRemove() {
    super.onRemove();
    _starImage?.dispose();
  }

  @override
  void update(double dt) {
    super.update(dt);
    // The game gets no key up event for a key released after a knob took the
    // focus, so drop the keys that aren't pressed any more.
    final held = _heldKeys.length;
    _heldKeys.retainWhere(
      HardwareKeyboard.instance.physicalKeysPressed.contains,
    );
    if (_heldKeys.length != held || _fireDeferred) {
      _updateFire();
    }
    _healthText.text = 'Health: ${player.health}%';
    _scoreText.text = 'Score: $score';
    _componentCounter.text = 'Components: ${descendants().length}';
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    camera.viewfinder.position = size / 2;
  }

  /// Makes the player fire, or, once the game is over, starts a new game as
  /// the pointer goes up. A tap starts a drag too, so this handles taps.
  @override
  void onDragStart(DragStartEvent event) {
    if (_isGameOver) {
      _newGamePointers.add(event.pointerId);
    } else {
      _firePointers.add(event.pointerId);
      _updateFire();
    }
    super.onDragStart(event);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    _firePointers.remove(event.pointerId);
    _updateFire();
    if (_newGamePointers.remove(event.pointerId) && _isGameOver) {
      _newGame();
    }
    super.onDragEnd(event);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    _firePointers.remove(event.pointerId);
    _updateFire();
    _newGamePointers.remove(event.pointerId);
    super.onDragCancel(event);
  }

  /// Moves the player by the drag's distance in world units, so that it
  /// follows the finger at any zoom. A destroyed player doesn't move.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!player.isDestroyed) {
      player.position.addScaled(event.canvasDelta, 1 / camera.viewfinder.zoom);
    }
    super.onDragUpdate(event);
  }

  /// Tracks the keys that move the player or fire, and handles them, so that
  /// they don't also move the focus. It ignores other keys.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.physicalKey;
    if (key != _fireKey && !_moveKeys.containsKey(key)) {
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

  /// Makes the player fire while a pointer drags or the fire key is held.
  ///
  /// Until the game and the player load, [update] calls it again each frame,
  /// so that a key held from the start fires once they have.
  void _updateFire() {
    _fireDeferred = !isLoaded || !player.isLoaded;
    if (_fireDeferred) {
      return;
    }
    if (_firePointers.isNotEmpty || _heldKeys.contains(_fireKey)) {
      player.beginFire();
    } else {
      player.stopFire();
    }
  }

  void increaseScore() {
    score++;
  }

  /// Stops the world, whatever [speed] is, and the player's fire, and shows
  /// Game Over until a tap starts a new game.
  ///
  /// The player calls it once it has faded out.
  void gameOver() {
    if (_isGameOver) {
      return;
    }
    _isGameOver = true;
    world.timeScale = 0;
    player.stopFire();
    camera.viewport.add(_gameOverText);
  }

  /// Starts a new game.
  ///
  /// It removes all the missiles, enemies and explosions, adds a first wave
  /// of enemies, and resets the score and the player. The player fires at
  /// once if a drag or the fire key lasted through Game Over. The world runs
  /// at [speed] again.
  void _newGame() {
    for (final group in [missileGroup, enemyGroup, explosionGroup]) {
      group.removeAll(group.children.toList());
    }
    _enemyCreator.createFirstWave();
    score = 0;
    player.reset();
    _updateFire();
    _gameOverText.removeFromParent();
    _isGameOver = false;
    world.timeScale = _speed;
  }
}

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVGs, with the renderer that the Renderer knob picks.
class RasterizerSvgShooterExample({
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
}) extends SvgShooterExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with flame_svg: its `SvgComponent`s draw its SVGs as images,
/// cached as [cache] sets.
class FlameSvgShooterExample({
  required super.status,
  final SvgCache cache = defaultSvgCache,
  super.random,
}) extends SvgShooterExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;
}
