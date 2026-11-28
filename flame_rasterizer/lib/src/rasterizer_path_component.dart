import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/src/color_transform_effects.dart';
import 'package:flame_rasterizer/src/has_rasterizer.dart';
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart';
import 'package:flame_rasterizer/src/rasterizer_svg_component.dart';
import 'package:flame_rasterizer/src/shared_scenes.dart';
import 'package:flutter/foundation.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// A Flame [PathComponent] that draws with rasterizer_gpu in a game with
/// [HasRasterizer].
///
/// It draws as a [RasterizerSvgComponent] does, as if it were an SVG of its
/// path with one `<path>` per paint layer. The first time it's drawn, it
/// imports its path with each of its paint layers: it makes a
/// [RasterizerScene] of them for the game's renderer
/// ([HasRasterizer.rasterizerGpu]). Each frame then draws that import under
/// the component's transform, with its [paint] applied over it, as a
/// [RasterizerSvgComponent] does. Its polygons and [containsPoint] are those
/// of [PathComponent].
///
/// So, unlike a [PathComponent], it applies its [paint] even when it has
/// paint layers. The paint's opacity fades each layer. The filters that
/// `tint`, [ColorEffect] and [HueEffect] set, which [RasterizerColorTransform]
/// makes, filter each layer. So tinted and faded components don't need a new
/// import, and they share imports and runs: consecutive draws that the
/// renderer batches together (see [RasterizerCanvas]). The paint's other
/// fields apply to the component as a whole, as they do to a sprite, and
/// start a new run. `hue` leaves the layers' own filters unchanged.
///
/// Fade the component with an [OpacityEffect] on the component itself, not
/// on `opacityProviderOfList()`, which fades the layers themselves and the
/// [paint] too.
///
/// Without paint layers, its [paint] does both jobs. Its color's RGB, style,
/// stroke settings, antialiasing and shader draw the path as a layer's would,
/// and its alpha and other fields apply over the result.
///
/// The GPU renderers flatten its path into polylines once, to within 1/4 of a
/// device pixel when the path's longer side is drawn [maxSize] device pixels
/// long, the largest size it's drawn at (see [RasterizerScene.fromPaths]). So
/// the path must not change.
///
/// Each time it draws, the component compares its paint layers with those of
/// its import, which costs little. When they differ, it imports the path
/// again, as for an edited SVG. It reuses the path's flattened contours, so it
/// doesn't flatten them again. When a layer has its own color filter made by
/// [RasterizerColorTransform], the component applies that filter to the
/// layer's color. While the GPU renderers can't draw a layer
/// ([RasterizerScene.canDraw]), such as one with another color filter or a
/// hairline stroke, the component draws with [Canvas.drawPath] instead. That
/// ends the run, as other canvas draws do.
///
/// Components made with the same [Path] object share an import while they
/// draw it for the same renderer, with the same [maxSize], [glow] and paint
/// layers. Without paint layers, their paints must also match in the fields
/// that draw as a layer's. The first component imports the path. The last one
/// to stop using the import frees it, when its layers change or when it or its
/// game is removed. So make all the components of one shape from one path,
/// and size them with [scale] rather than with paths of their own: they then
/// cost one import.
///
/// When drawn into any canvas other than the game's [RasterizerCanvas], such
/// as a `Snapshot`'s or a camera post process's, or outside a game with
/// [HasRasterizer], it also draws its layers with [Canvas.drawPath], with its
/// [paint] applied over them as in the game's runs. In the game's own canvas,
/// before the renderer is ready, it draws nothing, as a [RasterizerSvg] does,
/// unless a layer can't be imported.
class RasterizerPathComponent({
  required super.path,
  super.sampling,
  super.tolerance,
  super.filter,
  double? maxSize,
  RasterizerGlow? glow,
  super.position,
  super.scale,
  super.angle,
  super.anchor,
  super.children,
  super.priority,
  super.key,
  super.paint,
  super.paintLayers,
  super.isSolid,
}) extends PathComponent with ColorTransformEffects {
  /// Creates a component that draws [path].
  ///
  /// Throws [ArgumentError] if [maxSize] isn't a positive finite number.
  this {
    if (!(this.maxSize > 0) || !this.maxSize.isFinite) {
      throw ArgumentError.value(
        this.maxSize,
        'maxSize',
        'Not a positive finite number',
      );
    }
    onReleaseScenes(this, _releaseAll);
  }

  /// The largest size, in device pixels, at which it draws its path's longer
  /// side, and the size it imports the path for.
  ///
  /// It defaults to [RasterizerSvg.defaultMaxSize], the view's longer side.
  /// Pass the largest size the game draws the path at, as for
  /// [RasterizerSvg.fromBytes]: the path's longer side times the component's
  /// scale, the camera's largest zoom and the device pixel ratio.
  final double maxSize = maxSize ?? RasterizerSvg.defaultMaxSize;

  /// The neon glow around its path, which its import draws (see
  /// [RasterizerGlow]).
  ///
  /// The component's opacity and tint apply to the glow. Only the mesh
  /// renderer draws it. The atlas and canvas renderers, and
  /// [Canvas.drawPath], draw the path without it. Setting another glow
  /// imports the path again, as a change to a paint layer does.
  RasterizerGlow? glow = glow;

  // The path it was made with, whose import it shares, and that path's top
  // left. PathComponent moves [path] to the origin, so the component draws
  // the import shifted back by that top left.
  final Path _source = path;
  final Offset _topLeft = path.getBounds().topLeft;

  // The game's GPU renderer, once the component is mounted in a game with
  // HasRasterizer.
  RasterizerBackend? _gpu;

  SharedScene? _shared;

  // The fields of the paint layers of its import, or of its last failed
  // attempt to import. Without paint layers, it holds the fields of its paint
  // that draw as a layer's. Empty before it's first drawn.
  List<PaintFields> _fields = const [];

  // The glow at the time [_fields] were set.
  RasterizerGlow? _glow;

  // Imports that no component uses any more. The next update frees them,
  // after the frames that drew them have rendered.
  final List<RasterizerScene> _retired = [];

  // Copies of its paint layers, which [_drawPaths] fades or filters, and the
  // fields they were copied from. A change to any layer makes new copies.
  List<Paint> _copies = const [];
  List<PaintFields> _copied = const [];

  // The paint of the canvas layer through which a color transform filters
  // the pixels of a paint layer that has its own filter.
  static final _filterLayer = Paint();

  /// For tests: the import it draws, or null before it's drawn into a game's
  /// canvas, or while a layer can't be imported.
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
    if (!renderShape) {
      return;
    }
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
    _drawPaths(canvas);
  }

  /// Draws its path with [Canvas.drawPath] in each of its paint layers, with
  /// its [paint] applied over them.
  ///
  /// It draws as a [RasterizerSvg] draws its paths into a picture of its own.
  /// The paint's alpha fades each layer, and its [RasterizerColorTransform]
  /// filter, if any, filters each layer. Its other fields apply to a canvas
  /// layer around them all. Without paint layers, it draws with its [paint],
  /// as a [PathComponent] does.
  void _drawPaths(Canvas canvas) {
    if (!hasPaintLayers) {
      super.render(canvas);
      return;
    }
    RasterizerCanvas.drawWithPaint(canvas, paint, (opacity, transform) {
      final layers = paintLayers;
      if (opacity == 1 && transform == null) {
        for (final content in layers) {
          canvas.drawPath(path, content);
        }
        return;
      }
      final copies = _copiesOf(layers);
      for (var i = 0; i < layers.length; i++) {
        final content = layers[i];
        // A layer with its own filter keeps it. The transform's filter then
        // applies to the layer's pixels, through a canvas layer.
        final over = transform != null && content.colorFilter != null;
        final drawn = copies[i]
          ..color = content.color.withValues(alpha: content.color.a * opacity)
          ..colorFilter = over || transform == null
              ? content.colorFilter
              : transform.filter;
        if (over) {
          canvas.saveLayer(null, _filterLayer..colorFilter = transform.filter);
        }
        canvas.drawPath(path, drawn);
        if (over) {
          canvas.restore();
        }
      }
    });
  }

  /// Returns copies of [layers], made again if any layer changed since the
  /// last copy.
  List<Paint> _copiesOf(List<Paint> layers) {
    var changed = _copied.length != layers.length;
    for (var i = 0; i < layers.length && !changed; i++) {
      changed = !_copied[i].matches(layers[i]);
    }
    if (changed) {
      _copies = [for (final layer in layers) Paint.from(layer)];
      _copied = [for (final layer in layers) PaintFields(layer)];
    }
    return _copies;
  }

  /// Returns its import for its current paint layers and [glow], and imports
  /// the path again if they changed.
  ///
  /// Returns null outside a game with [HasRasterizer], or if a layer can't be
  /// imported.
  RasterizerScene? _currentScene() {
    final gpu = _gpu;
    if (gpu == null) {
      return null;
    }
    final layers = hasPaintLayers ? paintLayers : null;
    final count = layers?.length ?? 1;
    var changed = _fields.length != count || glow != _glow;
    for (var i = 0; i < count && !changed; i++) {
      final fields = _fields[i];
      changed =
          fields.layerOnly != (layers == null) ||
          !fields.matches(layers?[i] ?? paint);
    }
    if (changed) {
      // Set first, so that it doesn't retry a failed import every frame.
      _fields = layers == null
          ? [PaintFields(paint, layerOnly: true)]
          : [for (final layer in layers) PaintFields(layer)];
      _glow = glow;
      _release();
      final paints = layers == null
          ? [layerOf(paint)]
          : [for (final layer in layers) _filtered(layer)];
      if (paints.every(RasterizerScene.canDraw)) {
        _shared = acquireScene(
          _source,
          gpu,
          maxSize,
          glow,
          paints,
          () => RasterizerScene.fromPaths(
            [for (final p in paints) (path: _source, paint: p)],
            gpu: gpu,
            maxSize: maxSize,
            glow: glow,
          ),
        );
      }
    }
    return _shared?.scene;
  }

  /// Returns [layer], or a copy of it if its color filter is one that
  /// [RasterizerColorTransform] made.
  ///
  /// The copy has no color filter, and has its color filtered instead.
  static Paint _filtered(Paint layer) {
    final filter = layer.colorFilter;
    final transform = filter == null
        ? null
        : RasterizerColorTransform.of(filter);
    if (transform == null) {
      return layer;
    }
    return Paint.from(layer)
      ..colorFilter = null
      ..color = transform.apply(layer.color);
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
    final scene = releaseScene(_source, shared);
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
  /// imports its path again.
  void _releaseAll() {
    _release(now: true);
    _freeRetired();
    _fields = const [];
  }

  @override
  void onRemove() {
    _releaseAll();
    _gpu = null;
    super.onRemove();
  }
}
