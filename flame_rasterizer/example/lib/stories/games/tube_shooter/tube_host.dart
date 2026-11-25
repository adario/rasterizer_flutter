import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/game_sounds.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_glow.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;

/// What Tube Shooter and Tube Runner share: the view of the tube, the score
/// and the lives, the texts at the bottom, READY and Game Over, the
/// player's keys, drags, taps and scrolls, the glow, the sounds, and the
/// components that draw shapes and quads.
///
/// Each frame, [update] fits the view, applies the game's rules with
/// [advance], updates the components, then calls [afterUpdate] and shows
/// the tube's name, the lives and the score. Subclasses say when the game
/// waits for the player, and what ends the wait: see [isWaiting].
abstract class TubeHost({
  required super.status,
  math.Random? random,
}) extends ExampleGame
    with
        DragCallbacks,
        ScrollCallbacks,
        KeyboardEvents,
        PathComponents<ExampleWorld> {
  /// The seconds from the ship's destruction to its return.
  static const respawnTime = 1.5;

  static const startLives = 3;

  /// The cap height, in logical pixels, of the texts at the bottom.
  static const hudCap = 12.0;

  /// The cap height, in logical pixels, of the texts at the middle, such as
  /// READY and Game Over.
  static const bannerCap = VectorTextComponent.maxCapHeight;

  /// How far a drag goes to move the ship one lane, in logical pixels.
  static const dragPerLane = 40.0;

  /// The longest a drag can last and still count as a tap, in seconds.
  static const tapTime = 0.25;

  /// The farthest a drag can move and still count as a tap, in logical
  /// pixels.
  static const tapSlop = 10.0;

  /// The most seconds between the two taps of a double tap.
  static const doubleTapTime = 0.35;

  /// The glow of the shapes' lines: 3 times as wide as the lines, and thinner
  /// with depth, as they are.
  static const lineGlow = RasterizerGlow.widths(3);

  /// The glow of the lines of the tube, its lane, the spikes and the bolts:
  /// twice as wide as the lines, and thinner with depth, as they are.
  static const tubeGlow = RasterizerGlow.widths(2);

  final math.Random random = random ?? math.Random();

  final view = TubeView();

  int score = 0;
  int lives = startLives;

  /// The tube's name, at the bottom left, above [roundText].
  final tubeText = VectorTextComponent(capHeight: hudCap, line: 1, left: true);

  /// The round, or the time, at the bottom left.
  final roundText = VectorTextComponent(capHeight: hudCap, line: 0, left: true);

  /// The lives left and the score, at the bottom right.
  final livesText = VectorTextComponent(capHeight: hudCap, line: 1);
  final scoreText = VectorTextComponent(capHeight: hudCap, line: 0);

  /// READY, in the camera's viewport while the game waits for the player.
  final readyText = VectorTextComponent(text: 'READY', capHeight: bannerCap);

  /// Game Over, in the camera's viewport once the game is over.
  final gameOverText = VectorTextComponent(
    text: 'GAME OVER',
    capHeight: bannerCap,
  );

  /// Whether the ship moves at the player's will.
  bool get canMove;

  /// Whether the game waits for the player, at READY or Game Over, so that
  /// a tap ends the wait, rather than firing.
  bool get isWaiting;

  /// Whether the game waits at READY, where any key but a modifier ends the
  /// wait.
  bool get isReady;

  /// Whether the game is over, where Enter ends the wait, and the world
  /// stands still, whatever [speed] is.
  bool get isOver;

  /// Ends a wait: starts a new game once it's over, or else plays.
  void endWait();

  /// Moves the ship [lanes] round the tube, which may be part of a lane.
  void moveShipBy(double lanes);

  /// Called when [isFiring] may have changed.
  void onFiringChanged() {}

  /// Called on a double tap, while the game doesn't wait.
  void onDoubleTap() {}

  /// Called on Enter, while the game isn't over.
  void onEnter() {}

  /// Applies the game's rules over [dt] seconds of the world's time, before
  /// the world's components update.
  void advance(double dt) {}

  /// Does what updates would do in a moving world, where they don't happen,
  /// for a change of the lines' glow.
  void updateStillLines() {}

  /// Called once the components updated, [dt] seconds after the last frame.
  void afterUpdate(double dt) {}

  /// The Speed knob's value. It sets the world's time scale, except while the
  /// game is over and the world stands still.
  @override
  double get speed => _speed;
  double _speed = 1;

  @override
  set speed(double value) {
    _speed = value;
    if (!isOver) {
      world.timeScale = value;
    }
  }

  /// How many paths the game made in the last second, as the status bar
  /// shows: see [countPath].
  int get pathsPerSecond => _pathsPerSecond;
  int _pathsPerSecond = 0;
  int _paths = 0;
  double _pathsTime = 0;

  /// Counts a path that the game made, for [pathsPerSecond].
  void countPath() => _paths++;

  @override
  Iterable<String> get exampleStats => ['$_pathsPerSecond paths/s'];

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

  /// The keys that move the ship, fire and end the game's waits, by their
  /// places on the keyboard, whatever its layout.
  static final _leftKeys = {
    PhysicalKeyboardKey.arrowLeft,
    PhysicalKeyboardKey.keyA,
  };
  static final _rightKeys = {
    PhysicalKeyboardKey.arrowRight,
    PhysicalKeyboardKey.keyD,
  };
  static const _fireKey = PhysicalKeyboardKey.space;
  static final _enterKeys = {
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

  /// Whether the player fires: while a drag is down, or the fire key is
  /// held.
  bool get isFiring => _firePointers.isNotEmpty || _heldKeys.contains(_fireKey);

  /// Forgets the pointers that went down while the game waited, as the game
  /// changes state: they don't end the next wait.
  void forgetWaitPointers() => _waitPointers.clear();

  /// Forgets the last tap, so that it doesn't count toward a double tap.
  void forgetTaps() => _lastTap = double.negativeInfinity;

  /// Whether the renderer draws the lines' glow with them, as the mesh
  /// renderer does. Otherwise, [TubeGlow] draws the Glow knob's.
  bool get rendererGlows => false;

  /// The Glow knob's value: whether the lines glow.
  ///
  /// If [rendererGlows], the lines glow with [lineGlow] and [tubeGlow], so a
  /// change imports them again: the tube's paths, as a change of the view
  /// does, and the shapes as they keep their stroke. In a still world, where
  /// nothing updates, this happens at once: see [updateStillLines].
  /// Otherwise, a [TubeGlow] is the camera's post process while it's on.
  bool get glow => _glow;
  bool _glow = false;

  set glow(bool value) {
    if (value != _glow) {
      _glow = value;
      if (rendererGlows) {
        view.invalidate();
        if (isLoaded && world.timeScale == 0) {
          updateStillLines();
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

  /// The shapes' glow, if the Glow knob is on and the renderer draws it.
  RasterizerGlow? get shapeGlow => _glow && rendererGlows ? lineGlow : null;

  /// The glow of the tube's lines, if the Glow knob is on and the renderer
  /// draws it.
  RasterizerGlow? get linesGlow => _glow && rendererGlows ? tubeGlow : null;

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
  void play(Sound sound) {
    if (_sound) {
      _sounds?.play(sound.path);
    }
  }

  /// How many times as long as the widest lane the shapes grow, at most, so
  /// that their imports are fine enough.
  double get shapeGrowth => 1;

  /// Creates a component that draws [shape], one of `Shapes`, stroked in
  /// [color] about its origin, [widths] times as wide as the view's shapes.
  ///
  /// All the components of a shape share one import of it, until the view
  /// changes.
  PathComponent shapeComponent(Path shape, Color color, {double widths = 1}) {
    final bounds = shape.getBounds();
    return pathComponent(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widths * view.shapeStroke
        ..color = color,
      anchor: Anchor(-bounds.left / bounds.width, -bounds.top / bounds.height),
      maxSize:
          shapeGrowth * Tubes.widestLane * view.rimScale / view.devicePixel,
      glow: shapeGlow,
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

  /// Gives [drawing], made by [shapeComponent], [glow], if the renderer
  /// draws glows. If the glow changed, this imports the shape again.
  void glowShape(PathComponent drawing, RasterizerGlow? glow) {}

  /// Gives [drawing], made by [shapeComponent], the view's stroke width,
  /// [widths] times as wide. If the width changed, this imports the shape
  /// again.
  void keepStroke(PathComponent drawing, {double widths = 1}) {
    final width = widths * view.shapeStroke;
    if (drawing.paint.strokeWidth != width) {
      drawing.paint.strokeWidth = width;
    }
  }

  /// Creates a component that fills [quads] in [color], where they are in
  /// the world, at [priority], with [glow] if [rendererGlows]: a path of
  /// them, by default.
  ///
  /// Its contours stay open, as the fill closes them anyway. Flame's
  /// `PathComponent` would walk each closed contour into a polygon, which the
  /// game doesn't use, as [RasterizerPolygons.path]'s are.
  PositionComponent quadsComponent(
    RasterizerPolygons quads,
    Color color, {
    int? priority,
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
      maxSize: maxSizeOf(quads),
      priority: priority,
      glow: glow,
    );
  }

  /// Returns the most device pixels that [quads]' longer side spans.
  double maxSizeOf(RasterizerPolygons quads) =>
      math.max(quads.bounds.width, quads.bounds.height) / view.devicePixel;

  @override
  Future<void> onLoad() async {
    // Before the components that size their imports for the view load.
    fitView();
    // In the camera's viewport, as StoryGame's FPS counter is: above the
    // world, and unzoomed.
    camera.viewport.addAll([tubeText, roundText, livesText, scoreText]);
    if (_glow && !rendererGlows) {
      _updateGlow();
    }
    // Before the game starts, so that its first sounds play.
    if (_sound) {
      await _loadSounds();
    }
  }

  @override
  void onRemove() {
    _sounds?.dispose();
    super.onRemove();
  }

  @override
  void update(double dt) {
    _sounds?.nextFrame();
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
      onFiringChanged();
    }
    fitView();
    advance(dt * world.timeScale);
    super.update(dt);
    afterUpdate(dt);
    tubeText.text = view.tube.name.toUpperCase();
    livesText.text = 'LIVES $lives';
    scoreText.text = 'SCORE $score';
  }

  /// Fits the ring at the ship in 90% of the game's shorter side, with its
  /// lines' widths in device pixels, whatever the zoom.
  void fitView() {
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

  /// Starts firing, unless the game waits at READY or Game Over. Then the
  /// pointer only ends the wait when it goes up, as a tap: taps start drags
  /// too.
  @override
  void onDragStart(DragStartEvent event) {
    if (isWaiting) {
      _waitPointers.add(event.pointerId);
    } else {
      _firePointers.add(event.pointerId);
      onFiringChanged();
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
      moveShipBy(delta.x / dragPerLane);
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
    onFiringChanged();
    final drag = _drags.remove(event.pointerId);
    if (_waitPointers.remove(event.pointerId)) {
      endWait();
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
    onFiringChanged();
    _drags.remove(event.pointerId);
    _waitPointers.remove(event.pointerId);
    super.onDragCancel(event);
  }

  /// Moves the ship a lane for each scroll, whatever its size: clockwise for
  /// a scroll down, and as a drag would for one sideways. Scrolling in circles
  /// on a Steam Deck trackpad set to Steam Input's Scroll Wheel mode turns it
  /// round the tube.
  @override
  void onScroll(ScrollEvent event) {
    final delta = event.raw.scrollDelta;
    if (canMove) {
      if (delta.dy != 0) {
        moveShipBy(-delta.dy.sign);
      } else if (delta.dx != 0) {
        moveShipBy(delta.dx.sign);
      }
    }
    super.onScroll(event);
  }

  /// Handles a tap: the second tap of a double tap calls [onDoubleTap].
  void _tap() {
    if (_clock - _lastTap <= doubleTapTime) {
      _lastTap = double.negativeInfinity;
      onDoubleTap();
    } else {
      _lastTap = _clock;
    }
  }

  /// Handles a key: at READY, any key but a modifier ends the wait. Enter
  /// ends it once the game is over, and otherwise calls [onEnter]. The keys
  /// that move the ship or fire count as held while down, and it ignores the
  /// others.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.physicalKey;
    if (isReady && event is KeyDownEvent && !_modifierKeys.contains(key)) {
      endWait();
      return KeyEventResult.handled;
    }
    if (_enterKeys.contains(key)) {
      if (event is KeyDownEvent) {
        if (isOver) {
          endWait();
        } else {
          onEnter();
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
    onFiringChanged();
    return KeyEventResult.handled;
  }
}

/// A [TubeHost] whose paths and quads flame_rasterizer draws, with the
/// renderer that the Renderer knob picks.
mixin RasterizerTubeHost on TubeHost, ExampleRasterizer<ExampleWorld> {
  /// Whether the Renderer knob picked the mesh renderer, which draws the
  /// lines' glow with them.
  @override
  bool get rendererGlows => renderer == SvgRenderer.rasterizer;

  @override
  void glowShape(PathComponent drawing, RasterizerGlow? glow) {
    (drawing as RasterizerPathComponent).glow = glow;
  }

  /// Fills the quads separate, which the mesh renderer imports much faster
  /// than their union. Where glows overlap, they add up.
  @override
  PositionComponent quadsComponent(
    RasterizerPolygons quads,
    Color color, {
    int? priority,
    RasterizerGlow? glow,
  }) => RasterizerPolygonsComponent(
    polygons: quads,
    paint: Paint()..color = color,
    position: Vector2(quads.bounds.left, quads.bounds.top),
    maxSize: maxSizeOf(quads),
    priority: priority,
    glow: glow,
    separate: true,
  );
}

/// A [TubeHost] whose paths Flame's `PathComponent`s draw, with no glow.
mixin FlameTubeHost on TubeHost {
  @override
  String get rendererText => "Flame's PathComponent";

  /// None: Flame's PathComponents keep no numbers to show.
  @override
  Iterable<String> get rendererStats => const [];
}
