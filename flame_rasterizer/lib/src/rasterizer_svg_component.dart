import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/src/color_transform_effects.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// A [PositionComponent] that draws a [RasterizerSvg] scaled to its size, as a
/// [SpriteComponent] draws its sprite.
///
/// The component draws the SVG with its [paint], so effects such as
/// [OpacityEffect], [ColorEffect] and [HueEffect] work on it. Opacity fades
/// each of the SVG's paths separately, so overlapping paths show through each
/// other, while a sprite fades as a single image. The paint's other fields
/// apply to the SVG as a whole, as they do to a sprite.
///
/// Fading or tinting many components costs little. Components that differ only
/// in opacity, or in a [RasterizerColorTransform] filter such as the ones that
/// `tint`, [ColorEffect] and [HueEffect] set, can share a run: consecutive
/// draws that the renderer batches together (see [RasterizerCanvas]). Any
/// other color filter, blend mode or image filter starts a new run.
///
/// The component ignores [paintLayers]. When it's drawn into a picture of its
/// own, such as a `Snapshot`'s or a camera post-process's, it draws the SVG
/// with `dart:ui` ([RasterizerSvg.render]).
class RasterizerSvgComponent({
  /// The SVG to draw, or null to draw nothing.
  var RasterizerSvg? svg,
  Paint? paint,
  super.position,
  Vector2? size,
  super.scale,
  super.angle,
  super.nativeAngle,
  super.anchor,
  super.children,
  super.priority,
  super.key,
}) extends PositionComponent with HasPaint, ColorTransformEffects {
  /// Creates a component that draws [svg] with [paint].
  ///
  /// [size] defaults to the SVG's size ([RasterizerSvg.size]), as a
  /// [SpriteComponent]'s size defaults to its sprite's. Setting another [svg]
  /// later doesn't change the size.
  this : super(size: size ?? svg?.size) {
    if (paint != null) {
      this.paint = paint;
    }
  }

  @override
  void render(Canvas canvas) => svg?.render(canvas, size, overridePaint: paint);
}
