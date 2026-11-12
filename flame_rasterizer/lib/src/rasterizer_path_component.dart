import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/src/color_transform_effects.dart';
import 'package:flame_rasterizer/src/has_rasterizer.dart';
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart';
import 'package:flame_rasterizer/src/rasterizer_svg_component.dart';
import 'package:flutter/foundation.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// A Flame [PathComponent] drawn with rasterizer_gpu, in a game with
/// [HasRasterizer].
///
/// It draws into the game's runs as [RasterizerSvgComponent]s do, like an SVG
/// of its path with one `<path>` per paint layer. The first time it's drawn,
/// it imports its path, with each of its paint layers, for the game's
/// renderer ([HasRasterizer.rasterizerGpu]). Each frame then draws that
/// import under its transform, with its [paint] over it, as a
/// [RasterizerSvgComponent] does. Its polygons and [containsPoint] are
/// [PathComponent]'s.
///
/// So, unlike a [PathComponent], it draws its [paint] when it has paint
/// layers. The paint's opacity fades each layer. The filters of `tint`,
/// [ColorEffect] and [HueEffect] filter each layer, as
/// [RasterizerColorTransform] makes them. So tinted and faded components cost
/// no new import, and share runs and imports. The paint's other fields apply
/// to the component as a whole, as to a sprite, and start a new run. `hue`
/// leaves the layers' own filters alone. Fade the component with an
/// [OpacityEffect] on it, not on `opacityProviderOfList()`, which fades the
/// layers themselves, and the [paint] too.
///
/// Without paint layers, its [paint] does both jobs. Its color's RGB, style,
/// strokes, antialiasing and shader draw as a layer's would. Its alpha and
/// other fields apply over that layer.
///
/// The GPU renderers flatten its path once into polylines, within 1/4 of a
/// device pixel when its longer side is drawn [maxSize] device pixels long,
/// the most it's drawn at (see [RasterizerScene.fromPaths]). So the path
/// must not change. Each time the component is drawn, it compares its paint
/// layers with those of its import, which costs little. When they differ, it
/// imports the path again, as for an edited SVG, from the path's contours,
/// which aren't flattened again. A layer's own color filter made by
/// [RasterizerColorTransform] is drawn into the layer's color. While the GPU
/// renderers can't draw a layer ([RasterizerScene.canDraw]), such as one
/// with another color filter, or a hairline stroke, the component draws with
/// [Canvas.drawPath]. That ends the run, as other canvas draws do.
///
/// Components made with the same [Path] object share an import while they
/// draw it for the same renderer, with the same [maxSize], [glow] and paint
/// layers. Without paint layers, their paints must also match in the fields
/// that draw as a layer's. The first component imports the path, and the
/// last one to stop using the import frees it: when its layers change, or
/// when it or its game is removed. So make the components of one shape from
/// one path, and size them with [scale] rather than with paths of their own.
/// They then cost one import.
///
/// Into any canvas but the game's [RasterizerCanvas], such as a `Snapshot`'s
/// or a camera post process's, or outside a game with [HasRasterizer], it
/// draws its layers with [Canvas.drawPath] too, with its [paint] over them as
/// in the game's runs. Into the game's own canvas, before the renderer is
/// ready, it draws nothing, as a [RasterizerSvg] does, unless a layer can't
/// be imported.
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
  }

  /// The largest size, in device pixels, at which its path's longer side is
  /// drawn, which its import is made for.
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
  /// renderer draws it: the atlas and canvas renderers, and
  /// [Canvas.drawPath], draw the path without it. Setting another glow
  /// imports the path again, as a change to a paint layer does.
  RasterizerGlow? glow = glow;

  // The path it was made with, whose import it shares, and that path's top
  // left. PathComponent moves [path] to the origin, so the import is drawn
  // moved back by that top left.
  final Path _source = path;
  final Offset _topLeft = path.getBounds().topLeft;

  // The imports of each path, shared by the components made with it.
  static final _scenes = Expando<List<_SharedScene>>('shared scenes');

  // The game's GPU renderer, once the component is mounted in a game with
  // HasRasterizer.
  RasterizerBackend? _gpu;

  _SharedScene? _shared;

  // The fields of the paint layers that its import is for, or that couldn't
  // be imported. Without paint layers, the fields of its paint that draw as a
  // layer's. Empty before it's first drawn.
  List<_PaintFields> _fields = const [];

  // The glow when [_fields] were kept.
  RasterizerGlow? _glow;

  // Imports that no component uses any more. The next update frees them,
  // once the frames that drew them have rendered.
  final List<RasterizerScene> _retired = [];

  // Copies of its paint layers, which [_drawPaths] fades or filters, and the
  // fields they were copied from. A layer's change makes new copies.
  List<Paint> _copies = const [];
  List<_PaintFields> _copied = const [];

  // The canvas layer through which a color transform filters the pixels of a
  // paint layer that has its own filter.
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

  /// Draws its path with [Canvas.drawPath], with each of its paint layers and
  /// its [paint] over them.
  ///
  /// It draws as a [RasterizerSvg] draws its paths into a picture of its own.
  /// The paint's alpha fades each layer, and its [RasterizerColorTransform]
  /// filters each layer. Its other fields apply to a canvas layer around them
  /// all. Without paint layers, it draws with its [paint], as a
  /// [PathComponent] does.
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

  /// Copies of [layers], made again if any layer changed since the last copy.
  List<Paint> _copiesOf(List<Paint> layers) {
    var changed = _copied.length != layers.length;
    for (var i = 0; i < layers.length && !changed; i++) {
      changed = !_copied[i].matches(layers[i]);
    }
    if (changed) {
      _copies = [for (final layer in layers) Paint.from(layer)];
      _copied = [for (final layer in layers) _PaintFields(layer)];
    }
    return _copies;
  }

  /// Its import for its paint layers and [glow] as they are now. It imports
  /// the path again if they changed.
  ///
  /// Null outside a game with [HasRasterizer], or if a layer can't be
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
      // Kept first, so that an import that can't be made isn't tried again
      // each frame.
      _fields = layers == null
          ? [_PaintFields(paint, layerOnly: true)]
          : [for (final layer in layers) _PaintFields(layer)];
      _glow = glow;
      _release();
      final paints = layers == null
          ? [_layerOf(paint)]
          : [for (final layer in layers) _filtered(layer)];
      if (paints.every(RasterizerScene.canDraw)) {
        _shared = _acquire(gpu, paints);
      }
    }
    return _shared?.scene;
  }

  /// The layer that [paint] draws as, without paint layers: its fields except
  /// those that apply over the import, with its color opaque.
  static Paint _layerOf(Paint paint) => Paint.from(paint)
    ..color = paint.color.withValues(alpha: 1)
    ..blendMode = BlendMode.srcOver
    ..colorFilter = null
    ..imageFilter = null
    ..maskFilter = null
    ..invertColors = false;

  /// [layer], or, if its color filter is one that [RasterizerColorTransform]
  /// made, a copy without the filter whose color is filtered instead.
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

  /// The import of its path with [paints] and [glow], for [gpu] and
  /// [maxSize]: one that another component made, or a new one.
  _SharedScene _acquire(RasterizerBackend gpu, List<Paint> paints) {
    final scenes = _scenes[_source] ??= [];
    // The backend a new import gets: the canvas renderer until a GPU
    // renderer's self-test passes.
    final backend = RasterizerGpu.of(gpu).backend;
    for (final shared in scenes) {
      if (shared.matches(gpu, maxSize, backend, glow, paints)) {
        shared.users++;
        return shared;
      }
    }
    final shared = _SharedScene(
      gpu,
      maxSize,
      glow,
      [for (final p in paints) _PaintFields(p)],
      RasterizerScene.fromPaths(
        [for (final p in paints) (_source, p)],
        gpu: gpu,
        maxSize: maxSize,
        glow: glow,
      ),
    );
    scenes.add(shared);
    return shared;
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
    if (--shared.users > 0) {
      return;
    }
    _scenes[_source]!.remove(shared);
    if (now) {
      shared.scene.dispose();
    } else {
      _retired.add(shared.scene);
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
  /// It's called outside a frame, as the component or its game is removed.
  /// Drawn again, the component imports its path again.
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

/// Releases the imports of the [RasterizerPathComponent]s in [game]'s tree,
/// as the game is removed.
///
/// Flame doesn't remove the game's components then.
void releasePathScenes(Component game) {
  for (final component
      in game.descendants().whereType<RasterizerPathComponent>()) {
    component._releaseAll();
  }
}

/// A path's import for a renderer, a maximum size, a glow and paints, which
/// [users] components draw.
class _SharedScene(
  final RasterizerBackend gpu,
  final double maxSize,
  final RasterizerGlow? glow,
  final List<_PaintFields> fields,
  final RasterizerScene scene,
) {
  int users = 1;

  /// Whether it's the import for [gpu], [maxSize], [glow] and [paints], now
  /// that [gpu]'s imports are for [backend].
  bool matches(
    RasterizerBackend gpu,
    double maxSize,
    RasterizerBackend backend,
    RasterizerGlow? glow,
    List<Paint> paints,
  ) {
    if (gpu != this.gpu ||
        maxSize != this.maxSize ||
        backend != scene.backend ||
        glow != this.glow ||
        paints.length != fields.length) {
      return false;
    }
    for (var i = 0; i < paints.length; i++) {
      if (!fields[i].matches(paints[i])) {
        return false;
      }
    }
    return true;
  }
}

/// The fields of a paint that a path's import is made from, or that decide
/// whether it can be made ([RasterizerScene.canDraw]), as they were then.
///
/// With [layerOnly], [matches] compares only the fields that a
/// [RasterizerPathComponent]'s paint, without paint layers, draws as a
/// layer's, except its color's alpha.
class _PaintFields(Paint paint, {final bool layerOnly = false}) {
  final Color _color = paint.color;
  final PaintingStyle _style = paint.style;
  final double _strokeWidth = paint.strokeWidth;
  final StrokeCap _strokeCap = paint.strokeCap;
  final StrokeJoin _strokeJoin = paint.strokeJoin;

  // The getter's value, which isn't the real limit in Flutter 3.47.
  // rasterizer_gpu corrects it when it imports the path. Comparing two
  // getter values still finds a change.
  final double _strokeMiterLimit = paint.strokeMiterLimit;
  final BlendMode _blendMode = paint.blendMode;
  final bool _isAntiAlias = paint.isAntiAlias;
  final bool _invertColors = paint.invertColors;
  final Shader? _shader = paint.shader;
  final ColorFilter? _colorFilter = paint.colorFilter;
  final MaskFilter? _maskFilter = paint.maskFilter;
  final ImageFilter? _imageFilter = paint.imageFilter;

  /// Whether [paint]'s fields are these.
  bool matches(Paint paint) {
    final color = paint.color;
    if (!(layerOnly
            ? color.r == _color.r &&
                  color.g == _color.g &&
                  color.b == _color.b &&
                  color.colorSpace == _color.colorSpace
            : color == _color) ||
        paint.style != _style ||
        paint.strokeWidth != _strokeWidth ||
        paint.strokeCap != _strokeCap ||
        paint.strokeJoin != _strokeJoin ||
        paint.strokeMiterLimit != _strokeMiterLimit ||
        paint.isAntiAlias != _isAntiAlias ||
        paint.shader != _shader) {
      return false;
    }
    return layerOnly ||
        paint.blendMode == _blendMode &&
            paint.invertColors == _invertColors &&
            paint.colorFilter == _colorFilter &&
            paint.maskFilter == _maskFilter &&
            paint.imageFilter == _imageFilter;
  }
}
