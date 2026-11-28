import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/game_sounds.dart';
import 'package:flame_rasterizer_example/commons/outline_paints.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_font.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/bucket_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/flipper_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/guide_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/table_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/trail_component.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

part 'revolute_pinball_snapshot.dart';

enum PinballSound(final String file) {
  flip('flip'),
  score('score'),
  empty('empty'),
  drain('drain'),
  over('crash'),
  wheel('wheel'),
  bucket('bucket'),
  bump('bump');

  String get path => 'assets/audio/$file.wav';
}

/// Which bodies each drop holds: balls and SVGs taking turns, or only one kind.
enum PinballDrops(final String label) {
  mixed('Mixed'),
  balls('Balls'),
  svgs('SVGs'),
}

abstract class RevolutePinballExample({
  @override required var bool pieces,
  required super.status,
  RevolutePinballSnapshot? from,
}) extends Forge2DExampleGame
    with
        ExampleSvgs,
        SvgBodies,
        KeyboardEvents,
        PathComponents<Forge2DExampleWorld> {
  this : super(world: RevolutePinballWorld());

  factory RevolutePinballExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    required bool pieces,
    SvgCache cache = defaultSvgCache,
    RevolutePinballSnapshot? from,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameSvgRevolutePinballExample(
          pieces: pieces,
          status: status,
          cache: cache,
          from: from,
        )
      : RasterizerRevolutePinballExample(
          pieces: pieces,
          status: status,
          renderer: renderer,
          from: from,
        );

  /// The snapshot that the game continues from, if any.
  final RevolutePinballSnapshot? _from = from;

  /// The bodies that were in a bucket before a renderer switch. The bucket
  /// treats them as already at rest.
  final settled = <BodyComponent>{};

  static const description = '''
    A pinball with the bodies of Revolute Joint Svgs. A key or a tap starts
    it, and drops 10 bodies over a wheel. Once each is in a bucket, gone
    through the drain, or at rest, the wheel turns the other way, amber until
    it's at full speed, and the next 10 drop. Left, A or Left Shift, Right, D
    or Right Shift, or a tap in the bottom third's left or right half flips a
    flipper. On a Steam Deck, Steam Input can bind the triggers to the Shift
    keys. A body coming to rest in a bucket scores by its area and the
    bucket's fill, once. Drained bodies take energy, until the game is over:
    then the table goes on, without the flippers, drops or scores. A full
    bucket gives its bodies' area back, empties, and kicks the other's bodies
    up and out. The Drops knob picks the next drops' bodies: mixed, only
    balls or only SVGs. The Sound knob turns sounds on and off.
  ''';

  /// The Drops knob's value, which applies from the next drop.
  PinballDrops drops = PinballDrops.mixed;

  /// The Sound knob's value. The sounds load the first time it's turned on.
  bool get sound => _sound;
  bool _sound = false;

  set sound(bool value) {
    _sound = value;
    if (value && _sounds == null) {
      // GameSounds plays at most 3 of each sound at once, so at most 24 in all.
      (_sounds = GameSounds([
        for (final sound in PinballSound.values) sound.path,
      ])).load();
    }
  }

  GameSounds? _sounds;

  void play(PinballSound sound) {
    if (_sound) {
      _sounds?.play(sound.path);
    }
  }

  @override
  void onRemove() {
    _sounds?.dispose();
    super.onRemove();
  }

  static final _flipperKeys = {
    LogicalKeyboardKey.arrowLeft: 0,
    LogicalKeyboardKey.keyA: 0,
    LogicalKeyboardKey.shiftLeft: 0,
    LogicalKeyboardKey.arrowRight: 1,
    LogicalKeyboardKey.keyD: 1,
    LogicalKeyboardKey.shiftRight: 1,
  };

  static const _dropped = 10;
  static const _maxBodies = 200;

  /// How long a body must stay below [_restSpeed] to be at rest, in seconds.
  static const restTime = 0.5;
  static const _restSpeed = 0.5;

  /// The game ends when [drainedArea] reaches [_drainShare] of the arena's
  /// area. Each drained body adds [_drainCost] times its area to it.
  static const _drainShare = 0.1;
  static const _drainCost = 2.0;

  static const _hudCap = 12.0;

  /// The height below the table that the HUD's 2 lines need, in logical pixels.
  static const _hudBand =
      2 * StoryGame.hudMargin + (1 + VectorTextComponent.lineSpacing) * _hudCap;

  /// The width beside the table that the HUD's widest line needs, in logical
  /// pixels: ENERGY 100% or a 5-digit score, plus a margin on each side.
  static final _hudWidth =
      VectorFont.widthOf('ENERGY 100%') * _hudCap / VectorFont.capHeight +
      2 * StoryGame.hudMargin;

  /// The smallest width-to-height ratio that the table can keep with the HUD
  /// beside it.
  static const _minAspect = 0.9;

  /// Whether the table fills the game, with the HUD over its bottom corners.
  ///
  /// It does on a desktop, when the game is at least as wide as it is high.
  static bool fills(double width, double height) =>
      width >= height &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  static bool _fills(Vector2 size) => fills(size.x, size.y);

  /// Whether a table that [fills] the game is narrowed to a square in the
  /// game's middle.
  bool get square => _square;
  bool _square = false;

  set square(bool value) {
    if (value != _square) {
      _square = value;
      if (isLoaded && _fills(size)) {
        metersToPixels = _zoomFor(size);
        _buildTable();
      }
    }
  }

  /// The table's width in logical pixels, if it [fills] the game.
  double _filledWidth(Vector2 size) => _square ? size.y : size.x;

  /// The height of the HUD's band below the table.
  ///
  /// It's 0 when the table [_fills] the game. It's also 0 when the table,
  /// narrowed to make room for the HUD on both sides, is still at least
  /// [_minAspect] times as wide as high, as in landscape on a phone.
  static double _bandFor(Vector2 size) =>
      _fills(size) || size.x - 2 * _hudWidth >= _minAspect * size.y
      ? 0
      : _hudBand;

  /// The pixels per meter: 10, as in Flame's examples, or fewer on a small
  /// screen, so that the arena is at least [_minWidth] by [_minHeight] meters.
  static const _maxZoom = 10.0;
  static const _minWidth = 60.0;
  static const _minHeight = 45.0;

  double _zoomFor(Vector2 size) => math.min(
    _maxZoom,
    math.min(
      (_fills(size) ? _filledWidth(size) : size.x) / _minWidth,
      math.max(1, size.y - _bandFor(size)) / _minHeight,
    ),
  );

  /// The flippers' angle at rest, and the guides' slope.
  static const restAngle = math.pi / 6;

  @override
  final random = math.Random();

  /// Smaller balls can get stuck at the flippers' tips.
  @override
  double get minBallRadius => 0.7;

  /// Half the balls' density, so that a kick throws SVG bodies farther.
  @override
  double get svgDensity => 0.5;

  /// The path colors, as in the MultipleShapes example: each SVG's own color,
  /// and the next one in turn for each ball.
  @override
  Color nextColor([String? svg]) {
    const colors = OutlinePaints.colors;
    final index = svg == null ? tint++ : randomSvgNames.indexOf(svg);
    return colors[index % colors.length];
  }

  /// The SVGs drawn as their wireframe, in their color.
  static const _wireframed = ['spaceship', 'robot'];
  final _wireframes = <String, ExampleSvg>{};

  /// Draws the flame SVG as it is, the [_wireframed] SVGs as their wireframes,
  /// and the others as their outlines, with paths as in the MultipleShapes
  /// example.
  @override
  PositionComponent svgImage(SvgBody body) {
    if (body.name == 'flame') {
      return super.svgImage(body);
    }
    if (_wireframes[body.name] case final wireframe?) {
      // The wireframe's viewBox is the SVG's, grown by half its stroke width on
      // each side.
      final size = body.size.clone()
        ..multiply(wireframe.size)
        ..divide(body.svg.size);
      final svg = wireframe.component()
        ..size = size * metersToPixels
        ..scale = Vector2.all(1 / metersToPixels)
        ..anchor = Anchor.center;
      (svg as HasPaint).tint(body.color);
      return svg;
    }
    final outline = body.svg.outline;
    final rect = outline.rect;
    final bounds = outline.path.getBounds();
    final scale = Vector2(body.size.x / rect.width, body.size.y / rect.height);
    return outlineComponent(
        outline.path,
        OutlinePaints.of(body.color, rect.longestSide),
        maxSize: 3 * metersToPixels * SvgBodies.maxSide,
      )
      ..position = Vector2(
        (bounds.left - rect.center.dx) * scale.x,
        (bounds.top - rect.center.dy) * scale.y,
      )
      ..scale = scale;
  }

  @override
  void addBody(BodyComponent body) {
    if (body is Ball) {
      _drawAsPath(body);
    }
    super.addBody(body);
  }

  /// A unit circle that every ball draws, scaled to its radius.
  static final _circle = Path()
    ..addOval(Rect.fromCircle(center: Offset.zero, radius: 1));

  /// Draws [ball] with paths as in the MultipleShapes example.
  void _drawAsPath(Ball ball) {
    ball
      ..glows = false
      ..add(
        outlineComponent(
            _circle,
            OutlinePaints.of(ball.paint.color, 2),
            // The largest balls are 2 meters wide.
            maxSize: 3 * metersToPixels * 2,
          )
          ..position = Vector2.all(-ball.radius)
          ..scale = Vector2.all(ball.radius),
      );
  }

  /// Creates a component that draws [path] with [paintLayers] using the game's
  /// renderer.
  ///
  /// [maxSize] is the largest size it's imported for, which allows for a device
  /// pixel ratio of up to 3.
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  });

  /// The latest trail of each body that a flipper kicked or that hit the wheel.
  final _trails = <BodyComponent, TrailComponent>{};

  TableComponent? _table;
  var _flippers = <FlipperComponent>[];
  CircleShuffler? _wheel;
  var _buckets = <BucketComponent>[];
  final _ready = VectorTextComponent(
    text: 'READY',
    capHeight: VectorTextComponent.maxCapHeight,
  );
  final _gameOver = VectorTextComponent(
    text: 'GAME OVER',
    capHeight: VectorTextComponent.maxCapHeight,
  );
  final _energyText = VectorTextComponent(
    capHeight: _hudCap,
    line: 0,
    left: true,
  );
  final _targetText = VectorTextComponent(
    capHeight: _hudCap,
    line: 1,
    left: true,
  );
  final _dropsText = VectorTextComponent(capHeight: _hudCap, line: 1);
  final _scoreText = VectorTextComponent(capHeight: _hudCap, line: 0);

  /// The energy's colors from 0% to 100%.
  static const _energyColors = [
    Color(0xFFF87171),
    Color(0xFFFB923C),
    Color(0xFFFDE047),
    Color(0xFF34D399),
  ];

  int score = 0;
  var _drops = 0;

  /// The bodies that have scored in a bucket, which don't score again.
  final scored = <BodyComponent>{};

  /// Kicks the bodies in every bucket except [except], which is starting to
  /// empty.
  void kickBuckets({required BucketComponent except}) {
    for (final bucket in _buckets) {
      if (bucket != except) {
        bucket.kick();
      }
    }
    play(PinballSound.flip);
  }

  /// The energy that drained bodies have taken, in square meters: [_drainCost]
  /// times their area, minus what full buckets gave back.
  double drainedArea = 0.0;

  var _over = false;

  double get _energy => math.max(
    0,
    1 - drainedArea / (_drainShare * _arena.width * _arena.height),
  );

  static double area(BodyComponent body) => switch (body) {
    SvgBody(:final area) => area,
    _ => body.body.mass / body.body.shapes.first.density,
  };

  /// Whether the next drop waits for the wheel to turn the other way.
  var _queued = false;

  /// The last bodies dropped, with how long each has been at rest.
  var _current = <BodyComponent, double>{};

  /// The table's largest width-to-height ratio.
  static const _maxAspect = 1.2;

  /// The table's rectangle, in meters.
  ///
  /// When the table [_fills] the game, it covers the whole game, or only the
  /// game's middle square if [square]. Otherwise it covers the game's area
  /// above the HUD's band or, without a band, between the HUD's two sides. It's
  /// centered and at most [_maxAspect] times as wide as high.
  Rect get _arena {
    if (_fills(size)) {
      return Rect.fromCenter(
        center: Offset.zero,
        width: _filledWidth(size) / metersToPixels,
        height: size.y / metersToPixels,
      );
    }
    final band = _bandFor(size);
    final room = band == 0 ? size.x - 2 * _hudWidth : size.x;
    final height = (size.y - band) / metersToPixels;
    final width = math.min(room / metersToPixels, _maxAspect * height);
    return Rect.fromLTWH(
      -width / 2,
      -size.y / 2 / metersToPixels,
      width,
      height,
    );
  }

  /// READY's and GAME OVER's cap height: at most
  /// [VectorTextComponent.maxCapHeight], and less on a short screen.
  static double _bannerCap(Vector2 size) =>
      math.min(VectorTextComponent.maxCapHeight, size.y / 8);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!await loadBodySvgs()) {
      return;
    }
    for (final name in _wireframed) {
      _wireframes[name] = await loadSvg('assets/svgs/wireframe/$name.svg');
      if (isRemoved) {
        return;
      }
    }
    camera.viewport.addAll([
      if (!(_from?.started ?? false)) _ready,
      _energyText,
      _targetText,
      _dropsText,
      _scoreText,
    ]);
    _buildTable(wheel: _from?.wheel);
    if (_from case final from?) {
      _goOnFrom(from);
    }
    startStatus();
  }

  @override
  void onGameResize(Vector2 size) {
    metersToPixels = _zoomFor(size);
    final bannerScale = _bannerCap(size) / VectorFont.capHeight;
    for (final banner in [_ready, _gameOver]) {
      banner.scale.setAll(bannerScale);
    }
    super.onGameResize(size);
    // A rebuilt widget resizes the game to the same size, which needs no new
    // table.
    if (isLoaded && size != _tableSize) {
      _buildTable();
    }
  }

  /// The game's size that the table was built for.
  final _tableSize = Vector2.zero();

  /// Rebuilds the walls, the guides, the flippers, the wheel and the buckets
  /// for the arena's size. The wheel continues from [wheel], if given.
  void _buildTable({WheelSnapshot? wheel}) {
    _tableSize.setFrom(size);
    final a = _arena;
    // Sized from the smaller side, so that a wide table looks like a square
    // one.
    final small = math.min(a.width, a.height);
    final drain = math.max(0.06 * small, SvgBodies.maxSide);
    // Longer when the table doesn't fill the game, as on a phone.
    final flipper = (_fills(size) ? 0.18 : 0.24) * small;
    // Builds the left flipper and guide, and mirrors them for the right ones.
    // The flipper's tip ends at the drain, and the guide's recess under the tip
    // reaches the table's bottom.
    const angle = restAngle;
    const gap = FlipperComponent.gap;
    final bottom = FlipperComponent.bottomAngle(flipper);
    final tip = FlipperComponent.tipCenter(flipper);
    final floor =
        (tip +
              Vector2(math.cos(bottom), math.sin(bottom)) *
                  (FlipperComponent.tipRadius + gap))
          ..rotate(angle);
    final pivot = Vector2(
      -drain - FlipperComponent.tipRadius - (tip.clone()..rotate(angle)).x,
      a.bottom - floor.y,
    );
    final socket = [
      for (final p in FlipperComponent.arc(
        Vector2.zero(),
        FlipperComponent.radius + gap,
        math.pi +
            math.asin(
              FlipperComponent.radius / (FlipperComponent.radius + gap),
            ),
        bottom,
      ))
        p
          ..rotate(angle)
          ..add(pivot),
    ];
    final top = socket.first;
    final guide = [
      Vector2(a.left, top.y - (top.x - a.left) * math.tan(angle)),
      ...socket,
      pivot + floor,
      Vector2(a.left, a.bottom),
    ];
    final bucketWidth = math.max(0.2 * a.width, 2 * SvgBodies.maxSide);
    // From the height even on a table taller than wide, so that the bucket
    // holds as many bodies as on a wider table, where the height is the smaller
    // side.
    final bucketHeight = 0.2 * a.height;
    final bucketTop = a.top + 0.15 * a.height;
    final bucketBottom = bucketTop + bucketHeight + BucketComponent.thickness;
    final wheelReach = 0.15 * small;
    final table = TableComponent([
      Wall(Vector2(a.left, a.top), Vector2(a.right, a.top), hitEvents: true),
      Wall(Vector2(a.left, a.top), Vector2(a.left, a.bottom), hitEvents: true),
      Wall(
        Vector2(a.right, a.top),
        Vector2(a.right, a.bottom),
        hitEvents: true,
      ),
      GuideComponent(guide),
      GuideComponent([for (final v in guide.reversed) Vector2(-v.x, v.y)]),
      ..._flippers = [
        for (final side in [-1, 1])
          FlipperComponent(Vector2(-side * pivot.x, pivot.y), flipper, side),
      ],
      _wheel = CircleShuffler(
        // Its center is level with the buckets' bottom. On a table taller than
        // wide, its top is there instead, so that it throws the bodies under
        // the buckets.
        Vector2(0, bucketBottom + (a.height > a.width ? wheelReach : 0)),
        scale: wheelReach / CircleShuffler.reach,
        color: ExampleColors.dynamicColor(0),
        from: wheel,
      ),
      ..._buckets = [
        for (final side in [-1, 1])
          BucketComponent(
            Rect.fromCenter(
              center: Offset(
                side * (a.right - 0.06 * a.width - bucketWidth / 2),
                bucketTop + bucketHeight / 2,
              ),
              width: bucketWidth,
              height: bucketHeight,
            ),
          ),
      ],
    ]);
    _table?.next = table;
    world.add(_table = table);
  }

  var _started = false;

  void _start() {
    if (_over) {
      _newGame();
    } else if (!_started && isLoaded) {
      _started = true;
      _ready.removeFromParent();
      spawn();
    }
  }

  /// Releases the flippers and shows GAME OVER until a key press or a tap.
  ///
  /// The table keeps running, except that drained bodies take no energy and the
  /// buckets don't score.
  void _endGame() {
    _over = true;
    for (final flipper in _flippers) {
      flipper.releaseAll();
    }
    camera.viewport.add(_gameOver);
  }

  /// Clears the bodies and the score, and waits at READY.
  void _newGame() {
    _over = false;
    _started = false;
    _gameOver.removeFromParent();
    removeBodies([...svgBodies, ...balls]);
    _current = {};
    _queued = false;
    scored.clear();
    score = 0;
    _drops = 0;
    drainedArea = 0;
    for (final bucket in _buckets) {
      bucket.restart();
    }
    camera.viewport.add(_ready);
  }

  void spawn() {
    if (!isLoaded) {
      return;
    }
    _drops++;
    _sinceDrop = 0;
    final spawn = Vector2(0, _arena.top + 0.1 * _arena.height);
    final ballsFirst = random.nextBool();
    final bodies = [
      for (var i = 0; i < _dropped; i++)
        if (switch (drops) {
          PinballDrops.mixed => i.isEven == ballsFirst,
          PinballDrops.balls => true,
          PinballDrops.svgs => false,
        })
          randomBall()
        else
          randomSvg(spin: 2),
    ];
    final positions = spreadAround(
      spawn,
      [for (final body in bodies) body.radius],
      bounds: _arena.deflate(Wall.width),
      world: world.physicsWorld,
      random: random,
    );
    _current = {};
    for (final (i, body) in bodies.indexed) {
      final position = positions[i];
      final component = body.create(
        position,
        awayFrom(spawn, position, 2, random),
      );
      addBody(component);
      _current[component] = 0;
    }
  }

  /// Whether [body] has drained, counts in a bucket, or has been at rest for
  /// [restTime], after [dt] more seconds.
  bool _done(BodyComponent body, double dt) {
    if (body.isRemoving || body.isRemoved) {
      return true;
    }
    if (!body.isLoaded) {
      return false;
    }
    if (_buckets.any((bucket) => bucket.counts(body))) {
      return true;
    }
    final time = _current[body] = isStill(body.body) ? _current[body]! + dt : 0;
    return time >= restTime;
  }

  static bool isStill(Body body) =>
      body.linearVelocity.length < _restSpeed &&
      body.angularVelocity.abs() < _restSpeed;

  /// Starts a trail behind [body]'s component, unless its last one is still
  /// going, and returns whether it did.
  bool _kicked(Body body) {
    for (final component in [...svgBodies, ...balls]) {
      if (component.isLoaded && component.body == body) {
        if (_trails[component]?.over ?? true) {
          world.add(_trails[component] = TrailComponent(component));
          return true;
        }
        return false;
      }
    }
    return false;
  }

  /// How long a body that hits the wheel and starts a trail brakes the wheel,
  /// in seconds per meter a second of its hit speed.
  ///
  /// Hits brake the wheel only after [_dropGrace] seconds have passed since the
  /// last drop.
  static const _brakePerSpeed = 0.05;
  static const _dropGrace = 2.5;

  /// How fast a body must hit a wall, a slide or a bucket to make a sound, in
  /// meters a second.
  static const _minHitSpeed = 4.0;
  var _sinceDrop = double.infinity;

  @override
  void update(double dt) {
    super.update(dt);
    _sinceDrop += dt;
    _sounds?.nextFrame();
    _trails.removeWhere((_, trail) => trail.over);
    scored.removeWhere((body) => body.isRemoved);
    _scoreText.text = 'SCORE $score';
    _dropsText.text = 'DROP $_drops';
    final energy = _energy;
    final x = energy * (_energyColors.length - 1);
    final i = math.min(x.floor(), _energyColors.length - 2);
    _energyText
      ..text = 'ENERGY ${(100 * energy).round()}%'
      ..tint = Color.lerp(_energyColors[i], _energyColors[i + 1], x - i);
    final target = _buckets.map((b) => b.level).fold(0.0, math.max);
    _targetText.text = 'TARGET ${(100 * target).round()}%';
    final bottom = _arena.bottom + SvgBodies.maxSide;
    bool drained(BodyComponent body) =>
        body.isLoaded && body.body.position.y > bottom;
    final gone = [...svgBodies.where(drained), ...balls.where(drained)];
    if (gone.isNotEmpty) {
      // After the game is over, drained bodies take no energy and make no
      // sound.
      if (!_over) {
        drainedArea +=
            _drainCost * gone.fold(0.0, (sum, body) => sum + area(body));
        play(PinballSound.drain);
      }
      removeBodies(gone);
    }
    if (_over) {
      for (final bucket in _buckets) {
        bucket.finishEmptying(dt);
      }
      return;
    }
    for (final bucket in _buckets) {
      bucket.track([...svgBodies, ...balls], dt);
    }
    if (_started && _energy < 0.005) {
      play(PinballSound.over);
      _endGame();
      return;
    }
    final done = [for (final body in _current.keys.toList()) _done(body, dt)];
    if (_started &&
        !done.contains(false) &&
        svgBodies.length + balls.length + _dropped <= _maxBodies) {
      if (!_queued) {
        _queued = true;
        _wheel?.reverse();
      } else if (!(_wheel?.reversing ?? false)) {
        _queued = false;
        spawn();
      }
    }
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (!_started || _over) {
      if (event is KeyDownEvent) {
        _start();
      }
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    final flipper = _flipperKeys[key];
    if (flipper == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _hold(flipper, key);
    } else if (event is KeyUpEvent) {
      _release(key);
    }
    return KeyEventResult.handled;
  }

  void _hold(int flipper, Object holder) {
    if (_flippers.elementAtOrNull(flipper)?.hold(holder) ?? false) {
      play(PinballSound.flip);
    }
  }

  void _release(Object holder) {
    for (final flipper in _flippers) {
      flipper.release(holder);
    }
  }
}

class RevolutePinballWorld()
    extends Forge2DExampleWorld
    with TapCallbacks, HasGameRef<RevolutePinballExample> {
  @override
  void update(double dt) {
    super.update(dt);
    final events = physicsWorld.contactEvents;
    for (final flipper in gameRef._flippers) {
      flipper.track(events);
      if (flipper.kicking) {
        flipper.touching.forEach(gameRef._kicked);
      }
    }
    // Except for the wheel, only the walls, the slides and the buckets report
    // hits.
    final wheelBody = gameRef._wheel?.isLoaded ?? false
        ? gameRef._wheel!.body
        : null;
    for (final hit in events.hit) {
      if (!hit.shapeA.isValid ||
          !hit.shapeB.isValid ||
          hit.approachSpeed < RevolutePinballExample._minHitSpeed) {
        continue;
      }
      final bodies = [hit.shapeA.body, hit.shapeB.body];
      if (!bodies.contains(wheelBody)) {
        final bucket = gameRef._buckets.any(
          (bucket) => bucket.isLoaded && bodies.contains(bucket.body),
        );
        gameRef.play(bucket ? PinballSound.bucket : PinballSound.bump);
      }
    }
    // A body that hits the wheel starts a trail as if kicked, and brakes the
    // wheel by how hard it hit.
    if (gameRef._wheel case final wheel? when wheel.isLoaded) {
      Body? other(Shape a, Shape b) => !a.isValid || !b.isValid
          ? null
          : a.body == wheel.body
          ? b.body
          : b.body == wheel.body
          ? a.body
          : null;
      final speeds = <Body, double>{};
      for (final hit in events.hit) {
        if (other(hit.shapeA, hit.shapeB) case final body?) {
          speeds[body] = math.max(speeds[body] ?? 0, hit.approachSpeed);
        }
      }
      for (final event in events.begin) {
        if (other(event.shapeA, event.shapeB) case final body?
            when gameRef._kicked(body)) {
          gameRef.play(PinballSound.wheel);
          if (gameRef._sinceDrop >= RevolutePinballExample._dropGrace) {
            wheel.brake(
              RevolutePinballExample._brakePerSpeed * (speeds[body] ?? 0),
            );
          }
        }
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!gameRef._started || gameRef._over) {
      gameRef._start();
      return;
    }
    final position = event.canvasPosition;
    if (position.y > gameRef.size.y * 2 / 3) {
      gameRef._hold(position.x < gameRef.size.x / 2 ? 0 : 1, event.pointerId);
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    gameRef._release(event.pointerId);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    gameRef._release(event.pointerId);
  }
}

class RasterizerRevolutePinballExample({
  required super.pieces,
  required super.status,
  super.from,
  @override required final SvgRenderer renderer,
}) extends RevolutePinballExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerSvgs,
        RasterizerPathComponents {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  }) => RasterizerPathComponent(
    path: path,
    paintLayers: paintLayers,
    maxSize: maxSize,
    // Its polygons aren't used.
    sampling: path.getBounds().longestSide,
  );
}

class FlameSvgRevolutePinballExample({
  required super.pieces,
  required super.status,
  super.from,
  final SvgCache cache = defaultSvgCache,
}) extends RevolutePinballExample with FlameSvgs, FlamePathComponents {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;

  @override
  PathComponent outlineComponent(
    Path path,
    List<Paint> paintLayers, {
    required double maxSize,
  }) => PathComponent(
    path: path,
    paintLayers: paintLayers,
    // Its polygons aren't used.
    sampling: path.getBounds().longestSide,
  );
}
