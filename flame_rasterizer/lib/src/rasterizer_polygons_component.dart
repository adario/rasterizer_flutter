import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/src/color_transform_effects.dart';
import 'package:flame_rasterizer/src/has_rasterizer.dart';
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/rasterizer_path_component.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart';
import 'package:flame_rasterizer/src/shared_scenes.dart';
import 'package:flutter/foundation.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// A [PositionComponent] that draws [RasterizerPolygons] with rasterizer_gpu
/// in a game with [HasRasterizer].
///
/// Use it for shapes that a game rebuilds often, such as every frame. The GPU
/// renderers draw polygons without the flattening step that paths need, and
/// the component doesn't make polygons for hit tests as a Flame
/// `PathComponent` does. Its size is the size of the polygons' bounds, and it
/// draws the polygons shifted so that the bounds start at its origin.
///
/// The first time it's drawn, it imports the polygons: it makes a
/// [RasterizerScene] of them for the game's renderer. It draws them with its
/// [paint]'s style, stroke settings and opaque color, and fills them with the
/// non-zero rule. Then it applies the paint's alpha and other fields to the
/// result, as a [RasterizerPathComponent] without paint layers does. So
/// [OpacityEffect], [ColorEffect], [HueEffect] and `tint` don't make it
/// import the polygons again.
///
/// With [separate], the mesh renderer fills each polygon on its own. That's
/// much faster for many polygons, but overlapping polygons show through each
/// other when faded (see [RasterizerScene.fromPolygons]).
///
/// Components made with the same [polygons] share one import, as
/// [RasterizerPathComponent]s made with the same path do. When drawn into a
/// canvas other than the game's [RasterizerCanvas], or outside a game with
/// [HasRasterizer], it draws [RasterizerPolygons.path] with
/// [Canvas.drawPath]. In the game's own canvas, before the renderer is ready,
/// it draws nothing, unless it can't import its paint.
class RasterizerPolygonsComponent({
  /// The polygons it draws. They must not change.
  required final RasterizerPolygons polygons,
  double? maxSize,
  RasterizerGlow? glow,

  /// Whether the mesh renderer fills each polygon on its own: see
  /// [RasterizerScene.fromPolygons].
  final bool separate = false,
  Paint? paint,
  super.position,
  super.scale,
  super.angle,
  super.anchor,
  super.children,
  super.priority,
  super.key,
}) extends PositionComponent with HasPaint, ColorTransformEffects {
  /// Creates a component that draws [polygons] with [paint].
  ///
  /// Throws [ArgumentError] if [maxSize] isn't a positive finite number.
  this
    : super(
        size: Vector2(polygons.bounds.width, polygons.bounds.height),
      ) {
    if (!(this.maxSize > 0) || !this.maxSize.isFinite) {
      throw ArgumentError.value(
        this.maxSize,
        'maxSize',
        'Not a positive finite number',
      );
    }
    if (paint != null) {
      this.paint = paint;
    }
    onReleaseScenes(this, _releaseAll);
  }

  /// The largest size, in device pixels, at which it draws the polygons'
  /// longer side, as for [RasterizerPathComponent.maxSize].
  final double maxSize = maxSize ?? RasterizerSvg.defaultMaxSize;

  /// The neon glow around the polygons, as for
  /// [RasterizerPathComponent.glow].
  RasterizerGlow? glow = glow;

  // The top left of the polygons' bounds. The component draws its import
  // shifted back by it, so that the bounds start at its origin.
  late final Offset _topLeft = polygons.bounds.topLeft;

  // The game's GPU renderer, once the component is mounted in a game with
  // HasRasterizer.
  RasterizerBackend? _gpu;

  SharedScene? _shared;

  // The paint fields and glow of its last import, or of its last failed
  // attempt to import. Null before it's first drawn.
  PaintFields? _fields;
  RasterizerGlow? _glow;

  // Imports that no component uses any more. The next update frees them,
  // after the frames that drew them have rendered.
  final List<RasterizerScene> _retired = [];

  /// For tests: the import it draws, or null before it's drawn into a game's
  /// canvas, or while its paint can't be imported.
  @visibleForTesting
  RasterizerScene? get debugScene => _shared?.scene;

  @override
  void onMount() {
    super.onMount();
    final game = findGame();
    _gpu = game is HasRasterizer ? game.rasterizerGpu : null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _freeRetired();
  }

  @override
  void render(Canvas canvas) {
    if (canvas is RasterizerCanvas || identical(canvas, unreadyCanvas)) {
      final scene = _currentScene();
      if (scene != null) {
        if (canvas is RasterizerCanvas) {
          canvas.drawScene(
            scene,
            1,
            0,
            0,
            1,
            -_topLeft.dx,
            -_topLeft.dy,
            paint: paint,
          );
        }
        return;
      }
    }
    canvas
      ..save()
      ..translate(-_topLeft.dx, -_topLeft.dy)
      ..drawPath(polygons.path, paint)
      ..restore();
  }

  /// Returns its import for its current paint and [glow], and imports the
  /// polygons again if either changed.
  ///
  /// Returns null outside a game with [HasRasterizer], or if it can't import
  /// its paint.
  RasterizerScene? _currentScene() {
    final gpu = _gpu;
    if (gpu == null) {
      return null;
    }
    final fields = _fields;
    if (fields == null || !fields.matches(paint) || glow != _glow) {
      // Set first, so that it doesn't retry a failed import every frame.
      _fields = PaintFields(paint, layerOnly: true);
      _glow = glow;
      _release();
      final layer = layerOf(paint);
      if (RasterizerScene.canDraw(layer)) {
        _shared = acquireScene(
          polygons,
          gpu,
          maxSize,
          glow,
          [layer],
          () => RasterizerScene.fromPolygons(
            [(polygons: polygons, paint: layer)],
            gpu: gpu,
            maxSize: maxSize,
            glow: glow,
            separate: separate,
          ),
          separate: separate,
        );
      }
    }
    return _shared?.scene;
  }

  /// Stops using its import, and frees it if no other component uses it.
  ///
  /// It frees the import right away if [now], or else at its next update,
  /// after the frames that drew it have rendered.
  void _release({bool now = false}) {
    final shared = _shared;
    if (shared == null) {
      return;
    }
    _shared = null;
    final scene = releaseScene(polygons, shared);
    if (scene == null) {
      return;
    }
    if (now) {
      scene.dispose();
    } else {
      _retired.add(scene);
    }
  }

  void _freeRetired() {
    for (final scene in _retired) {
      scene.dispose();
    }
    _retired.clear();
  }

  /// Stops using its import, and immediately frees the imports that no other
  /// component uses.
  ///
  /// [onRemove] and `releaseScenes` call it outside a frame, when the
  /// component or its game is removed. If the component is drawn again, it
  /// imports its polygons again.
  void _releaseAll() {
    _release(now: true);
    _freeRetired();
    _fields = null;
  }

  @override
  void onRemove() {
    _releaseAll();
    _gpu = null;
    super.onRemove();
  }
}
