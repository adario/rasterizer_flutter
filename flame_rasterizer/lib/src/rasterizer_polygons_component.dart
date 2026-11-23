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

/// A [PositionComponent] that draws [RasterizerPolygons] with rasterizer_gpu,
/// in a game with [HasRasterizer], as a [RasterizerPathComponent] draws a
/// path without paint layers.
///
/// It's for shapes that a game makes often, such as every frame: the GPU
/// renderers take the polygons' corners as they are, without flattening a
/// path, and the component makes no polygons for hit tests, as a Flame
/// `PathComponent` does. Its size is the polygons' bounds, which start at its
/// origin, and it contains a point within those bounds.
///
/// Its [paint]'s color's RGB, style and strokes draw the polygons, with
/// non-zero fills. Its alpha, and its other fields, apply over them, as for a
/// [RasterizerPathComponent] without paint layers. So [OpacityEffect],
/// [ColorEffect], [HueEffect] and `tint` cost no new import.
///
/// With [separate], the mesh renderer fills each polygon on its own, which is
/// much faster for many polygons, but overlaps show through an opacity: see
/// [RasterizerScene.fromPolygons].
///
/// Components made with the same [polygons] share an import, as
/// [RasterizerPathComponent]s made with the same path do. Into any canvas but
/// the game's [RasterizerCanvas], or outside a game with [HasRasterizer], it
/// draws [RasterizerPolygons.path] with [Canvas.drawPath].
class RasterizerPolygonsComponent({
  /// The polygons it draws, which must not change.
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
  /// longer side, as [RasterizerPathComponent.maxSize].
  final double maxSize = maxSize ?? RasterizerSvg.defaultMaxSize;

  /// The neon glow around the polygons, as [RasterizerPathComponent.glow].
  RasterizerGlow? glow = glow;

  // The polygons' top left, which the import is drawn moved back by.
  late final Offset _topLeft = polygons.bounds.topLeft;

  // The game's GPU renderer, once the component is mounted in a game with
  // HasRasterizer.
  RasterizerBackend? _gpu;

  SharedScene? _shared;

  // The fields of the paint that its import is for, or that couldn't be
  // imported, and the glow then. Null before it's first drawn.
  PaintFields? _fields;
  RasterizerGlow? _glow;

  // Imports that no component uses any more. The next update frees them,
  // once the frames that drew them have rendered.
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

  /// Returns its import for its paint and [glow] as they are now. It imports
  /// the polygons again if they changed.
  ///
  /// Null outside a game with [HasRasterizer], or if its paint can't be
  /// imported.
  RasterizerScene? _currentScene() {
    final gpu = _gpu;
    if (gpu == null) {
      return null;
    }
    final fields = _fields;
    if (fields == null || !fields.matches(paint) || glow != _glow) {
      // Kept first, so that an import that can't be made isn't tried again
      // each frame.
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
  /// It frees the import [now], or else at its next update, once the frames
  /// that drew it have rendered.
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

  /// Stops using its import, and frees now what no other component uses.
  ///
  /// [onRemove] and `releaseScenes` call it outside a frame, as the component
  /// or its game is removed. Drawn again, the component imports its polygons
  /// again.
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
