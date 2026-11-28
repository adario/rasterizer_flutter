import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/outline_paints.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/svg/collidable_svgs_example.dart'
    show CollidableArena;
import 'package:flutter/widgets.dart';

part 'multiple_shapes_snapshot.dart';

/// The values of the example's knobs, except Zoom, Speed and the cache knobs.
typedef MultipleShapesSettings = ({
  SvgRenderer renderer,
  Shapes shapes,
  int count,
});

/// What a shape picks at random: the index of its SVG's or outline's size, and
/// its width at a scale of 1.
typedef ShapePick = ({int sizeIndex, double width});

/// What the example's shapes are.
enum Shapes(final String label) {
  /// SVGs, drawn as they are.
  svgs('SVGs'),

  /// SVGs' outlines, each as one path, filled and stroked in a color of its
  /// own.
  ///
  /// A [RasterizerPathComponent] draws each one with flame_rasterizer, and
  /// Flame's [PathComponent] draws it with Flame SVG.
  paths('Paths'),
}

/// Shapes and a snowman that move, spin and collide: see [description].
///
/// [count] shapes, made from SVGs picked at random, fill the arena in rows. The
/// arena is a rectangle of the game's size, centered on the world's origin. The
/// shapes are the SVGs or their outlines, as [shapes] says. The status adds the
/// number of shapes, and of those colliding at the moment, to what
/// [ExampleGame] shows.
///
/// Given the snapshot of a game with another renderer, the game resumes from it
/// with the same shapes: see [MultipleShapesSnapshots].
abstract class MultipleShapesExample({
  required final Shapes shapes,
  required var int _count,
  required super.status,
  math.Random? random,
  MultipleShapesSnapshot? from,
}) extends ExampleGame with ExampleSvgs, HasCollisionDetection {
  /// Creates the game for the renderer and shapes in [settings], resuming from
  /// [from] if given.
  ///
  /// Flame SVG uses flame_svg's [cache] settings.
  factory MultipleShapesExample.of(
    MultipleShapesSettings settings,
    ValueNotifier<String> status, {
    SvgCache cache = defaultSvgCache,
    math.Random? random,
    MultipleShapesSnapshot? from,
  }) => settings.renderer == SvgRenderer.flameSvg
      ? FlameMultipleShapesExample(
          shapes: settings.shapes,
          count: settings.count,
          status: status,
          cache: cache,
          random: random,
          from: from,
        )
      : RasterizerMultipleShapesExample(
          shapes: settings.shapes,
          count: settings.count,
          status: status,
          renderer: settings.renderer,
          random: random,
          from: from,
        );

  static const description = '''
    Shapes made from SVGs picked at random fill the arena in rows, with a
    snowman of three circles, as in Flame's multiple shapes example. They
    move, spin and wrap around the arena's walls. Drag a shape to throw it.

    Their hitboxes follow the contours of the SVGs' paths: they're
    flame_rasterizer's SvgHitbox, whatever draws the shapes. While a shape
    collides with another, it's tinted green, and purple on the walls. The
    snowman's circles, many hitboxes in one component, turn their own colors.

    The Shapes knob picks Paths, the default, or SVGs. Paths are each SVG's
    outline as one path, filled and stroked in a color of its own.
    RasterizerPathComponent draws them with the renderer that the Renderer
    knob picks; with Flame SVG, Flame's PathComponent does.

    The other knobs pick the shape number, zoom the camera and change the
    game's speed. With Flame SVG and SVGs, the cache knobs set flame_svg's
    cache. Only a new renderer, new shapes or a new cache make a new game. A
    new renderer's game goes on with the same shapes, from where they were.
    The bar under the game shows the renderer, the frame times, the
    renderer's own numbers, the shapes and those colliding now.

    Based on Flame's MultipleShapesExample.
  ''';

  /// The gap between two components in a row, at a scale of 1, as in
  /// Flame's example.
  static const _gap = 100.0;

  /// The gap between two rows' tops, at a scale of 1, as in Flame's example.
  static const _rowHeight = 200.0;

  /// The snowman's top left corner, from the arena's top left corner, as in
  /// Flame's example.
  static final _snowmanPosition = Vector2.all(150);

  /// The snowman's size, as in Flame's example.
  static final _snowmanSize = Vector2(120, 250);

  final math.Random random = random ?? math.Random();

  /// The snapshot that the game resumes from, if any.
  final MultipleShapesSnapshot? _from = from;

  /// The value of the Shape Number knob, not counting the snowman.
  ///
  /// A new value changes the running game: it adds shapes where there's room or
  /// removes the last ones. Then it resizes them all to the largest scale at
  /// which that many shapes fit in the rows.
  int get count => _count;
  set count(int value) {
    if (value == _count) {
      return;
    }
    _count = value;
    if (_laidOut) {
      _fit();
    }
  }

  /// The arena, whose walls the components wrap around.
  late final CollidableArena arena;

  /// The snowman, once loaded.
  late final CollidableSnowman snowman;

  /// The shapes, once loaded.
  final tintedShapes = <TintedShape>[];

  /// The snowman and the shapes.
  List<MovingCollidable> get collidables => [snowman, ...tintedShapes];

  /// The SVGs of [randomSvgNames], loaded up front when [shapes] is SVGs.
  final _svgs = <ExampleSvg>[];

  /// The outlines of [randomSvgNames], loaded up front when [shapes] is
  /// Paths.
  final _outlines = <SvgOutline>[];

  /// The size of each SVG or outline. The shapes made from it keep its aspect
  /// ratio.
  final _sizes = <Vector2>[];

  /// The index in [_sizes] and the width at a scale of 1 picked for each shape.
  ///
  /// It holds at least one pick for each shape.
  final _picks = <ShapePick>[];

  /// Whether [onLoad] has laid out the first shapes in rows.
  bool _laidOut = false;

  /// Creates a component that draws [path] with [paintLayers].
  ///
  /// Its polygons sample the path every [sampling] units of the path.
  PathComponent pathComponent(
    ui.Path path,
    List<ui.Paint> paintLayers,
    double sampling,
  );

  @override
  Iterable<String> get exampleStats {
    final colliding = collidables.where((c) => c.isColliding).length;
    final what = shapes == Shapes.svgs ? 'SVGs' : 'paths';
    return [
      '${tintedShapes.length} $what and a snowman',
      '$colliding colliding',
    ];
  }

  @override
  Future<void> onLoad() async {
    for (final name in randomSvgNames) {
      final path = 'assets/svgs/$name.svg';
      switch (shapes) {
        case Shapes.svgs:
          final svg = await loadSvg(path);
          _svgs.add(svg);
          _sizes.add(svg.size);
        case Shapes.paths:
          final outline = await loadOutline(path);
          _outlines.add(outline);
          _sizes.add(Vector2(outline.rect.width, outline.rect.height));
      }
      // The game was removed while it loaded.
      if (isRemoved) {
        return;
      }
    }
    arena = CollidableArena(size: size.clone());
    world.add(arena);
    snowman = CollidableSnowman(
      position: arena.topLeftPosition + _snowmanPosition,
      size: _snowmanSize.clone(),
      velocity: Vector2(-100, 100),
    );
    world.add(snowman);
    _restorePicks();
    _fit();
    _restoreCollidables();
    _laidOut = true;
    startStatus();
  }

  /// Keeps the first [count] shapes and adds new ones, all at the largest scale
  /// at which [count] shapes fit in the rows.
  ///
  /// At the start, the new shapes go in the rows. Later, they go wherever
  /// there's room.
  void _fit() {
    final target = _count;
    while (_picks.length < target) {
      _picks.add((
        sizeIndex: random.nextInt(_sizes.length),
        // 50 to 150 wide at a scale of 1.
        width: 50 + random.nextDouble() * 100,
      ));
    }
    final scale = _scaleFor(target);
    if (tintedShapes.length > target) {
      world.removeAll(tintedShapes.sublist(target));
      tintedShapes.length = target;
    }
    for (final (i, shape) in tintedShapes.indexed) {
      shape.resize(_sizeOf(i, scale));
    }
    final rows = _laidOut ? const <Vector2>[] : _rows(scale, target);
    final topLeft = arena.topLeftPosition;
    for (var i = tintedShapes.length; i < target; i++) {
      final shapeSize = _sizeOf(i, scale);
      final shape = _shape(
        _picks[i].sizeIndex,
        position: i < rows.length
            ? rows[i] + topLeft
            : arena.freePosition(shapeSize, collidables, random),
        size: shapeSize,
      );
      tintedShapes.add(shape);
      world.add(shape);
    }
  }

  /// Creates a shape from the [k]th SVG or its outline, at [position] and of
  /// [size], with a random velocity and rotation speed.
  TintedShape _shape(
    int k, {
    required Vector2 position,
    required Vector2 size,
  }) {
    final velocity = (Vector2.random(random) - Vector2.random(random)) * 200;
    final rotationSpeed = 0.5 - random.nextDouble();
    if (shapes == Shapes.svgs) {
      return TintedSvg(
        _svgs[k],
        position: position,
        size: size,
        velocity: velocity,
        rotationSpeed: rotationSpeed,
      );
    }
    final outline = _outlines[k];
    final rect = outline.rect;
    // Sample the polygons once per unit of the shape's size, as its hitbox
    // does.
    final units = math.max(size.x / rect.width, size.y / rect.height);
    return TintedPath(
      outline,
      pathComponent(outline.path, _pathPaints(k), 1 / units),
      position: position,
      size: size,
      velocity: velocity,
      rotationSpeed: rotationSpeed,
    );
  }

  /// Creates [OutlinePaints] for the path of the [k]th outline, in the
  /// outline's color.
  ///
  /// All the shapes of an outline get equal paints, so with flame_rasterizer
  /// they share one import. Each shape still gets its own paint objects, so
  /// that each one is tinted separately.
  List<ui.Paint> _pathPaints(int k) => OutlinePaints.of(
    OutlinePaints.colors[k % OutlinePaints.colors.length],
    _outlines[k].rect.longestSide,
  );

  /// Returns the size of the [i]th shape at [scale].
  Vector2 _sizeOf(int i, double scale) {
    final (:sizeIndex, :width) = _picks[i];
    final aspect = _sizes[sizeIndex];
    return Vector2(width, width * aspect.y / aspect.x)..scale(scale);
  }

  /// Returns the largest scale, up to 1 and in steps of 0.01, at which [target]
  /// shapes fit in the rows.
  double _scaleFor(int target) {
    for (var percent = 100; percent > 1; percent--) {
      if (_rows(percent / 100, target).length == target) {
        return percent / 100;
      }
    }
    return 0.01;
  }

  /// Returns the centers of as many of the first [target] shapes as fit in the
  /// rows of Flame's example at [scale], relative to the arena's top left
  /// corner.
  ///
  /// The first shape goes after the snowman, treating the snowman's top left
  /// corner as its center. Each other shape goes after the one before it, or at
  /// the start of a new row.
  List<Vector2> _rows(double scale, int target) {
    final gap = _gap * scale;
    final centers = <Vector2>[];
    var (last, lastWidth) = (_snowmanPosition, _snowmanSize.x);
    for (var i = 0; i < target; i++) {
      final shapeSize = _sizeOf(i, scale);
      var center = Vector2(gap, last.y + _rowHeight * scale);
      if (last.x + lastWidth / 2 + gap + shapeSize.x <= size.x) {
        center = Vector2(last.x + gap + shapeSize.x / 2, last.y);
      }
      final bottomRight = center + shapeSize / 2;
      if (bottomRight.x >= size.x || bottomRight.y >= size.y) {
        break;
      }
      centers.add(center);
      (last, lastWidth) = (center, shapeSize.x);
    }
    return centers;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // The components that the new size leaves outside wrap around the new
    // walls.
    if (isLoaded) {
      arena.size = size.clone();
    }
  }
}

/// A component that moves with [velocity] and spins at [rotationSpeed], in
/// radians a second.
///
/// It wraps around to the other side of the game's arena when it leaves it. It
/// stops while dragged, and the drag throws it when it ends.
abstract class MovingCollidable({
  required super.position,
  required super.size,
  required final Vector2 velocity,
  required var double rotationSpeed,
  super.anchor = Anchor.center,
}) extends PositionComponent
    with DragCallbacks, CollisionCallbacks, GestureHitboxes {
  /// The dot at its center that shows it's dragged.
  final _dragIndicator = _DragIndicator();

  @override
  void update(double dt) {
    super.update(dt);
    if (isDragged) {
      return;
    }
    position.addScaled(velocity, dt);
    angle = (angle + dt * rotationSpeed) % (2 * math.pi);
    _wrap();
  }

  /// Brings it back in on the other side of the arena when it's wholly outside,
  /// as in Flame's example.
  ///
  /// Its rotation doesn't count: the check uses its unrotated size.
  void _wrap() {
    final game = findGame();
    if (game is! MultipleShapesExample) {
      return;
    }
    final rect = game.arena.toRect();
    final center = absoluteCenter;
    // Its scaled size, without making a Vector2 as `scaledSize` does.
    final width = this.width * scale.x.abs();
    final height = this.height * scale.y.abs();
    var dx = 0.0;
    var dy = 0.0;
    if (center.x + width / 2 < rect.left) {
      dx = rect.width + width;
    } else if (center.x - width / 2 > rect.right) {
      dx = -rect.width - width;
    }
    if (center.y + height / 2 < rect.top) {
      dy = rect.height + height;
    } else if (center.y - height / 2 > rect.bottom) {
      dy = -rect.height - height;
    }
    if (dx != 0 || dy != 0) {
      position.setValues(position.x + dx, position.y + dy);
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragIndicator.position = size / 2;
    add(_dragIndicator);
  }

  /// Throws it at a tenth of the drag's speed, as in Flame's example. The
  /// speed is in world units, so it's the same at any zoom.
  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _dragIndicator.removeFromParent();
    final zoom = findGame()?.camera.viewfinder.zoom ?? 1;
    velocity.setFrom(event.velocity / (10 * zoom));
  }
}

/// A white dot, above its parent's other children.
class _DragIndicator() extends PositionComponent {
  this : super(priority: 1);

  static final _paint = ui.Paint()..color = const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) => canvas.drawCircle(Offset.zero, 5, _paint);
}

/// A shape with an [SvgHitbox] from an SVG's [outline], tinted while it
/// collides.
///
/// It's tinted green while it collides with another shape, and purple while it
/// collides with the arena's walls, as in Flame's example. The tint is a color
/// filter, like the one that Flame's `tint` sets.
abstract class TintedShape(
  final SvgOutline outline, {
  required super.position,
  required super.size,
  required super.velocity,
  required super.rotationSpeed,
}) extends MovingCollidable {
  /// Flame's example's green: Material's green at an alpha of 0.8.
  static const collisionTint = Color(0xCC4CAF50);

  /// Flame's example's purple: Material's purple at an alpha of 0.8.
  static const wallTint = Color(0xCC9C27B0);

  /// The component that draws it.
  @protected
  PositionComponent get image;

  /// Fits [image] to its size.
  @protected
  void fitImage();

  /// The color filter that it's drawn with: the one from `tint` while it
  /// collides, or null otherwise.
  @visibleForTesting
  ui.ColorFilter? get tintFilter;

  /// Tints it with [color], or clears its tint if [color] is null.
  @protected
  void tintWith(Color? color);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    fitImage();
    addAll([image, SvgHitbox(outline, size: size)]);
  }

  /// Resizes it and its image to [value]. Its hitbox follows its size.
  void resize(Vector2 value) {
    size = value;
    fitImage();
  }

  @override
  void onCollisionStart(
    List<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    tintWith(other is CollidableArena ? wallTint : collisionTint);
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    super.onCollisionEnd(other);
    if (!isColliding) {
      tintWith(null);
    }
  }
}

/// An SVG, tinted with Flame's `tint`.
///
/// With flame_rasterizer, [RasterizerSvgComponent] makes the tint's filter,
/// so that tinted SVGs share a run.
class TintedSvg(
  final ExampleSvg svg, {
  required super.position,
  required super.size,
  required super.velocity,
  required super.rotationSpeed,
}) extends TintedShape {
  this : super(svg.outline);

  /// The component that draws its SVG.
  @override
  late final PositionComponent image = svg.component();

  /// [image], as the [HasPaint] that both renderers' components are.
  HasPaint get _painted => image as HasPaint;

  @override
  void fitImage() => image.size = size;

  @override
  ui.ColorFilter? get tintFilter => _painted.paint.colorFilter;

  @override
  void tintWith(Color? color) {
    if (color == null) {
      _painted.paint.colorFilter = null;
    } else {
      _painted.tint(color);
    }
  }
}

/// An SVG's outline, drawn by [image], a [PathComponent] of the outline's path.
///
/// A [RasterizerPathComponent] applies its `paint` over its paint layers, as a
/// [RasterizerSvgComponent] does. So it's tinted with Flame's `tint`, and
/// flame_rasterizer makes the tint's filter, so that tinted paths share a run.
/// Flame's own [PathComponent] doesn't apply its `paint` when it has paint
/// layers, so each of its layers gets a filter like `tint`'s instead.
class TintedPath(
  super.outline,
  @override final PathComponent image, {
  required super.position,
  required super.size,
  required super.velocity,
  required super.rotationSpeed,
}) extends TintedShape {
  /// Places and scales [image], as [SvgHitbox] does with its polygons, so that
  /// the outline's rect stretches to the shape's size.
  @override
  void fitImage() {
    final rect = outline.rect;
    if (rect.isEmpty) {
      return;
    }
    final sx = size.x / rect.width;
    final sy = size.y / rect.height;
    // A path component draws its path from the path bounds' top left corner.
    final bounds = outline.path.getBounds();
    image
      ..position.setValues(
        (bounds.left - rect.left) * sx,
        (bounds.top - rect.top) * sy,
      )
      ..scale.setValues(sx, sy);
  }

  @override
  ui.ColorFilter? get tintFilter => switch (image) {
    RasterizerPathComponent(:final paint) => paint.colorFilter,
    _ => image.paintLayers.first.colorFilter,
  };

  @override
  void tintWith(Color? color) {
    final image = this.image;
    if (image is RasterizerPathComponent) {
      if (color == null) {
        image.paint.colorFilter = null;
      } else {
        image.tint(color);
      }
      return;
    }
    final filter = color == null
        ? null
        : ui.ColorFilter.mode(color, ui.BlendMode.srcATop);
    for (final paint in image.paintLayers) {
      paint.colorFilter = filter;
    }
  }
}

/// Three circles on top of each other, as in Flame's example: many hitboxes
/// in one component.
///
/// Each circle is a [SnowmanPart], a hitbox with its own color.
class CollidableSnowman({
  required super.position,
  required super.size,
  required super.velocity,
}) extends MovingCollidable {
  this : super(rotationSpeed: 0.3, anchor: Anchor.topLeft);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    addAll([
      SnowmanPart(
        radius: size.x / 2,
        position: Vector2(size.x / 2, size.y - size.y / 4),
        hitColor: const Color(0xFF4CAF50),
      ),
      SnowmanPart(
        radius: size.x * 0.4,
        position: Vector2(size.x / 2, size.y * 0.4),
        hitColor: const Color(0xFFFFEB3B),
      ),
      SnowmanPart(
        radius: size.x * 0.3,
        position: Vector2(size.x / 2, size.y * 0.15),
        hitColor: const Color(0xFFF44336),
      ),
    ]);
  }
}

/// A white circle of the snowman, which turns [hitColor] while it collides with
/// anything except the arena's walls.
class SnowmanPart({
  required super.radius,
  required super.position,
  required final Color hitColor,
}) extends CircleHitbox {
  this : super(anchor: Anchor.center) {
    paint.color = _startColor;
    renderShape = true;
  }

  static const _startColor = Color(0xCCFFFFFF);

  @override
  void onCollisionStart(List<Vector2> intersectionPoints, ShapeHitbox other) {
    super.onCollisionStart(intersectionPoints, other);
    paint.color = other.hitboxParent is CollidableArena
        ? _startColor
        : hitColor.withValues(alpha: 0.8);
  }

  @override
  void onCollisionEnd(ShapeHitbox other) {
    super.onCollisionEnd(other);
    if (!isColliding) {
      paint.color = _startColor;
    }
  }
}

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVGs, and [RasterizerPathComponent]s its paths, with the renderer that the
/// Renderer knob picks.
class RasterizerMultipleShapesExample({
  required super.shapes,
  required super.count,
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.from,
}) extends MultipleShapesExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  PathComponent pathComponent(
    ui.Path path,
    List<ui.Paint> paintLayers,
    double sampling,
  ) => RasterizerPathComponent(
    path: path,
    paintLayers: paintLayers,
    sampling: sampling,
  );
}

/// The example with Flame: flame_svg's `SvgComponent`s draw its SVGs as
/// images, cached as [cache] sets, and Flame's [PathComponent]s its paths.
class FlameMultipleShapesExample({
  required super.shapes,
  required super.count,
  required super.status,
  final SvgCache cache = defaultSvgCache,
  super.random,
  super.from,
}) extends MultipleShapesExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;

  @override
  String get rendererText =>
      shapes == Shapes.paths ? 'Flame' : super.rendererText;

  /// Shows no renderer numbers with paths, which have no flame_svg cache.
  @override
  Iterable<String> get rendererStats =>
      shapes == Shapes.paths ? const [] : super.rendererStats;

  @override
  PathComponent pathComponent(
    ui.Path path,
    List<ui.Paint> paintLayers,
    double sampling,
  ) => PathComponent(path: path, paintLayers: paintLayers, sampling: sampling);
}
