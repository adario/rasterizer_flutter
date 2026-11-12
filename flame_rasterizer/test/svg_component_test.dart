// Checks RasterizerSvgComponent's size, in flutter_tester. From this
// package's folder:
//   flutter test test/svg_component_test.dart
//
// By default, the component takes its SVG's size, as a SpriteComponent takes
// its sprite's.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

// A 30 × 20 viewBox.
final _svg = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 20"> '
    '<rect width="30" height="20" fill="#ff0000"/></svg>',
  ),
);

void main() {
  test("a RasterizerSvgComponent is its SVG's size by default", () {
    final svg = RasterizerSvg.fromBytes(_svg);
    expect(RasterizerSvgComponent(svg: svg).size, Vector2(30, 20));
    expect(
      RasterizerSvgComponent(svg: svg, size: Vector2.all(8)).size,
      Vector2.all(8),
    );
    expect(RasterizerSvgComponent().size, Vector2.zero());
    expect(RasterizerSvgComponent(nativeAngle: 1).nativeAngle, 1);
    svg.dispose();
  });
}
