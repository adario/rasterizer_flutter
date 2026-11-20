import 'dart:ui';

import 'package:flame_rasterizer_example/commons/material.dart' show Colors;

/// The paints of MultipleShapes' paths, each an SVG's outline.
abstract final class OutlinePaints() {
  /// The paths' colors, one for each SVG, in turn: Material's colors, except
  /// the tints' green and purple.
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

  /// Creates paints for a path whose outline's longer side is [longestSide]
  /// long: a fill in [color], at Flame's example's alpha, and a lighter,
  /// rounded stroke, [_strokeShare] of that side wide.
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
