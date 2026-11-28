import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart' show hueRotationMatrix;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Makes Flame's `tint` and `hue` set color filters that apply to each path
/// of a component's vector content.
///
/// It's for components that draw their content with their [paint], as
/// [RasterizerCanvas.drawScene] does. [RasterizerColorTransform] makes the
/// filters and can read them back, so tinted components can still share a
/// run of [RasterizerCanvas]. [RasterizerCanvas] can't read any other filter
/// on [paint], so such a filter starts a new run.
mixin ColorTransformEffects on HasPaint {
  /// Tints [paint] as Flame does, with a filter from
  /// [RasterizerColorTransform] when it can make one.
  @override
  void tint(Color color, {Object? paintId}) {
    final transform = RasterizerColorTransform.mode(color, BlendMode.srcATop);
    if (transform == null) {
      return super.tint(color, paintId: paintId);
    }
    _setFilter(getPaint(paintId), transform.filter);
    onChanged();
  }

  /// Rotates the hue of [paint] as Flame does, with a filter from
  /// [RasterizerColorTransform].
  ///
  /// Flame also sets the filter on each paint layer. This mixin leaves the
  /// layers' own filters unchanged, because the filter of [paint] already
  /// applies over them.
  @override
  set hue(double value) {
    if (value == hue) {
      return;
    }
    final layers = hasPaintLayers ? paintLayers : const <Paint>[];
    final filters = [for (final layer in layers) layer.colorFilter];
    super.hue = value;
    for (final (i, layer) in layers.indexed) {
      _setFilter(layer, filters[i]);
    }
    if (value != 0) {
      final transform = RasterizerColorTransform.matrix(
        hueRotationMatrix(value),
      );
      if (transform != null) {
        _setFilter(paint, transform.filter);
      }
    }
    // Flame's setter calls onChanged before the filters above are set.
    onChanged();
  }

  /// Sets [filter] on [paint], even if the paint already has an equal one.
  ///
  /// On the web, CanvasKit's paint keeps its current filter when the new one
  /// is equal, but [RasterizerColorTransform.of] only reads back the filter
  /// object it made.
  static void _setFilter(Paint paint, ColorFilter? filter) => paint
    ..colorFilter = null
    ..colorFilter = filter;
}
