import 'dart:ui' as ui;

import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

import 'svg_paths.dart';

// Converts vector_graphics_compiler's types to dart:ui's, with an opacity
// multiplied into the paints' colors.
//
// Based on the file of the same name that this package's author wrote for
// flame_svg, along with SvgPaths. Flame didn't merge it.

/// [color] as a dart:ui color, with [opacity] multiplied into its alpha.
ui.Color _color(Color color, double opacity) {
  final c = ui.Color(color.value);
  return opacity == 1 ? c : c.withValues(alpha: c.a * opacity);
}

/// Converts vector_graphics_compiler's blend modes to dart:ui's.
extension BlendModeConverter on BlendMode {
  ui.BlendMode toUiBlendMode() => switch (this) {
    BlendMode.clear => ui.BlendMode.clear,
    BlendMode.color => ui.BlendMode.color,
    BlendMode.colorBurn => ui.BlendMode.colorBurn,
    BlendMode.colorDodge => ui.BlendMode.colorDodge,
    BlendMode.darken => ui.BlendMode.darken,
    BlendMode.difference => ui.BlendMode.difference,
    BlendMode.dst => ui.BlendMode.dst,
    BlendMode.dstATop => ui.BlendMode.dstATop,
    BlendMode.dstIn => ui.BlendMode.dstIn,
    BlendMode.dstOut => ui.BlendMode.dstOut,
    BlendMode.dstOver => ui.BlendMode.dstOver,
    BlendMode.exclusion => ui.BlendMode.exclusion,
    BlendMode.hardLight => ui.BlendMode.hardLight,
    BlendMode.hue => ui.BlendMode.hue,
    BlendMode.lighten => ui.BlendMode.lighten,
    BlendMode.luminosity => ui.BlendMode.luminosity,
    BlendMode.modulate => ui.BlendMode.modulate,
    BlendMode.multiply => ui.BlendMode.multiply,
    BlendMode.overlay => ui.BlendMode.overlay,
    BlendMode.plus => ui.BlendMode.plus,
    BlendMode.saturation => ui.BlendMode.saturation,
    BlendMode.screen => ui.BlendMode.screen,
    BlendMode.softLight => ui.BlendMode.softLight,
    BlendMode.src => ui.BlendMode.src,
    BlendMode.srcATop => ui.BlendMode.srcATop,
    BlendMode.srcIn => ui.BlendMode.srcIn,
    BlendMode.srcOut => ui.BlendMode.srcOut,
    BlendMode.srcOver => ui.BlendMode.srcOver,
    BlendMode.xor => ui.BlendMode.xor,
  };
}

/// Converts vector_graphics_compiler's stroke caps to dart:ui's.
extension StrokeCapConverter on StrokeCap {
  ui.StrokeCap toUiStrokeCap() => switch (this) {
    StrokeCap.butt => ui.StrokeCap.butt,
    StrokeCap.round => ui.StrokeCap.round,
    StrokeCap.square => ui.StrokeCap.square,
  };
}

/// Converts vector_graphics_compiler's stroke joins to dart:ui's.
extension StrokeJoinConverter on StrokeJoin {
  ui.StrokeJoin toUiStrokeJoin() => switch (this) {
    StrokeJoin.miter => ui.StrokeJoin.miter,
    StrokeJoin.round => ui.StrokeJoin.round,
    StrokeJoin.bevel => ui.StrokeJoin.bevel,
  };
}

/// Converts vector_graphics_compiler's tile modes to dart:ui's.
extension TileModeConverter on TileMode {
  ui.TileMode toUiTileMode() => switch (this) {
    TileMode.clamp => ui.TileMode.clamp,
    TileMode.repeated => ui.TileMode.repeated,
    TileMode.mirror => ui.TileMode.mirror,
    TileMode.decal => ui.TileMode.decal,
  };
}

/// Converts vector_graphics_compiler's gradients to dart:ui's.
extension GradientConverter on Gradient {
  /// This gradient as a dart:ui one, with [opacity] multiplied into its colors.
  ///
  /// Returns null if it has no colors, as SVG then paints nothing with it, or
  /// if it's neither linear nor radial. Its bounds must already be applied, as
  /// in parsed [VectorInstructions]: its [Gradient.unitMode] is then
  /// [GradientUnitMode.transformed].
  ui.Gradient? toUiGradient([double opacity = 1]) {
    assert(
      unitMode == null || unitMode == GradientUnitMode.transformed,
      'Gradient bounds must be applied before conversion',
    );
    final c = colors;
    if (c == null || c.isEmpty) {
      return null;
    }
    final uiColors = [for (final color in c) _color(color, opacity)];
    final uiTileMode = tileMode?.toUiTileMode() ?? ui.TileMode.clamp;
    final matrix4 = transform?.toMatrix4();
    final g = this;
    if (g is LinearGradient) {
      return ui.Gradient.linear(
        ui.Offset(g.from.x, g.from.y),
        ui.Offset(g.to.x, g.to.y),
        uiColors,
        offsets,
        uiTileMode,
        matrix4,
      );
    }
    if (g is RadialGradient) {
      final f = g.focalPoint;
      // vector_graphics_compiler has no focal radius, so it stays dart:ui's
      // default, 0.
      return ui.Gradient.radial(
        ui.Offset(g.center.x, g.center.y),
        g.radius,
        uiColors,
        offsets,
        uiTileMode,
        matrix4,
        f == null ? null : ui.Offset(f.x, f.y),
      );
    }
    return null;
  }
}

/// Converts vector_graphics_compiler's paints to dart:ui's.
extension PaintConverter on Paint {
  /// This paint's fill and stroke as dart:ui paints, with [opacity] multiplied
  /// into their colors.
  VectorPaint toVectorPaint([double opacity = 1]) => VectorPaint(
    fill: toFilledUiPaint(opacity),
    stroke: toStrokedUiPaint(opacity),
  );

  /// This paint's stroke as a dart:ui paint, with [opacity] multiplied into
  /// its color.
  ///
  /// Returns null if the stroke paints nothing: if there's none, if its width
  /// is 0, or if its gradient has no colors. A stroke with no width, or a
  /// negative one, gets SVG's default width, 1.
  ui.Paint? toStrokedUiPaint([double opacity = 1]) {
    final s = stroke;
    final w = s?.width;
    final width = w == null || w < 0 ? 1.0 : w;
    if (s == null || width == 0) {
      return null;
    }
    final shader = s.shader?.toUiGradient(opacity);
    if (s.shader != null && shader == null) {
      return null;
    }
    final p = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..blendMode = blendMode.toUiBlendMode()
      ..strokeWidth = width
      ..color = _color(s.color, shader == null ? opacity : 1)
      ..shader = shader;
    // With no miter limit, the paint keeps the engine's default. Setting the
    // value that dart:ui's getter reads back would change it (miterLimitOf).
    final m = s.miterLimit;
    if (m != null) {
      p.strokeMiterLimit = m;
    }
    final c = s.cap;
    if (c != null) {
      p.strokeCap = c.toUiStrokeCap();
    }
    final j = s.join;
    if (j != null) {
      p.strokeJoin = j.toUiStrokeJoin();
    }
    return p;
  }

  /// This paint's fill as a dart:ui paint, with [opacity] multiplied into its
  /// color.
  ///
  /// Returns null if the fill paints nothing: if there's none, or if its
  /// gradient has no colors.
  ui.Paint? toFilledUiPaint([double opacity = 1]) {
    final f = fill;
    if (f == null) {
      return null;
    }
    final shader = f.shader?.toUiGradient(opacity);
    if (f.shader != null && shader == null) {
      return null;
    }
    return ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..blendMode = blendMode.toUiBlendMode()
      ..color = _color(f.color, shader == null ? opacity : 1)
      ..shader = shader;
  }
}

/// Converts vector_graphics_compiler's paths to dart:ui's.
extension PathConverter on Path {
  /// This path as a dart:ui path.
  ui.Path toUiPath() {
    final p = ui.Path()
      ..fillType = fillType == PathFillType.evenOdd
          ? ui.PathFillType.evenOdd
          : ui.PathFillType.nonZero;
    for (final c in commands) {
      if (c is MoveToCommand) {
        p.moveTo(c.x, c.y);
      } else if (c is LineToCommand) {
        p.lineTo(c.x, c.y);
      } else if (c is CubicToCommand) {
        p.cubicTo(c.x1, c.y1, c.x2, c.y2, c.x3, c.y3);
      } else if (c is CloseCommand) {
        p.close();
      }
    }
    return p;
  }

  /// Whether any of this path's contours encloses an area.
  ///
  /// That is, whether a contour's points, its curves' control points included,
  /// aren't all on one line. In SVG, a fill of a path with no area paints
  /// nothing. A canvas, on Skia and Impeller, paints a hairline instead.
  bool get hasArea {
    double x0 = 0, y0 = 0, dx = 0, dy = 0;
    var direction = false;
    // Whether (x, y) lies off the line through the contour's first two
    // distinct points, by more than a millionth of the distance between them.
    bool offLine(double x, double y) {
      if (direction) {
        final cross = dx * (y - y0) - dy * (x - x0);
        return cross.abs() > 1e-6 * (dx * dx + dy * dy);
      }
      if (x != x0 || y != y0) {
        dx = x - x0;
        dy = y - y0;
        direction = true;
      }
      return false;
    }

    for (final c in commands) {
      if (c is MoveToCommand) {
        x0 = c.x;
        y0 = c.y;
        direction = false;
      } else if (c is LineToCommand) {
        if (offLine(c.x, c.y)) {
          return true;
        }
      } else if (c is CubicToCommand) {
        if (offLine(c.x1, c.y1) || offLine(c.x2, c.y2) || offLine(c.x3, c.y3)) {
          return true;
        }
      }
    }
    return false;
  }
}
