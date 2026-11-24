import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/flight_stars_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/runner_seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/components/ship_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
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
    left and right, or a lane per scroll of the mouse wheel. The Tube knob
    picks one of Tube Shooter's closed tubes, which the ship goes on down
    without a stop. The ship's lane shows in the ship's colour, as in Tube
    Shooter.

    After 8 seconds, and every 5 seconds from then on, a seeder comes at the
    farthest ring across the tube, on a lane picked at random. It climbs its lane toward the ship, laying a
    spike behind it, and goes once it passes the ship; the spike goes once
    all of it does. Nothing collides yet.

    The game makes the tube's quads again every frame. The mesh renderer fills
    each quad on its own, as a fan of triangles, rather than their union. The
    bar under the game shows the renderer, the frame times, the renderer's own
    numbers, the tube's quads and the paths made each second.
  ''';

  /// How fast the ship flies, in tube units a second.
  static const flightSpeed = 2.0;

  /// When the first seeder comes, and how often the others do, in seconds
  /// of the game.
  static const firstSeeder = 8.0;
  static const seederPeriod = 5.0;

  /// How far a drag goes to move the ship one lane, in logical pixels.
  static const dragPerLane = 40.0;

  final math.Random random = random ?? math.Random();

  final view = TubeView()..tube = tube ?? Tubes.hexagon;

  final endlessTube = EndlessTube();

  /// The tube it flies down, one of [tubes].
  Tube get tube => view.tube;

  /// Changes the tube where the ship is, without a stop: the ship goes on at
  /// the same angle round the axis, in the new tube's nearest step. The
  /// seeders and spikes go.
  set tube(Tube value) {
    final from = view.tube;
    if (value == from) {
      return;
    }
    view.tube = value;
    if (ship.isLoaded) {
      ship.switchFrom(from);
    }
    for (final seeder in _seeders) {
      seeder.removeFromParent();
    }
    _seeders.clear();
    _spikes.clear();
  }

  final tubeGroup = Component();
  final ship = ShipComponent();
  final stars = FlightStarsComponent();

  /// How far the ship has flown along the tube's axis, in tube units.
  double get flown => _flown;
  double _flown = 0;

  /// The components that draw the tube, and the ship's lane over it in the
  /// ship's colour, as Tube Shooter does.
  PositionComponent? _tube;
  PositionComponent? _lane;
  PositionComponent? _spikesDrawing;

  /// The seeders climbing the tube, and the spikes they laid, nearest first.
  final _seeders = <RunnerSeederComponent>[];
  final _spikes = <Spike>[];

  /// How long the game has run since the last seeder came, or since
  /// [seederPeriod] before [firstSeeder].
  double _seederTime = seederPeriod - firstSeeder;

  /// How far the ship had flown, the view's version and the ship's lane, as
  /// the tube's paths were made last.
  double _tubeFlown = double.nan;
  int _tubeVersion = -1;
  int? _tubeLane;

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
    _updateSeeders(dt * world.timeScale);
    endlessTube.advanceTo(_flown);
    _updateTube();
    super.update(dt);
  }

  /// Makes the tube's paths again if the ship flew or changed lanes, or the
  /// view changed.
  void _updateTube() {
    // The ship knows its lane once loaded.
    final lane = ship.isLoaded ? ship.lane : null;
    if (_flown == _tubeFlown &&
        view.version == _tubeVersion &&
        lane == _tubeLane) {
      return;
    }
    _tubeFlown = _flown;
    _tubeVersion = view.version;
    _tubeLane = lane;
    final quads = endlessTube.quadsAt(
      _flown,
      view,
      lane: lane,
      spikes: _spikes,
    );
    _quads =
        quads.tube.vertexCounts.length +
        quads.lane.vertexCounts.length +
        quads.spikes.vertexCounts.length;
    _tube = _replaceQuads(_tube, quads.tube, TubeColors.tube);
    _lane = _replaceQuads(_lane, quads.lane, TubeColors.ship);
    _spikesDrawing = _replaceQuads(
      _spikesDrawing,
      quads.spikes,
      TubeColors.spikes,
    );
    for (final seeder in _seeders) {
      seeder.placeAt(quads.seeders[_spikes.indexOf(seeder.spike)]);
    }
  }

  /// Over [dt] seconds of the game: brings a seeder at [firstSeeder], then
  /// every [seederPeriod], at the farthest ring across the tube, climbs the
  /// seeders, and drops those past the ship, and the spikes all past it.
  void _updateSeeders(double dt) {
    _seederTime += dt;
    if (_seederTime >= seederPeriod) {
      _seederTime -= seederPeriod;
      const spacing = EndlessTube.ringSpacing;
      final far = ((_flown + EndlessTube.ahead) / spacing).floor() * spacing;
      final spike = Spike(random.nextInt(tube.laneCount), far);
      final seeder = RunnerSeederComponent(spike);
      _spikes.add(spike);
      _seeders.add(seeder);
      world.add(seeder);
    }
    for (final seeder in _seeders) {
      seeder.climb(dt);
    }
    _seeders.removeWhere((seeder) {
      final passed = seeder.spike.near < _flown;
      if (passed) {
        seeder.removeFromParent();
      }
      return passed;
    });
    _spikes.removeWhere((spike) => spike.far < _flown);
  }

  /// Removes [old], if any, and returns a component that fills [quads] in
  /// [color], added to [tubeGroup], if there are any.
  PositionComponent? _replaceQuads(
    PositionComponent? old,
    RasterizerPolygons quads,
    Color color,
  ) {
    old?.removeFromParent();
    if (quads.bounds.isEmpty) {
      return null;
    }
    _paths++;
    final component = quadsComponent(quads, color);
    tubeGroup.add(component);
    return component;
  }

  /// Creates a component that fills [quads] in [color], where they are in
  /// the world.
  PositionComponent quadsComponent(RasterizerPolygons quads, Color color);

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
  /// than their union. The tube is opaque, so their overlaps don't show.
  @override
  PositionComponent quadsComponent(RasterizerPolygons quads, Color color) =>
      RasterizerPolygonsComponent(
        polygons: quads,
        paint: Paint()..color = color,
        position: Vector2(quads.bounds.left, quads.bounds.top),
        maxSize: maxSizeOf(quads),
        separate: true,
      );
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

  /// Fills a path of the quads.
  ///
  /// Its contours stay open, as the fill closes them anyway. Flame's
  /// `PathComponent` would walk each closed contour into a polygon, which the
  /// game doesn't use, as [RasterizerPolygons.path]'s are.
  @override
  PositionComponent quadsComponent(RasterizerPolygons quads, Color color) {
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
