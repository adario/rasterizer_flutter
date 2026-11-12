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
/// each of the SVG's paths on its own, so paths that overlap show through each
/// other, while a sprite fades as a single image. The paint's other fields
/// apply to the SVG as a whole, as they do to a sprite.
///
/// Fading or tinting many components costs little. Components that differ only
/// by opacity, or by a [RasterizerColorTransform] filter such as those of
/// `tint`, [ColorEffect] and [HueEffect], share a run of [RasterizerCanvas].
/// Any other color filter, blend mode or image filter starts a new run.
///
/// The component doesn't draw [paintLayers]. Inside a picture of its own, such
/// as a `Snapshot`'s or a camera post-process's, it draws the SVG with
/// `dart:ui` ([RasterizerSvg.render]).
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
  /// [size] defaults to the SVG's own ([RasterizerSvg.size]), as a
  /// [SpriteComponent]'s defaults to its sprite's. Setting another [svg] later
  /// doesn't change the size.
  this : super(size: size ?? svg?.size) {
    if (paint != null) {
      this.paint = paint;
    }
  }

  @override
  void render(Canvas canvas) => svg?.render(canvas, size, overridePaint: paint);
}
