import 'dart:ui';

import 'package:flame/components.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

// The imports that the package's components share, by the path or polygons
// they draw. Shared by the package's files, and not exported.

/// How each component that imports scenes releases them all.
final _releases = Expando<void Function()>('scene releases');

/// Registers how [component] releases all its imports, for [releaseScenes].
void onReleaseScenes(Component component, void Function() release) =>
    _releases[component] = release;

/// Releases the imports of the components in [game]'s tree, as the game is
/// removed.
///
/// Flame doesn't remove the game's components then.
void releaseScenes(Component game) {
  for (final component in game.descendants()) {
    _releases[component]?.call();
  }
}

/// The imports of each path or polygons, shared by the components made with
/// it.
final _scenes = Expando<List<SharedScene>>('shared scenes');

/// Returns the import of [source], a path or polygons, with [paints], [glow]
/// and [separate], for [gpu] and [maxSize]: one that another component made,
/// or else a new one that [import] makes.
SharedScene acquireScene(
  Object source,
  RasterizerBackend gpu,
  double maxSize,
  RasterizerGlow? glow,
  List<Paint> paints,
  RasterizerScene Function() import, {
  bool separate = false,
}) {
  final scenes = _scenes[source] ??= [];
  // The backend a new import gets: the canvas renderer where the GPU
  // renderer isn't supported, or with RasterizerGpu.forceCanvas.
  final backend = RasterizerGpu.of(gpu).backend;
  for (final shared in scenes) {
    if (shared.matches(gpu, maxSize, backend, glow, separate, paints)) {
      shared.users++;
      return shared;
    }
  }
  final shared = SharedScene(
    gpu,
    maxSize,
    glow,
    separate,
    [for (final p in paints) PaintFields(p)],
    import(),
  );
  scenes.add(shared);
  return shared;
}

/// Stops a component's use of [shared], an import of [source]. Returns its
/// scene if no other component uses it, for the caller to free.
RasterizerScene? releaseScene(Object source, SharedScene shared) {
  if (--shared.users > 0) {
    return null;
  }
  _scenes[source]!.remove(shared);
  return shared.scene;
}

/// A path's or polygons' import for a renderer, a maximum size, a glow,
/// whether it's separate and paints, which [users] components draw.
class SharedScene(
  /// The game's GPU renderer that it's imported for.
  final RasterizerBackend gpu,

  /// The size it's imported for.
  final double maxSize,

  /// The glow it's imported with.
  final RasterizerGlow? glow,

  /// Whether polygons are imported separate.
  final bool separate,

  /// The fields of the paints it's imported with.
  final List<PaintFields> fields,

  /// The import.
  final RasterizerScene scene,
) {
  /// Keeps [scene], which one component draws.
  this;

  /// How many components draw it.
  int users = 1;

  /// Returns whether it's the import for [gpu], [maxSize], [glow],
  /// [separate] and [paints], now that [gpu]'s imports are for [backend].
  bool matches(
    RasterizerBackend gpu,
    double maxSize,
    RasterizerBackend backend,
    RasterizerGlow? glow,
    bool separate,
    List<Paint> paints,
  ) {
    if (gpu != this.gpu ||
        maxSize != this.maxSize ||
        backend != scene.backend ||
        glow != this.glow ||
        separate != this.separate ||
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

/// The fields of a paint that a component imports its path or polygons with,
/// or that decide whether it can import them ([RasterizerScene.canDraw]), as
/// they were then.
///
/// With [layerOnly], [matches] compares only the fields that a component's
/// paint, without paint layers, draws as a layer's, except its color's alpha.
class PaintFields(
  Paint paint, {

  /// Whether [matches] compares only the fields that draw as a layer's.
  final bool layerOnly = false,
}) {
  /// Keeps [paint]'s fields.
  this;

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

  /// Returns whether [paint]'s fields are these.
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

/// Returns the layer that [paint] draws as, without paint layers: its fields
/// except those that apply over the import, with its color opaque.
Paint layerOf(Paint paint) => Paint.from(paint)
  ..color = paint.color.withValues(alpha: 1)
  ..blendMode = BlendMode.srcOver
  ..colorFilter = null
  ..imageFilter = null
  ..maskFilter = null
  ..invertColors = false;
