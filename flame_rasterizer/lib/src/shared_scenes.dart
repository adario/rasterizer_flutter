import 'dart:ui';

import 'package:flame/components.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

// The imports that the package's components share, kept by the path or
// polygons they draw. The package's files use these, and the package doesn't
// export them.

/// The function that releases all of a component's imports, for each
/// component that has any.
final _releases = Expando<void Function()>('scene releases');

/// Registers [release] as the function that releases all of [component]'s
/// imports, for [releaseScenes].
void onReleaseScenes(Component component, void Function() release) =>
    _releases[component] = release;

/// Releases the imports of all the components in [game]'s tree, when the
/// game is removed.
///
/// Flame doesn't remove the game's components then, so they can't release
/// their imports themselves.
void releaseScenes(Component game) {
  for (final component in game.descendants()) {
    _releases[component]?.call();
  }
}

/// The imports of each path or polygons, which the components made with it
/// share.
final _scenes = Expando<List<SharedScene>>('shared scenes');

/// Returns an import of [source], a path or polygons, with [paints], [glow]
/// and [separate], for [gpu] and [maxSize].
///
/// It returns an import that another component made, if one matches, or else
/// a new one that [import] makes.
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
  // The backend that a new import gets: the canvas renderer where the GPU
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

/// Stops a component from using [shared], an import of [source].
///
/// Returns the import's scene if no other component uses it, so that the
/// caller can free it.
RasterizerScene? releaseScene(Object source, SharedScene shared) {
  if (--shared.users > 0) {
    return null;
  }
  _scenes[source]!.remove(shared);
  return shared.scene;
}

/// An import of a path or polygons, which [users] components draw.
///
/// Components share it only if they draw it with the same renderer, maximum
/// size, glow, [separate] setting and paints.
class SharedScene(
  /// The game's GPU renderer that the import is for.
  final RasterizerBackend gpu,

  /// The maximum size that the import is for.
  final double maxSize,

  /// The glow of the import.
  final RasterizerGlow? glow,

  /// Whether the import fills each polygon on its own.
  final bool separate,

  /// The fields of the paints of the import.
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

/// A copy of the paint fields that a component imported its path or
/// polygons with.
///
/// It also copies the fields that decide whether the component can import
/// them at all ([RasterizerScene.canDraw]).
///
/// With [layerOnly], [matches] compares only the fields that a component
/// without paint layers draws its layer with, and ignores the color's alpha.
class PaintFields(
  Paint paint, {

  /// Whether [matches] compares only the fields that a layer draws with.
  final bool layerOnly = false,
}) {
  /// Copies [paint]'s fields.
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

  /// Returns whether [paint]'s fields match these.
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

/// Returns the paint that a component without paint layers draws its layer
/// with.
///
/// It's [paint] with an opaque color, and without the fields that the
/// component applies to the layer afterwards.
Paint layerOf(Paint paint) => Paint.from(paint)
  ..color = paint.color.withValues(alpha: 1)
  ..blendMode = BlendMode.srcOver
  ..colorFilter = null
  ..imageFilter = null
  ..maskFilter = null
  ..invertColors = false;
