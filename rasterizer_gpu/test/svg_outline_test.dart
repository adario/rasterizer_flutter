// Checks SvgOutline, an SVG's outline for hitboxes. From this package's
// folder:
//   flutter test test/svg_outline_test.dart
//
// The outline is parsed in Dart, whatever the backend, in the SVG's
// coordinates. Its filled paths are closed, as SVG fills them. Its paths that
// are only stroked stay as they are.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

Uint8List svg(
  String body, {
  String root = 'width="100" height="100" viewBox="0 0 100 100"',
}) => Uint8List.fromList(
  utf8.encode('<svg xmlns="http://www.w3.org/2000/svg" $root>$body</svg>'),
);

List<bool> closedContours(ui.Path path) => [
  for (final metric in path.computeMetrics()) metric.isClosed,
];

void main() {
  test('a filled open contour is closed, as SVG fills it', () {
    final outline = SvgOutline.fromSvg(
      svg('<path d="M10 10 L90 10 L90 90" fill="#ff0000"/>'),
    );
    expect(closedContours(outline.path), [true]);
    expect(outline.path.contains(const ui.Offset(80, 30)), isTrue);
  });

  test('a stroked-only open contour stays open', () {
    final outline = SvgOutline.fromSvg(
      svg(
        '<path d="M10 10 L90 10" fill="none" stroke="#ff0000" '
        'stroke-width="4"/>',
      ),
    );
    expect(closedContours(outline.path), [false]);
  });

  test("its path is in the SVG's coordinates, and its rect is the viewBox", () {
    final bytes = svg(
      '<rect x="60" y="70" width="20" height="10" fill="#ff0000"/>',
      root: 'width="100" height="100" viewBox="50 50 100 100"',
    );
    final outline = SvgOutline.fromSvg(bytes);
    expect(outline.path.getBounds(), const ui.Rect.fromLTRB(60, 70, 80, 80));
    expect(outline.rect, const ui.Rect.fromLTWH(50, 50, 100, 100));
    final scene = RasterizerScene.fromSvg(
      bytes,
      backend: RasterizerBackend.canvas,
    );
    expect(outline.rect, scene.viewBox);
    expect(scene.rect, scene.viewBox);
  });

  test('with an empty size and no viewBox, its rect is the bounds, as its '
      "scene's", () {
    final bytes = svg(
      '<rect x="10" y="20" width="30" height="40" fill="#ff0000"/>',
      root: 'width="0" height="0"',
    );
    final outline = SvgOutline.fromSvg(bytes);
    expect(outline.rect, const ui.Rect.fromLTWH(10, 20, 30, 40));
    final scene = RasterizerScene.fromSvg(
      bytes,
      backend: RasterizerBackend.canvas,
    );
    expect(scene.rect, outline.rect);
  });

  test("bytes that aren't an SVG throw", () {
    expect(
      () => SvgOutline.fromSvg(Uint8List.fromList(utf8.encode('nope'))),
      throwsArgumentError,
    );
  });
}
