import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart' show hueRotationMatrix;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Makes Flame's `tint` and `hue` set filters that apply to each path of a
/// component's vector content.
///
/// For components that draw their content with their [paint], as
/// [RasterizerCanvas.drawScene] does. [RasterizerColorTransform] makes the
/// filters, and can read them back, so tinted components still share a run.
/// [RasterizerCanvas] can't read any other filter on [paint], which starts a
/// new run.
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
  /// Flame also sets the filter on each paint layer. Here the layers keep
  /// their own filters, as the filter of [paint] already applies over them.
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
    // Flame's setter called it before the filters above were set.
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
