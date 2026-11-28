import 'dart:ui';

import 'package:flame_rasterizer_example/commons/material.dart' show Colors;

/// The paints of MultipleShapes' paths, each of which is an SVG's outline.
abstract final class OutlinePaints() {
  /// The paths' colors, given to the SVGs in turn.
  ///
  /// They are Material's colors, except green and purple, which the shapes
  /// use as tints.
  static const colors = [
    Colors.blue,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.amber,
    Colors.indigo,
    Colors.red,
  ];

  /// A path's stroke width, as a share of its outline's longer side.
  static const _strokeShare = 1 / 50;

  /// Creates the paints for a path whose outline's longer side is
  /// [longestSide] long.
  ///
  /// The fill is [color] at the alpha of Flame's example. The stroke is
  /// lighter and rounded, and [_strokeShare] of that side wide.
  static List<Paint> of(Color color, double longestSide) => [
    Paint()..color = color.withValues(alpha: 0.8),
    Paint()
      ..color = Color.lerp(color, Colors.white, 0.5)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = longestSide * _strokeShare
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round,
  ];
}
