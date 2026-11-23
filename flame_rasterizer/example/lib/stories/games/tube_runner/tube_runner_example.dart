import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/flight_stars_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/ship_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult, MediaQuery;

/// A prototype of an endless runner, where running is flying: see
/// [description].
///
/// It borrows Tube Shooter's tube, ship, stars and view. In the world, the
/// ring at the ship is centred on the origin, where the camera looks.
/// Subclasses pick the component that draws a path: see [pathComponent].
abstract class TubeRunnerExample({
  required super.status,
  math.Random? random,
}) extends ExampleGame
    with
        DragCallbacks,
        ScrollCallbacks,
        KeyboardEvents,
        PathComponents<ExampleWorld> {
  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG.
  factory TubeRunnerExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeRunnerExample(status: status, random: random)
      : RasterizerTubeRunnerExample(
          status: status,
          renderer: renderer,
          random: random,
        );

  static const description = '''
    A prototype of an endless runner in vector lines, where running is flying.
    The ship flies down an endless tube that bends as it goes, and that the
    game makes as the ship gets there. Everything in the game is a Flutter
    Path. RasterizerPathComponent draws them with the renderer that the
    Renderer knob picks; with Flame SVG, Flame's PathComponent does.

    Move the ship round the tube with the arrow keys, A and D, by dragging
    left and right, or a lane per scroll of the mouse wheel.

    The game makes the tube's path again every frame. The bar under the game
    shows the renderer, the frame times, the renderer's own numbers, the
    quads in the tube's path and the paths made each second.
  ''';

  /// How fast the ship flies, in tube units a second.
  static const flightSpeed = 2.0;

  /// How far a drag goes to move the ship one lane, in logical pixels.
  static const dragPerLane = 40.0;

  final math.Random random = random ?? math.Random();

  final view = TubeView()..tube = Tubes.hexagon;

  late final endlessTube = EndlessTube(view.tube);

  final tubeGroup = Component();
  final ship = ShipComponent();
  final stars = FlightStarsComponent();

  /// How far the ship has flown along the tube's axis, in tube units.
  double get flown => _flown;
  double _flown = 0;

  /// The component that draws the tube.
  PathComponent? _tube;

  /// How far the ship had flown, and the view's version, as the tube's path
  /// was made last.
  double _tubeFlown = double.nan;
  int _tubeVersion = -1;

  /// How many quads the tube's path has.
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

  /// The keys held that went down while the game had the focus.
  final _heldKeys = <PhysicalKeyboardKey>{};

  /// Where the keys held move the ship: 1 to the right along the bottom, -1
  /// to the left, or 0.
  int get keyDirection =>
      (_heldKeys.any(_rightKeys.contains) ? 1 : 0) -
      (_heldKeys.any(_leftKeys.contains) ? 1 : 0);

  /// Creates a component that draws [shape], one of `Shapes`, stroked in
  /// [color] about its origin, as Tube Shooter does.
  PathComponent shapeComponent(Path shape, Color color) {
    final bounds = shape.getBounds();
    return pathComponent(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = view.shapeStroke
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

  /// Gives [drawing], made by [shapeComponent], the view's stroke width. If
  /// the width changed, this imports the shape again.
  void keepStroke(PathComponent drawing) {
    final width = view.shapeStroke;
    if (drawing.paint.strokeWidth != width) {
      drawing.paint.strokeWidth = width;
    }
  }

  @override
  Future<void> onLoad() async {
    // Before the ship loads: it sizes its import for the view.
    _fitView();
    endlessTube.advanceTo(_flown);
    world.addAll([tubeGroup, ship]);
    // Under the world, as Tube Shooter's stars are.
    camera.backdrop.add(stars);
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
    _flown += flightSpeed * dt * world.timeScale;
    endlessTube.advanceTo(_flown);
    _updateTube();
    super.update(dt);
  }

  /// Makes the tube's path again if the ship flew or the view changed.
  void _updateTube() {
    if (_flown == _tubeFlown && view.version == _tubeVersion) {
      return;
    }
    _tubeFlown = _flown;
    _tubeVersion = view.version;
    final (:path, :quads) = endlessTube.pathAt(_flown, view);
    _quads = quads;
    _tube?.removeFromParent();
    _tube = null;
    final bounds = path.getBounds();
    if (bounds.isEmpty) {
      return;
    }
    _paths++;
    tubeGroup.add(
      _tube = pathComponent(
        path,
        Paint()..color = TubeColors.tube,
        position: Vector2(bounds.left, bounds.top),
        maxSize: math.max(bounds.width, bounds.height) / view.devicePixel,
      ),
    );
  }

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

  /// Moves the ship a lane every [dragPerLane] logical pixels left or right,
  /// whatever the zoom.
  @override
  void onDragUpdate(DragUpdateEvent event) {
    ship.moveBy(event.canvasDelta.x / dragPerLane);
    super.onDragUpdate(event);
  }

  /// Moves the ship a lane for each scroll, whatever its size: clockwise for
  /// a scroll down, and as a drag would for one sideways.
  @override
  void onScroll(ScrollEvent event) {
    final delta = event.raw.scrollDelta;
    if (delta.dy != 0) {
      ship.moveBy(-delta.dy.sign);
    } else if (delta.dx != 0) {
      ship.moveBy(delta.dx.sign);
    }
    super.onScroll(event);
  }

  /// Counts the keys that move the ship as held while down, and ignores the
  /// others.
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    final key = event.physicalKey;
    if (!_leftKeys.contains(key) && !_rightKeys.contains(key)) {
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
}) extends TubeRunnerExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerPathComponents<ExampleWorld> {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeRunnerExample({required super.status, super.random})
    extends TubeRunnerExample
    with FlamePathComponents<ExampleWorld> {
  @override
  String get rendererText => "Flame's PathComponent";

  /// None: Flame's PathComponents keep no numbers to show.
  @override
  Iterable<String> get rendererStats => const [];
}
