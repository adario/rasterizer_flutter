// Checks the canvas renderer's SVG import, from this package's folder:
//   flutter test test/svg_paths_test.dart
//
// The canvas renderer imports SVGs with SvgPaths, a trimmed version of one
// written for flame_svg. Its scenes must match those of the GPU renderer,
// which Rasterizer's core imports with NanoSVG. The test also checks how
// SvgPaths handles opacity, merging, masks and patterns.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/svg_paths/svg_paths.dart';

/// An SVG of [body], 100 by 100 unless [root] sets other attributes.
String svg(
  String body, {
  String root = 'width="100" height="100" viewBox="0 0 100 100"',
}) => '<svg xmlns="http://www.w3.org/2000/svg" $root>$body</svg>';

/// The scenes of [source] for the GPU renderer and for the canvas renderer.
(RasterizerScene, RasterizerScene) scenes(String source) {
  final bytes = Uint8List.fromList(utf8.encode(source));
  return (
    RasterizerScene.fromSvg(bytes, backend: RasterizerBackend.gpu),
    RasterizerScene.fromSvg(bytes, backend: RasterizerBackend.canvas),
  );
}

/// Expects each edge of [actual] within [tolerance] of [expected]'s.
void expectRect(
  ui.Rect actual,
  ui.Rect expected, {
  double tolerance = 0.01,
  String? reason,
}) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(
      a,
      closeTo(e, tolerance),
      reason: '${reason ?? ''} $actual against $expected',
    );
  }
}

ui.Color fillColor(SvgPaths paths, int i) => paths.paths[i].paint.fill!.color;

void main() {
  group('the same coordinates as the core', () {
    final cases = {
      'shapes': svg(
        '<rect x="10" y="20" width="30" height="40" fill="red"/><circle cx="70" cy="70" r="20" fill="blue"/>',
      ),
      'stroked': svg(
        '<path d="M10,10 L90,10 L90,90" fill="none" stroke="black" stroke-width="6"/>',
      ),
      'default stroke width, transformed': svg(
        '<g transform="scale(4)"><path d="M2,5 L20,5" fill="none" stroke="black"/></g>',
      ),
      "root's stroke width, transformed": svg(
        '<g transform="scale(2)"><path d="M5,20 L40,20" fill="none" stroke="black"/></g>',
        root: 'width="100" height="100" viewBox="0 0 100 100" stroke-width="3"',
      ),
      "root's style's stroke width, transformed": svg(
        '<g transform="scale(2)"><path d="M5,20 L40,20" fill="none" stroke="black"/></g>',
        root:
            'width="100" height="100" viewBox="0 0 100 100" '
            'style="stroke-width:3"',
      ),
      'a clip path that mixes clip rules': svg(
        '<defs><clipPath id="c"><rect width="50" height="50"/>'
        '<rect x="50" width="50" height="50" clip-rule="evenodd"/></clipPath>'
        '</defs><rect width="100" height="100" fill="red" fill-opacity="0.5" '
        'clip-path="url(#c)"/>',
      ),
      'a clip path in a style': svg(
        '<defs><clipPath id="c"><rect width="50" height="50"/>'
        '<rect x="50" width="50" height="50" clip-rule="evenodd"/></clipPath>'
        '</defs><rect width="100" height="100" fill="red" '
        'style="fill-opacity:0.5;clip-path:url(#c)"/>',
      ),
      'a shape drawn twice under two clip paths': svg(
        '<defs><clipPath id="l"><rect width="50" height="100"/></clipPath>'
        '<clipPath id="r"><rect x="50" width="50" height="100"/></clipPath>'
        '</defs><g clip-path="url(#l)">'
        '<circle cx="50" cy="50" r="40" fill="red"/></g>'
        '<g clip-path="url(#r)"><circle cx="50" cy="50" r="40" fill="red"/></g>',
      ),
      'transformed group': svg(
        '<g transform="translate(20,10) scale(2)"><rect x="0" y="0" width="10" height="5"/></g>',
      ),
      'viewBox origin': svg(
        '<rect x="-40" y="-10" width="50" height="30"/>',
        root: 'width="200" height="200" viewBox="-50 -20 100 100"',
      ),
      'no viewBox': svg(
        '<rect x="5" y="5" width="10" height="10"/>',
        root: 'width="64" height="48"',
      ),
      'gradient': svg(
        '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>'
        '</linearGradient></defs><rect x="10" y="10" width="80" height="20" fill="url(#g)"/>',
      ),
    };
    for (final MapEntry(key: name, value: source) in cases.entries) {
      test(name, () {
        final (core, canvas) = scenes(source);
        expectRect(canvas.viewBox, core.viewBox, reason: 'viewBox');
        expectRect(canvas.bounds, core.bounds, reason: 'bounds');
        expect(canvas.pathCount, core.pathCount);
      });
    }

    test('the tiger', () {
      final source = File('example/assets/tiger/tiger.svg').readAsStringSync();
      final (core, canvas) = scenes(source);
      expectRect(canvas.viewBox, core.viewBox, reason: 'viewBox');
      // The core takes its bounds from the control points of NanoSVG's
      // cubics, and SvgPaths from Flutter's paths, so they differ a little.
      expectRect(canvas.bounds, core.bounds, tolerance: 1, reason: 'bounds');
      // ignore: avoid_print
      print(
        '  tiger: ${core.pathCount} core draws, ${canvas.pathCount} canvas '
        'draws (merged), bounds ${core.bounds} & ${canvas.bounds}',
      );
    });
  });

  group('skipped by the core as by vector_graphics_compiler', () {
    // The ghost shows only if its element isn't skipped. The other shape
    // always shows.
    const ghost = '<rect width="10" height="10"/>',
        drawn = '<rect x="50" y="50" width="10" height="10" fill="blue"/>',
        gradient =
            '<linearGradient id="g"><stop offset="0" stop-color="red"/>'
            '<stop offset="1" stop-color="green"/></linearGradient>',
        painted = '<rect x="20" y="20" width="10" height="10" fill="url(#g)"/>';
    const only = ui.Rect.fromLTRB(50, 50, 60, 60);
    final cases = <String, (String, ui.Rect)>{
      for (final element in [
        'clipPath id="c"',
        'mask id="m"',
        'pattern id="p" width="10" height="10"',
        'symbol id="s"',
        // Elements that neither import draws, so their content is skipped.
        'clippath id="c"',
        'marker id="k"',
        'switch',
        'style',
        'foo',
      ])
        '<${element.split(' ').first}>': (
          '<$element>$ghost</${element.split(' ').first}>$drawn',
          only,
        ),
      'a clip in <defs>': (
        '<defs><clipPath id="c">$ghost</clipPath></defs>$drawn',
        only,
      ),
      'a gradient in a mask, still used': (
        '<mask id="m">$gradient$ghost</mask>$painted$drawn',
        const ui.Rect.fromLTRB(20, 20, 60, 60),
      ),
      'a gradient in an element it doesn\'t handle, not used': (
        '<foo>$gradient</foo>$painted$drawn',
        only,
      ),
      '<a>, a group whose attributes are inherited': (
        '<a stroke="red" stroke-width="10">$drawn</a>',
        const ui.Rect.fromLTRB(45, 45, 65, 65),
      ),
      'a comment\'s clip, as recycle.svg\'s': (
        '<!-- <clipPath id="c">$ghost</clipPath> -->$drawn',
        only,
      ),
      'a comment with a > before its shapes': (
        '<!-- a > b $ghost -->$drawn',
        only,
      ),
      'CDATA with a > before its shapes': (
        '<text><![CDATA[ a > b $ghost ]]></text>$drawn',
        only,
      ),
      'a group in a clip, which the group around keeps': (
        '<g transform="translate(5,5)"><clipPath id="c">'
            '<g transform="scale(2)">$ghost</g></clipPath>$drawn</g>',
        const ui.Rect.fromLTRB(55, 55, 65, 65),
      ),
      'a group in <defs>, which the group around keeps': (
        '<g transform="translate(5,5)"><defs><g>$ghost</g></defs>$drawn</g>',
        const ui.Rect.fromLTRB(55, 55, 65, 65),
      ),
      'self-closing elements without a space': ('<foo/><defs/>$drawn', only),
    };
    for (final MapEntry(key: name, value: (body, bounds)) in cases.entries) {
      test(name, () {
        final (core, canvas) = scenes(svg(body));
        expectRect(canvas.bounds, bounds, reason: 'canvas');
        expectRect(core.bounds, bounds, reason: 'core');
        expect(core.pathCount, canvas.pathCount);
      });
    }
  });

  group('opacity multiplied into the paints, as the core does', () {
    test('element and group opacity, nested', () {
      final paths = SvgPaths(
        svg(
          '<g opacity="0.5"><rect width="10" height="10" fill="red"/>'
          '<g opacity="0.5"><rect x="20" width="10" height="10" fill="red" fill-opacity="0.5"/></g></g>'
          '<rect x="40" width="10" height="10" fill="red" opacity="0.25"/><rect x="60" width="10" height="10" fill="red"/>',
        ),
        merge: false,
      );
      expect(
        [for (var i = 0; i < 4; i++) fillColor(paths, i).a],
        [closeTo(0.5, 0.01), closeTo(0.125, 0.01), closeTo(0.25, 0.01), 1],
      );
    });

    test('in gradients\' colours', () {
      final paths = SvgPaths(
        svg(
          '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>'
          '</linearGradient></defs><g opacity="0.5"><rect width="80" height="20" fill="url(#g)"/></g>',
        ),
      );
      final paint = paths.paths.single.paint.fill!;
      expect(paint.shader, isNotNull);
      expect(paint.color.a, 1);
    });
  });

  group('merging', () {
    test('consecutive paths with one paint whose bounds don\'t overlap', () {
      final source = svg(
        '<rect width="10" height="10" fill="red"/><rect x="20" width="10" height="10" fill="red"/>'
        '<rect x="25" width="10" height="10" fill="red"/><rect x="50" width="10" height="10" fill="blue"/>',
      );
      expect(SvgPaths(source).paths.length, 3);
      expect(SvgPaths(source, merge: false).paths.length, 4);
    });

    test('not paths with a fill and a stroke', () {
      expect(
        SvgPaths(
          svg(
            '<rect width="10" height="10" fill="red" stroke="black"/>'
            '<rect x="50" width="10" height="10" fill="red" stroke="black"/>',
          ),
        ).paths.length,
        2,
      );
    });
  });

  group('skipped', () {
    test('masks\' own shapes, but not their content', () {
      final paths = SvgPaths(
        svg(
          '<defs><mask id="m"><rect width="50" height="50" fill="white"/></mask></defs>'
          '<rect width="100" height="100" fill="red" mask="url(#m)"/><rect x="10" width="10" height="10" fill="blue"/>',
        ),
      );
      expect(paths.paths.length, 2);
      expect(
        [for (var i = 0; i < 2; i++) fillColor(paths, i).toARGB32()],
        [0xFFFF0000, 0xFF0000FF],
      );
    });

    test('patterns\' tiles and the shapes painted with them', () {
      final paths = SvgPaths(
        svg(
          '<defs><pattern id="p" width="10" height="10" '
          'patternUnits="userSpaceOnUse">'
          '<rect width="5" height="5" fill="green"/></pattern></defs><rect width="100" height="100" fill="url(#p)"/>'
          '<rect x="10" width="10" height="10" fill="blue"/>',
        ),
      );
      expect(paths.paths.length, 1);
      expect(fillColor(paths, 0).toARGB32(), 0xFF0000FF);
    });
  });

  test('a stroke of width 0 isn\'t drawn', () {
    final (core, canvas) = scenes(
      svg(
        '<path d="M10,10 L90,90" fill="none" stroke="black" stroke-width="0"/>',
      ),
    );
    expect(canvas.pathCount, core.pathCount);
    expect(canvas.pathCount, 0);
  });

  test('paths without an area aren\'t filled', () {
    int draws(String body) => scenes(svg(body)).$2.pathCount;
    // A canvas would paint these fills as hairlines.
    expect(draws('<path d="M10,10 L90,90"/>'), 0);
    expect(draws('<path d="M10,50 L50,50 L90,50 Z"/>'), 0);
    expect(draws('<path d="M10,10 L50,50 M20,20 L80,80"/>'), 0);
    expect(draws('<path d="M10,95 L90,95" stroke="black"/>'), 1);
    // The line's stroke still draws. The curve, the triangle and the
    // second subpath have an area, so they're filled.
    expect(draws('<path d="M10,50 C30,10 70,90 90,50"/>'), 1);
    expect(draws('<path d="M10,10 L90,10 L50,90 Z"/>'), 1);
    expect(draws('<path d="M10,10 L90,90 M10,90 L90,90 L90,10"/>'), 1);
  });

  test('a canvas scene can\'t be drawn by a GPU run, nor a GPU scene by a '
      'canvas run', () async {
    final (core, canvas) = scenes(svg('<rect width="10" height="10"/>'));
    final renderer = await RasterizerRenderer.create(
      backend: RasterizerBackend.canvas,
    );
    final run = renderer.beginFrame(100, 100).addRun();
    run.add(canvas, 1, 0, 0, 1, 0, 0);
    expect(() => run.add(core, 1, 0, 0, 1, 0, 0), throwsArgumentError);
  });
}
