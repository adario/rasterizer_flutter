// ignore_for_file: avoid_print
// Checks the mesh renderer's import through FFI, from this package's folder:
//   flutter test test/mesh_test.dart
//
// The import turns each path into triangles. Their areas, and the points
// they cover, must match what SVG fills and strokes. The test also checks
// the strokes' offsets, the glows and the paints.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:rasterizer_gpu/src/core.dart';
import 'package:test/test.dart';

/// An SVG of [body], whose viewBox is 100 by 100 unless [viewBox] sets it.
Uint8List svg(String body, {String viewBox = '0 0 100 100'}) =>
    Uint8List.fromList(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>'
          .codeUnits,
    );

/// The mesh of an SVG of [body], flattened for [maxSize] pixels.
Mesh mesh(String body, {double maxSize = 1000}) =>
    Mesh.fromSvgBytes(svg(body), maxSize: maxSize);

/// The triangles of [m]'s path [path], as x and y for each of 3 corners.
Iterable<List<double>> triangles(Mesh m, int path) sync* {
  final p = m.paths[path], v = m.vertices, i = m.indices as List<int>;
  final f = m.vertexFloats;
  for (var k = p.indexBegin; k < p.indexBegin + p.indexCount; k += 3) {
    yield [
      for (var j = 0; j < 3; j++) ...[v[i[k + j] * f], v[i[k + j] * f + 1]],
    ];
  }
}

/// The area of the triangles of [m]'s path [path].
double area(Mesh m, [int path = 0]) {
  var sum = 0.0;
  for (final t in triangles(m, path)) {
    sum += ((t[2] - t[0]) * (t[5] - t[1]) - (t[4] - t[0]) * (t[3] - t[1]))
        .abs();
  }
  return sum / 2;
}

/// How many of [path]'s triangles hold [x0], [y0].
///
/// The point is nudged off the diagonals that split rectangles in two.
int coverage(Mesh m, double x0, double y0, [int path = 0]) {
  final x = x0 + 1.23e-3, y = y0 + 2.71e-3;
  var count = 0;
  for (final t in triangles(m, path)) {
    double side(int a, int b) =>
        (t[b] - t[a]) * (y - t[a + 1]) - (t[b + 1] - t[a + 1]) * (x - t[a]);
    final s0 = side(0, 2), s1 = side(2, 4), s2 = side(4, 0);
    if ((s0 > 0 && s1 > 0 && s2 > 0) || (s0 < 0 && s1 < 0 && s2 < 0)) {
      count++;
    }
  }
  return count;
}

/// The most triangles of [path] that hold one point of a grid over [m]'s
/// bounds: 1 when no triangles overlap.
int maxCoverage(Mesh m, [int path = 0]) {
  var most = 0;
  final b = m.bounds;
  for (var j = 0; j < 40; j++) {
    for (var i = 0; i < 40; i++) {
      most = math.max(
        most,
        coverage(
          m,
          b.lx + (i + 0.37) / 40 * b.width,
          b.ly + (j + 0.61) / 40 * b.height,
          path,
        ),
      );
    }
  }
  return most;
}

/// The point that [t] maps [x], [y] to.
(double, double) apply(Transform t, double x, double y) =>
    (t.a * x + t.c * y + t.tx, t.b * x + t.d * y + t.ty);

/// A path of [d], stroked black, with [attributes].
String stroke(String d, String attributes) =>
    '<path d="$d" fill="none" stroke="#000" $attributes/>';

/// Checks that [m] is well formed.
///
/// Each index points at a vertex, and each vertex is finite and holds its
/// path's index. Each path's triangles come right after the previous path's.
void checkWellFormed(Mesh m) {
  final i = m.indices as List<int>, v = m.vertices, f = m.vertexFloats;
  expect(m.indexCount % 3, 0);
  expect(i.every((k) => k < m.vertexCount), isTrue);
  expect(v.every((f) => f.isFinite), isTrue);
  var next = 0, misplaced = 0;
  for (var p = 0; p < m.paths.length; p++) {
    final path = m.paths[p];
    expect(path.indexBegin, next);
    expect(path.indexCount, greaterThan(0));
    next += path.indexCount;
    for (var k = path.indexBegin; k < next; k++) {
      if (v[i[k] * f + 2] != p) {
        misplaced++;
      }
    }
  }
  expect(next, m.indexCount);
  expect(misplaced, 0, reason: "vertices without their path's index");
  final strips = m.stripIndices as List<int>?;
  if (strips != null) {
    expect(strips.length % 3, 0);
    expect(strips.every((k) => k < m.vertexCount), isTrue);
    expect(m.stripIndices.runtimeType, m.indices.runtimeType);
  }
}

/// The x, y and offset ux, uy of vertex [k] of [m], a mesh with offsets.
///
/// A stroke's vertex lies at the point it's built around, plus its offset
/// times the stroke's half width.
List<double> offsetVertex(Mesh m, int k) {
  final v = m.vertices;
  return [v[k * 5], v[k * 5 + 1], v[k * 5 + 3], v[k * 5 + 4]];
}

/// The vertices [indices] use, each once.
Set<int> used(List<int> indices) => indices.toSet();

/// The point that vertex [k] is built around, for a half width of [hw].
(double, double) centerOf(Mesh m, int k, double hw) {
  final [x, y, ux, uy] = offsetVertex(m, k);
  return (x - ux * hw, y - uy * hw);
}

/// Whether [p] is within 1e-3 of one of [points].
bool near((double, double) p, List<(double, double)> points) =>
    points.any((q) => (p.$1 - q.$1).abs() < 1e-3 && (p.$2 - q.$2).abs() < 1e-3);

/// The sum of the areas of [indices]' triangles.
double areaOf(Mesh m, List<int> indices) {
  final v = m.vertices, f = m.vertexFloats;
  var sum = 0.0;
  for (var k = 0; k < indices.length; k += 3) {
    final [a, b, c] = [for (var j = 0; j < 3; j++) indices[k + j] * f];
    sum +=
        ((v[b] - v[a]) * (v[c + 1] - v[a + 1]) -
                (v[c] - v[a]) * (v[b + 1] - v[a + 1]))
            .abs();
  }
  return sum / 2;
}

/// The vertices of path [p] of [m], a mesh with a glow, as x, y and glow.
Set<(double, double, double)> glowVertices(Mesh m, int p) {
  final i = m.indices as List<int>, v = m.vertices, path = m.paths[p];
  return {
    for (var k = path.indexBegin; k < path.indexBegin + path.indexCount; k++)
      (v[i[k] * 6], v[i[k] * 6 + 1], v[i[k] * 6 + 5]),
  };
}

/// The points of path [p] of [m] whose glow is 0: the ribbon's outer edge.
List<(double, double)> ribbonEdge(Mesh m, int p) => [
  for (final (x, y, glow) in glowVertices(m, p))
    if (glow == 0) (x, y),
];

/// [m]'s bounds, as a list.
List<double> boundsOf(Mesh m) => [
  m.bounds.lx,
  m.bounds.ly,
  m.bounds.ux,
  m.bounds.uy,
];

void main() {
  group('fills', () {
    test('a rectangle is its area, in its color, premultiplied', () {
      final m = mesh(
        '<rect x="10" y="20" width="30" height="40" fill="#ff8000" '
        'fill-opacity="0.5"/>',
      );
      checkWellFormed(m);
      expect(m.paths, hasLength(1));
      expect(m.paths[0].paint, MeshPaint.color);
      final c = m.paths[0].color;
      // An opacity of 0.5 is an alpha of 127 / 255.
      expect(c[0], closeTo(0.5, 1e-2));
      expect(c[1], closeTo(128 / 255 * 0.5, 1e-2));
      expect(c[2], 0);
      expect(c[3], closeTo(0.5, 1e-2));
      expect(area(m), closeTo(1200, 1e-3));
      expect(m.indices, isA<Uint16List>());
      expect(
        [m.bounds.lx, m.bounds.ly, m.bounds.ux, m.bounds.uy],
        [10, 20, 40, 60],
      );
      expect([m.svgBounds.ux, m.svgBounds.uy], [100, 100]);
    });

    test('nested contours: nonzero fills both, even-odd cuts a hole', () {
      const d = 'M10,10 H90 V90 H10 Z M30,30 H70 V70 H30 Z';
      final nonzero = mesh('<path d="$d"/>'),
          evenOdd = mesh('<path fill-rule="evenodd" d="$d"/>'),
          reversed = mesh(
            '<path d="M10,10 H90 V90 H10 Z M30,30 V70 H70 V30 Z"/>',
          );
      expect(area(nonzero), closeTo(6400, 1e-2));
      expect(coverage(nonzero, 50, 50), 1);
      expect(area(evenOdd), closeTo(4800, 1e-2));
      expect(coverage(evenOdd, 50, 50), 0);
      expect(coverage(evenOdd, 20, 20), 1);
      // The reversed inner contour brings the winding back to 0.
      expect(area(reversed), closeTo(4800, 1e-2));
      expect(coverage(reversed, 50, 50), 0);
    });

    test('self-intersections, with either rule', () {
      const star = 'M50,5 L79,90 L5,35 L95,35 L21,90 Z';
      final nonzero = mesh('<path d="$star"/>'),
          evenOdd = mesh('<path fill-rule="evenodd" d="$star"/>');
      expect(coverage(nonzero, 50, 50), 1);
      expect(coverage(evenOdd, 50, 50), 0);
      expect(coverage(nonzero, 50, 15), 1);
      expect(coverage(evenOdd, 50, 15), 1);
      expect(maxCoverage(nonzero), 1);
      expect(maxCoverage(evenOdd), 1);
      // A bow tie's halves wind opposite ways, so both rules fill them.
      const bowTie = 'M0,0 L100,100 L100,0 L0,100 Z';
      expect(area(mesh('<path d="$bowTie"/>')), closeTo(5000, 1e-2));
      expect(
        area(mesh('<path fill-rule="evenodd" d="$bowTie"/>')),
        closeTo(5000, 1e-2),
      );
    });

    test('overlapping contours: nonzero unites them, even-odd cuts the '
        'overlap', () {
      const d = 'M0,0 H60 V60 H0 Z M40,40 H100 V100 H40 Z';
      final nonzero = mesh('<path d="$d"/>'),
          evenOdd = mesh('<path fill-rule="evenodd" d="$d"/>');
      expect(area(nonzero), closeTo(6800, 1e-2));
      expect(coverage(nonzero, 50, 50), 1);
      expect(maxCoverage(nonzero), 1);
      expect(area(evenOdd), closeTo(6400, 1e-2));
      expect(coverage(evenOdd, 50, 50), 0);
    });

    test('curves are flattened within the tolerance at maxSize', () {
      const r = 40.0;
      final exact = math.pi * r * r;
      var vertices = 0;
      for (final maxSize in [100.0, 1000.0]) {
        final m = mesh('<circle cx="50" cy="50" r="$r"/>', maxSize: maxSize);
        // A quarter of a pixel, in a 100 unit viewBox.
        final tolerance = 0.25 * 100 / maxSize;
        // Chords cut each curve by at most the tolerance. And the circle's
        // cubics stray from it by up to 0.03% of its radius.
        expect(
          area(m),
          inInclusiveRange(
            exact - 2 * math.pi * r * (tolerance + 3e-4 * r),
            exact + 2 * math.pi * r * 3e-4 * r,
          ),
        );
        expect(m.vertexCount, greaterThan(vertices));
        vertices = m.vertexCount;
      }
    });
  });

  group('strokes', () {
    test("a line's caps", () {
      double capped(String cap) => area(
        mesh(stroke('M10,50 H90', 'stroke-width="10" stroke-linecap="$cap"')),
      );
      expect(capped('butt'), closeTo(800, 1e-2));
      expect(capped('square'), closeTo(900, 1e-2));
      // On average, arcs' chords cut 2/3 of the tolerance off.
      expect(capped('round'), closeTo(800 + math.pi * 25, 1));
    });

    test("a square's joins", () {
      Mesh joined(String join) => mesh(
        '<rect x="20" y="20" width="60" height="60" fill="none" stroke="#000" '
        'stroke-width="10" stroke-linejoin="$join"/>',
      );
      final miter = joined('miter'), bevel = joined('bevel');
      expect(area(miter), closeTo(2400, 1e-2));
      expect(coverage(miter, 50, 50), 0);
      expect(coverage(miter, 20, 50), 1);
      expect(coverage(miter, 16, 16), 1);
      expect(maxCoverage(miter), 1);
      // A strip: 2 triangles per side, plus 1 per corner for bevels.
      expect(miter.indexCount ~/ 3, 8);
      expect(area(bevel), closeTo(2400 - 4 * 12.5, 1e-2));
      expect(bevel.indexCount ~/ 3, 12);
      expect(maxCoverage(bevel), 1);
      expect(
        area(joined('round')),
        closeTo(2400 - 4 * (25 - math.pi * 25 / 4), 1),
      );
    });

    test('the miter limit bevels sharp corners', () {
      // A corner of 53°, whose miter ratio is 1 / sin(26.6°), 2.24.
      Mesh limited(double limit) => mesh(
        stroke(
          'M10,90 L50,10 L90,90',
          'stroke-width="4" stroke-miterlimit="$limit"',
        ),
      );
      final miter = limited(4), bevel = limited(2);
      // The miter's tip is 4.5 above the corner, and the bevel's edge 0.9.
      expect(coverage(miter, 50, 6.5), 1);
      expect(coverage(bevel, 50, 6.5), 0);
      expect(coverage(bevel, 50, 9.5), 1);
      expect(area(miter), greaterThan(area(bevel)));
    });

    test("round joins' small turns take their miter, within the tolerance", () {
      // The circle is flattened into segments, each a quad of the strip.
      final m = mesh(
        '<circle cx="50" cy="50" r="40" fill="none" stroke="#000" '
        'stroke-width="4" stroke-linejoin="round"/>',
      );
      expect(m.vertexCount, greaterThan(32));
      expect(m.indexCount ~/ 3, m.vertexCount, reason: '2 a segment');
      expect(maxCoverage(m), 1);
      // With miters, its area is the flattened circle's perimeter times the
      // stroke's width.
      expect(area(m), closeTo(math.pi * (42 * 42 - 38 * 38), 0.5));
    });

    test('a self-overlapping stroke covers its overlap once', () {
      final m = mesh(
        stroke('M0,0 L100,100 M0,100 L100,0', 'stroke-width="10"'),
      );
      expect(area(m), closeTo(2 * math.sqrt2 * 100 * 10 - 100, 0.05));
      expect(coverage(m, 50, 50), 1);
      expect(maxCoverage(m), 1);
      // A turn back, and a sharp turn whose inner miter reaches past both
      // segments.
      for (final d in ['M10,50 H90 H30', 'M10,50 H90 L10,55']) {
        final turn = mesh(
          stroke(d, 'stroke-width="10" stroke-linejoin="round"'),
        );
        expect(maxCoverage(turn), 1, reason: d);
        expect(coverage(turn, 50, 50), 1, reason: d);
      }
    });

    test('a sharp turn stays within half the width of the path', () {
      // Inner miters would reach far past the segments here: a turn back to
      // a point left of the start, and a jog back and forth, as in the
      // example's spaceship outline. The quads overlap instead.
      const paths = {
        'M10,50 H90 L10,55': [5.0, 45.0, 95.0, 60.0],
        'M90,51 L50,50 H50.5 L10,51': [5.0, 45.0, 95.0, 56.0],
      };
      for (final MapEntry(key: d, value: bounds) in paths.entries) {
        for (final join in ['miter', 'round', 'bevel']) {
          final m = mesh(
            stroke(d, 'stroke-width="10" stroke-linejoin="$join"'),
          );
          final b = m.bounds;
          final reason = '$d $join';
          expect(b.lx, greaterThanOrEqualTo(bounds[0] - 1e-3), reason: reason);
          expect(b.ly, greaterThanOrEqualTo(bounds[1] - 1e-3), reason: reason);
          expect(b.ux, lessThanOrEqualTo(bounds[2] + 1e-3), reason: reason);
          expect(b.uy, lessThanOrEqualTo(bounds[3] + 1e-3), reason: reason);
          expect(maxCoverage(m), 1, reason: reason);
          expect(coverage(m, 50, 50), 1, reason: reason);
        }
      }
    });

    test('dashes, with odd patterns repeated, offsets and dots', () {
      Mesh dashed(String attributes) =>
          mesh(stroke('M0,50 H100', 'stroke-width="2" $attributes'));
      final plain = dashed('stroke-dasharray="10 10"');
      expect(area(plain), closeTo(100, 1e-2));
      expect(coverage(plain, 5, 50), 1);
      expect(coverage(plain, 15, 50), 0);
      expect(area(dashed('stroke-dasharray="10"')), closeTo(100, 1e-2));
      final offset = dashed('stroke-dasharray="10 10" stroke-dashoffset="5"');
      expect(area(offset), closeTo(100, 1e-2));
      expect(coverage(offset, 2, 50), 1);
      expect(coverage(offset, 7, 50), 0);
      expect(coverage(offset, 17, 50), 1);
      // Dashes of no length are dots: at 0, 20, ... 100.
      final dots = mesh(
        stroke(
          'M0,50 H100',
          'stroke-width="4" stroke-linecap="round" stroke-dasharray="0 20"',
        ),
      );
      expect(area(dots), closeTo(6 * math.pi * 4, 2));
      expect(coverage(dots, 100, 50), 1);
    });

    test("a closed path's first & last dashes meet at its start, joined", () {
      Mesh dashed(String offset) => mesh(
        '<rect x="20" y="20" width="60" height="60" fill="none" stroke="#000" '
        'stroke-width="2" stroke-dasharray="30 30" stroke-dashoffset="$offset"/>',
      );
      // From 0, the corner at the start is a dash's start.
      final start = dashed('0');
      expect(area(start), closeTo(4 * 30 * 2, 1e-2));
      expect(coverage(start, 19.5, 19.5), 0);
      // From 15, each dash turns a corner. The last one goes on through the
      // start into the first, so that corner gets its miter and no dash ends
      // there. Each miter's square makes up for its corner's inner overlap.
      final through = dashed('15');
      expect(area(through), closeTo(4 * 30 * 2, 1e-2));
      expect(coverage(through, 19.5, 19.5), 1);
    });
  });

  group('offsets', () {
    const x = 'M0,0 L100,100 M0,100 L100,0';
    const gradient =
        '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" '
        'y1="0" x2="100" y2="0"><stop offset="0" stop-color="#f00"/>'
        '<stop offset="1" stop-color="#00f"/></linearGradient></defs>';

    test('a mesh of fills has none', () {
      final m = mesh('<rect width="10" height="10"/>');
      checkWellFormed(m);
      expect(m.vertexFloats, 3);
      expect(m.vertices.length, 3 * m.vertexCount);
      expect(m.stripIndices, isNull);
      expect(m.paths.single.halfWidth, 0);
    });

    test("a fill before a stroke has 0's, the stroke its half width", () {
      final m = mesh(
        '<rect width="10" height="10" fill="#f00"/>'
        '${stroke('M20,50 H80', 'stroke-width="6"')}',
      );
      checkWellFormed(m);
      expect(m.vertexFloats, 5);
      expect(m.vertices.length, 5 * m.vertexCount);
      expect(m.paths.map((p) => p.halfWidth), [0, 3]);
      for (final k in used(m.indices as List<int>)) {
        final [_, _, ux, uy] = offsetVertex(m, k);
        expect(m.vertices[k * 5 + 2] == 0, ux == 0 && uy == 0);
      }
    });

    test("a line's corners are built around its ends", () {
      final m = mesh(stroke('M10,50 H90', 'stroke-width="10"'));
      checkWellFormed(m);
      expect(m.vertexCount, 4);
      expect(m.stripIndices, isNull);
      for (var k = 0; k < 4; k++) {
        expect(near(centerOf(m, k, 5), const [(10, 50), (90, 50)]), isTrue);
        final [_, _, ux, uy] = offsetVertex(m, k);
        expect([ux.abs(), uy.abs()], [0, 1]);
      }
    });

    test("joins' miters and round caps' arcs, around their own points", () {
      const corners = [(20.0, 20.0), (80.0, 20.0), (80.0, 80.0), (20.0, 80.0)];
      final square = mesh(
        '<rect x="20" y="20" width="60" height="60" fill="none" stroke="#000" '
        'stroke-width="10"/>',
      );
      checkWellFormed(square);
      expect(square.vertexCount, 8);
      for (var k = 0; k < 8; k++) {
        expect(near(centerOf(square, k, 5), corners), isTrue);
        final [_, _, ux, uy] = offsetVertex(square, k);
        expect(math.sqrt(ux * ux + uy * uy), closeTo(math.sqrt2, 1e-5));
      }
      final capped = mesh(
        stroke('M10,50 H90', 'stroke-width="10" stroke-linecap="round"'),
      );
      checkWellFormed(capped);
      var hubs = 0;
      for (var k = 0; k < capped.vertexCount; k++) {
        expect(
          near(centerOf(capped, k, 5), const [(10, 50), (90, 50)]),
          isTrue,
        );
        final [_, _, ux, uy] = offsetVertex(capped, k);
        final length = math.sqrt(ux * ux + uy * uy);
        if (length == 0) {
          hubs++;
        } else {
          expect(length, closeTo(1, 1e-5));
        }
      }
      expect(hubs, 2);
    });

    test("dashes' ends are built around the dashes' own points", () {
      final m = mesh(
        stroke('M0,50 H100', 'stroke-width="2" stroke-dasharray="10 10"'),
      );
      checkWellFormed(m);
      for (var k = 0; k < m.vertexCount; k++) {
        final (cx, cy) = centerOf(m, k, 1);
        expect(cy, closeTo(50, 1e-3));
        expect(cx / 10, closeTo((cx / 10).roundToDouble(), 1e-3));
      }
    });

    test('an opaque stroke that overlaps itself keeps its strip too', () {
      final m = mesh(stroke(x, 'stroke-width="10"'));
      checkWellFormed(m);
      expect(maxCoverage(m), 1);
      final union = m.indices as List<int>;
      final strip = m.stripIndices! as List<int>;
      for (final k in used(union)) {
        final [_, _, ux, uy] = offsetVertex(m, k);
        expect([ux, uy], [0, 0], reason: 'a union has no offsets');
      }
      expect(used(strip).intersection(used(union)), isEmpty);
      const ends = [(0.0, 0.0), (100.0, 100.0), (0.0, 100.0), (100.0, 0.0)];
      for (final k in used(strip)) {
        expect(near(centerOf(m, k, 5), ends), isTrue);
      }
      // The strip covers the crossing twice, the union once.
      expect(areaOf(m, strip), closeTo(areaOf(m, union) + 100, 0.05));
    });

    test('a translucent one keeps only its union', () {
      final m = mesh(stroke(x, 'stroke-width="10" stroke-opacity="0.5"'));
      checkWellFormed(m);
      expect(m.stripIndices, isNull);
      expect(m.vertexFloats, 5);
      for (var k = 0; k < m.vertexCount; k++) {
        final [_, _, ux, uy] = offsetVertex(m, k);
        expect([ux, uy], [0, 0]);
      }
      expect(m.paths.single.halfWidth, 5);
    });

    test("a gradient's strokes, by its stops' alpha", () {
      final opaque = mesh(
        '$gradient<path d="$x" fill="none" stroke="url(#g)" '
        'stroke-width="10"/>',
      );
      expect(opaque.stripIndices, isNotNull);
      final translucent = mesh(
        '${gradient.replaceFirst('"#00f"', '"#00f" stop-opacity="0.5"')}'
        '<path d="$x" fill="none" stroke="url(#g)" stroke-width="10"/>',
      );
      expect(translucent.stripIndices, isNull);
    });

    test('a stroke that doesn\'t overlap itself keeps only its strip', () {
      final m = mesh(stroke('M10,10 H90 V90', 'stroke-width="4"'));
      checkWellFormed(m);
      expect(m.stripIndices, isNull);
      expect(
        used(m.indices as List<int>).every((k) {
          final [_, _, ux, uy] = offsetVertex(m, k);
          return ux != 0 || uy != 0;
        }),
        isTrue,
      );
    });

    test("the strips' list holds the other paths, in paint order", () {
      const fill = '<rect x="40" y="40" width="20" height="20" fill="#f00"/>';
      final m = mesh(
        '$fill${stroke(x, 'stroke-width="10"')}'
        '<rect x="5" y="40" width="9" height="9" fill="#0f0"/>'
        '${stroke('M0,0 H3', 'stroke-width="1"')}',
      );
      checkWellFormed(m);
      final a = m.indices as List<int>, b = m.stripIndices! as List<int>;
      final [first, union, second, line] = m.paths;
      expect(
        b.sublist(0, first.indexCount),
        a.sublist(first.indexBegin, first.indexCount),
      );
      final tail = second.indexCount + line.indexCount;
      expect(b.sublist(b.length - tail), a.sublist(second.indexBegin));
      expect(union.halfWidth, 5);
      expect(b.length, isNot(a.length));
    });

    test('a mesh that starts with an overlapping stroke has strips', () {
      final m = mesh(
        '${stroke(x, 'stroke-width="10"')}'
        '<rect x="40" y="40" width="20" height="20" fill="#f00"/>',
      );
      checkWellFormed(m);
      final a = m.indices as List<int>, b = m.stripIndices! as List<int>;
      final fill = m.paths[1];
      expect(b.sublist(b.length - fill.indexCount), a.sublist(fill.indexBegin));
    });
  });

  group('glow', () {
    const red = 0xFFFF0000, blue = 0xFF0000FF, tolerance = 0.01;
    const fill = PathDraw(path: 0, color: red);
    const stroked = PathDraw(path: 0, color: red, strokeWidth: 2);
    const radius10 = Glow(radius: 10);
    final square = ui.Path()..addRect(const ui.Rect.fromLTRB(20, 20, 80, 80));
    final line = ui.Path()
      ..moveTo(10, 50)
      ..lineTo(90, 50);

    Mesh glowing(List<ui.Path> paths, List<PathDraw> draws, Glow? glow) =>
        Mesh.fromPaths(
          [
            for (final path in paths)
              PathContours([path], tolerance: tolerance),
          ],
          draws,
          const Bounds(0, 0, 100, 100),
          tolerance: tolerance,
          glow: glow,
        );

    /// A path from [points], open unless [close].
    ui.Path polyline(List<(double, double)> points, {bool close = false}) {
      final path = ui.Path()..moveTo(points[0].$1, points[0].$2);
      for (final (x, y) in points.skip(1)) {
        path.lineTo(x, y);
      }
      if (close) {
        path.close();
      }
      return path;
    }

    test("a fill's ribbon comes first, 6 floats a vertex, in its color", () {
      final m = glowing([square], const [fill], radius10);
      checkWellFormed(m);
      expect(m.vertexFloats, 6);
      expect(m.vertices.length, 6 * m.vertexCount);
      expect(m.paths, hasLength(2));
      expect(m.paths[0].paint, MeshPaint.color);
      expect(m.paths[0].color, [1, 0, 0, 1]);
      expect(m.paths[0].halfWidth, 0);
      final ribbon = glowVertices(m, 0);
      expect(ribbon.map((v) => v.$3).toSet(), {0, 1});
      for (final (x, y, glow) in ribbon) {
        if (glow == 1) {
          expect(
            near((x, y), const [(20, 20), (80, 20), (80, 80), (20, 80)]),
            isTrue,
          );
        }
      }
      expect(glowVertices(m, 1).map((v) => v.$3).toSet(), {1});
      final i = m.indices as List<int>, v = m.vertices;
      for (var k = 0; k < m.paths[0].indexCount; k++) {
        expect([v[i[k] * 6 + 3], v[i[k] * 6 + 4]], [0, 0], reason: 'offsets');
      }
    });

    test("the draws' own triangles and offsets are those without a glow", () {
      final x = ui.Path()
        ..moveTo(0, 0)
        ..lineTo(100, 100)
        ..moveTo(0, 100)
        ..lineTo(100, 0);
      final cases = <(List<ui.Path>, List<PathDraw>, int)>[
        ([square], const [fill], 1),
        ([square], const [stroked], 1),
        (
          [square, line],
          const [
            PathDraw(path: 1, color: blue, strokeWidth: 4),
            fill,
            PathDraw(path: 0, color: red, hairline: true),
          ],
          2,
        ),
        ([x], const [PathDraw(path: 0, color: red, strokeWidth: 10)], 1),
      ];
      for (final (paths, draws, halos) in cases) {
        final plain = glowing(paths, draws, null);
        final lit = glowing(paths, draws, radius10);
        checkWellFormed(lit);
        // Past the halos, only a core has a glow other than 1.
        final own = [
          for (var p = halos; p < lit.paths.length; p++)
            if (glowVertices(lit, p).every((v) => v.$3 == 1)) p,
        ];
        expect(own, hasLength(plain.paths.length));
        final f = plain.vertexFloats;
        for (var p = 0; p < plain.paths.length; p++) {
          final a = plain.paths[p], b = lit.paths[own[p]];
          expect(triangles(lit, own[p]), triangles(plain, p));
          expect(b.color, a.color);
          expect(b.halfWidth, a.halfWidth);
          final ia = plain.indices as List<int>, ib = lit.indices as List<int>;
          for (var k = 0; f == 5 && k < a.indexCount; k++) {
            final va = ia[a.indexBegin + k] * 5, vb = ib[b.indexBegin + k] * 6;
            expect(
              [lit.vertices[vb + 3], lit.vertices[vb + 4]],
              [plain.vertices[va + 3], plain.vertices[va + 4]],
            );
          }
        }
      }
    });

    test('without one, or of no radius or strength, a mesh is as before', () {
      for (final glow in const [
        null,
        Glow(radius: 0),
        Glow(radius: 10, strength: 0),
        Glow(radius: double.nan),
      ]) {
        final filled = glowing([square], const [fill], glow);
        expect([filled.vertexFloats, filled.paths.length], [3, 1]);
        expect(filled.isOpaque, isTrue);
        final stroke_ = glowing([line], const [stroked], glow);
        expect([stroke_.vertexFloats, stroke_.paths.length], [5, 1]);
      }
    });

    test('one ribbon per path drawn, first in both lists of indices', () {
      final x = ui.Path()
        ..moveTo(0, 0)
        ..lineTo(100, 100)
        ..moveTo(0, 100)
        ..lineTo(100, 0);
      final m = glowing(
        [x, square, line, line],
        const [
          PathDraw(path: 0, color: red, strokeWidth: 10),
          PathDraw(path: 1, color: red),
          PathDraw(path: 1, color: blue, strokeWidth: 2),
          // Paints nothing, and path 3 isn't drawn.
          PathDraw(path: 2, color: 0x00FF0000),
        ],
        radius10,
      );
      checkWellFormed(m);
      // 2 halos, 3 draws and the 2 strokes' cores.
      expect(m.paths, hasLength(2 + 3 + 2));
      expect(m.paths[0].color, [1, 0, 0, 1]);
      expect(m.paths[1].color, [0, 0, 1, 1], reason: 'its last draw');
      final a = m.indices as List<int>, b = m.stripIndices! as List<int>;
      final ribbons = m.paths[2].indexBegin;
      expect(ribbons, greaterThan(0));
      expect(b.sublist(0, ribbons), a.sublist(0, ribbons));
    });

    test('a mesh with a glow is never opaque', () {
      expect(glowing([square], const [fill], null).isOpaque, isTrue);
      expect(glowing([square], const [fill], radius10).isOpaque, isFalse);
    });

    test('its color and strength, premultiplied', () {
      List<double> color(Glow glow) =>
          glowing([square], const [fill], glow).paths[0].color;
      expect(color(const Glow(radius: 5, strength: 0.5)), [0.5, 0, 0, 0.5]);
      expect(color(const Glow(radius: 5, color: blue)), [0, 0, 1, 1]);
      expect(color(const Glow(radius: 5, strength: 0.5, color: blue)), [
        0,
        0,
        0.5,
        0.5,
      ]);
      expect(color(const Glow(radius: 5, strength: 7)), [1, 0, 0, 1]);
    });

    test('the bounds grow with the ribbon, and the SVG bounds stay', () {
      final m = glowing([square], const [fill], radius10);
      expect(boundsOf(m), [10, 10, 90, 90]);
      expect([m.svgBounds.ux, m.svgBounds.uy], [100, 100]);
      final s = glowing([square], const [stroked], radius10);
      expect(boundsOf(s), [10, 10, 90, 90]);
    });

    test("a line's caps are half discs, and nothing overlaps", () {
      final m = glowing([line], const [stroked], radius10);
      checkWellFormed(m);
      expect(boundsOf(m), [0, 40, 100, 60]);
      // Its 2 points, plus 7 per cap, on its half disc's arc of 6 steps.
      expect(m.paths[0].indexCount ~/ 3, 2 * 6 + 2 * 2);
      expect(glowVertices(m, 0), hasLength(2 + 2 * 7));
      // 2 sides of 80 by 10, and half of a regular 12-gon at each end.
      expect(area(m), closeTo(1600 + 300, 1e-2));
      expect(maxCoverage(m), 1);
    });

    test('a closed stroke has both sides, an inner and an outer one', () {
      final m = glowing([square], const [stroked], radius10);
      checkWellFormed(m);
      // The points, then the outer corners' arcs and the inner miters.
      expect(glowVertices(m, 0), hasLength(4 + 4 * 4 + 4));
      expect(m.paths[0].indexCount ~/ 3, 4 * 3 + 2 * 4 + 2 * 4);
      expect(maxCoverage(m), 1);
      expect(coverage(m, 50, 50), 0);
      expect(coverage(m, 50, 25), 1);
      expect(coverage(m, 50, 15), 1);
      expect(coverage(m, 50, 5), 0);
    });

    test('round joins have steps of 30°, on the radius', () {
      final edge = ribbonEdge(glowing([square], const [fill], radius10), 0);
      expect(edge, hasLength(4 * 4));
      for (final degrees in const [0.0, 30.0, 60.0, 90.0]) {
        final a = degrees * math.pi / 180;
        expect(
          near((80 + 10 * math.cos(a), 20 - 10 * math.sin(a)), edge),
          isTrue,
        );
      }
    });

    test('a turn of at most a step is a miter, on the outer side too', () {
      Mesh turned(double degrees) {
        final a = degrees * math.pi / 180;
        return glowing(
          [
            polyline([
              (0, 50),
              (50, 50),
              (50 + 50 * math.cos(a), 50 + 50 * math.sin(a)),
            ]),
          ],
          const [stroked],
          radius10,
        );
      }

      // 3 points, 2 caps of 7, and a miter on each side. Past one step, the
      // outer side gets an arc of 2 steps instead.
      expect(glowVertices(turned(29), 0), hasLength(3 + 2 * 7 + 2));
      expect(glowVertices(turned(31), 0), hasLength(3 + 2 * 7 + 1 + 3));
    });

    test('an inner corner is mitered while within half of each segment', () {
      ui.Path corner(double second) =>
          polyline([(0, 50), (50, 50), (50, 50 + second)]);
      List<(double, double)> edge(double second) =>
          ribbonEdge(glowing([corner(second)], const [stroked], radius10), 0);
      // At a right angle, the inner miter 10 out lies 10 along each segment.
      for (final fits in [40.0, 20.0]) {
        expect(near((40, 60), edge(fits)), isTrue);
        expect(near((50, 60), edge(fits)), isFalse);
        expect(near((40, 50), edge(fits)), isFalse);
      }
      expect(near((40, 60), edge(19)), isFalse);
      expect(near((50, 60), edge(19)), isTrue);
      expect(near((40, 50), edge(19)), isTrue);
    });

    test('a fill glows outward, whatever its winding', () {
      final reversed = polyline(const [
        (20, 20),
        (20, 80),
        (80, 80),
        (80, 20),
      ], close: true);
      for (final path in [square, reversed]) {
        final m = glowing([path], const [fill], radius10);
        checkWellFormed(m);
        expect(glowVertices(m, 0), hasLength(4 + 4 * 4));
        expect(m.paths[0].indexCount ~/ 3, 4 * 3 + 4 * 2);
        expect(boundsOf(m), [10, 10, 90, 90]);
        expect(maxCoverage(m), 1);
        expect(coverage(m, 50, 50), 0);
        expect(coverage(m, 15, 50), 1);
        expect(coverage(m, 50, 85), 1);
        expect(coverage(m, 5, 50), 0);
      }
    });

    test("a hole's ribbon is inside the fill", () {
      final path = ui.Path()
        ..addRect(const ui.Rect.fromLTRB(10, 10, 90, 90))
        ..addRect(const ui.Rect.fromLTRB(30, 30, 70, 70));
      final m = glowing([path], const [fill], const Glow(radius: 5));
      expect(coverage(m, 50, 50), 0);
      expect(coverage(m, 27, 50), 1);
    });

    test('a fill closes open contours, also those back at their start', () {
      const points = [(20.0, 20.0), (80.0, 20.0), (80.0, 80.0), (20.0, 80.0)];
      for (final open in [
        points,
        [...points, points[0]],
      ]) {
        final m = glowing([polyline(open)], const [fill], radius10);
        checkWellFormed(m);
        expect(coverage(m, 15, 50), 1, reason: 'the closing edge');
        expect(glowVertices(m, 0), hasLength(4 + 4 * 4));
      }
    });

    test('a contour of no area has no outside, and one of 2 points none', () {
      for (final path in [
        line,
        polyline(const [(10, 50), (50, 50), (90, 50)]),
      ]) {
        final m = glowing([path], const [fill], radius10);
        expect(m.paths, isEmpty);
      }
    });

    test('a turn back is a half disc ahead, once', () {
      final m = glowing(
        [
          polyline(const [(10, 50), (90, 50), (30, 50)]),
        ],
        const [stroked],
        radius10,
      );
      checkWellFormed(m);
      expect(coverage(m, 95, 50), 1);
      expect(m.bounds.ux, 100);
      // The ribbon walks there and back over 4 stops: the 3 points, then the
      // turn again. So it has 3 points, 3 half discs of 7 points and 6
      // triangles each, and a quad per stop. The turn's second stop has no
      // half disc of its own.
      expect(glowVertices(m, 0), hasLength(3 + 3 * 7));
      expect(m.paths[0].indexCount ~/ 3, 3 * 6 + 4 * 2);
    });

    group('in line widths', () {
      const three = Glow(radius: 3, inWidths: true);

      test("a stroke's radius is that many times its width, the widest", () {
        final m = glowing(
          [line],
          const [
            PathDraw(path: 0, color: red, strokeWidth: 2),
            PathDraw(path: 0, color: red, strokeWidth: 4),
            PathDraw(path: 0, color: red, strokeWidth: 3),
          ],
          three,
        );
        expect(boundsOf(m), [-2, 38, 102, 62]);
      });

      test("a fill's is that many times the shorter edge at each point", () {
        final m = glowing(
          [
            polyline(const [(0, 0), (100, 1), (100, 3), (0, 4)], close: true),
          ],
          const [fill],
          three,
        );
        checkWellFormed(m);
        final b = m.bounds;
        expect(b.lx, closeTo(-12, 1e-2), reason: '3 x 4 at the wide end');
        expect(b.ux, closeTo(106, 1e-2), reason: '3 x 2 at the narrow end');
        expect(b.ly, closeTo(-12, 1e-2));
        expect(b.uy, closeTo(16, 1e-2));
      });

      test(
        "a hairline has none, but has one of a radius in the paths' units",
        () {
          const hairline = [PathDraw(path: 0, color: red, hairline: true)];
          final none = glowing([line], hairline, three);
          expect(none.paths, hasLength(1));
          expect(none.vertexFloats, 6);
          final some = glowing([line], hairline, radius10);
          expect(some.paths, hasLength(2));
          expect(boundsOf(some), [0, 40, 100, 60]);
        },
      );
    });

    test("a stroke's halo reaches 1 at the stroke's edge", () {
      final m = glowing([line], const [stroked], radius10);
      // The stroke's edge, a half width of 1 from the polyline, lies 9/10 of
      // the way in from the ribbon's outer edge, whose glow is 0.
      final glows = glowVertices(m, 0).map((v) => v.$3).toSet();
      expect(glows, hasLength(2));
      expect(glows.reduce(math.max), closeTo(10 / 9, 1e-6));
      expect(glows.reduce(math.min), 0);
    });

    test("a stroke's quads have no fans, even where a miter lengthens one", () {
      final m = glowing(
        [
          polyline(const [(0, 50), (50, 50), (50, 90)]),
        ],
        const [stroked],
        radius10,
      );
      // Its vertices lie only on the polyline and on the outer edge.
      expect(glowVertices(m, 0).map((v) => v.$3).toSet(), hasLength(2));
    });

    test('a quad that tapers is a fan around its centre, of its mean glow', () {
      final m = glowing(
        [
          polyline(const [(0, 0), (100, 1), (100, 3), (0, 4)], close: true),
        ],
        const [fill],
        const Glow(radius: 3, inWidths: true),
      );
      checkWellFormed(m);
      // The 2 long sides, whose radius tapers from 12 at the wide end to 6
      // at the narrow one.
      final centres = glowVertices(m, 0).where((v) => v.$3 == 0.5);
      expect(centres, hasLength(2));
      expect(
        glowVertices(
          glowing([line], const [stroked], radius10),
          0,
        ).where((v) => v.$3 == 0.5),
        isEmpty,
        reason: "a stroke's radius doesn't change",
      );
    });

    test('only a halo is marked as one', () {
      expect(
        glowing([line], const [stroked], radius10).paths.map((p) => p.isHalo),
        [true, false, false],
      );
      expect(
        glowing([line], const [stroked], null).paths.map((p) => p.isHalo),
        [false],
      );
    });

    group('core', () {
      const widths = Glow(radius: 3, inWidths: true);

      test("a stroke's is over its draw, 2 on its line and 1 at its edge", () {
        final m = glowing([line], const [stroked], radius10);
        checkWellFormed(m);
        expect(m.paths, hasLength(3), reason: 'the halo, the draw, the core');
        expect(m.paths[2].paint, MeshPaint.color);
        expect(m.paths[2].halfWidth, 0);
        final core = glowVertices(m, 2);
        expect(core.map((v) => v.$3).toSet(), {1, 2});
        for (final (_, y, glow) in core) {
          if (glow == 2) {
            expect(y, 50);
          }
          expect((y - 50).abs(), lessThanOrEqualTo(1));
        }
        expect(coverage(m, 50, 50.5, 2), 1);
        expect(coverage(m, 50, 52, 2), 0);
        final i = m.indices as List<int>, v = m.vertices;
        for (var k = 0; k < m.paths[2].indexCount; k++) {
          final at = m.paths[2].indexBegin + k;
          expect(
            [v[i[at] * 6 + 3], v[i[at] * 6 + 4]],
            [0, 0],
            reason: 'offsets',
          );
        }
      });

      test("it has its draw's color, whatever the halo's", () {
        final m = glowing(
          [line],
          const [stroked],
          const Glow(radius: 10, strength: 0.5, color: blue),
        );
        expect(m.paths[0].color, [0, 0, 0.5, 0.5]);
        expect(m.paths[2].color, [1, 0, 0, 1]);
      });

      test('it follows its draw, so that a later draw paints over it', () {
        final m = glowing(
          [square, line],
          const [
            PathDraw(path: 0, color: red, strokeWidth: 2),
            PathDraw(path: 1, color: blue, strokeWidth: 2),
          ],
          radius10,
        );
        checkWellFormed(m);
        expect(m.paths, hasLength(2 + 2 * 2));
        expect(glowVertices(m, 2).map((v) => v.$3).toSet(), {1});
        expect(glowVertices(m, 3).map((v) => v.$3).toSet(), {1, 2});
        expect(m.paths[3].color, [1, 0, 0, 1]);
        expect(glowVertices(m, 4).map((v) => v.$3).toSet(), {1});
        expect(glowVertices(m, 5).map((v) => v.$3).toSet(), {1, 2});
        expect(m.paths[5].color, [0, 0, 1, 1]);
      });

      test('it is in both lists of indices', () {
        final x = ui.Path()
          ..moveTo(0, 0)
          ..lineTo(100, 100)
          ..moveTo(0, 100)
          ..lineTo(100, 0);
        final m = glowing(
          [x],
          const [PathDraw(path: 0, color: red, strokeWidth: 10)],
          radius10,
        );
        checkWellFormed(m);
        final core = m.paths[2];
        final a = m.indices as List<int>, b = m.stripIndices! as List<int>;
        expect(
          b.sublist(b.length - core.indexCount),
          a.sublist(core.indexBegin, core.indexBegin + core.indexCount),
        );
      });

      test('a hairline has none', () {
        final m = glowing(
          [line],
          const [PathDraw(path: 0, color: red, hairline: true)],
          radius10,
        );
        expect(m.paths, hasLength(2));
      });

      test("a fill has one only in line widths, to its shape's middle", () {
        expect(glowing([square], const [fill], radius10).paths, hasLength(2));
        final m = glowing([square], const [fill], widths);
        checkWellFormed(m);
        expect(m.paths, hasLength(3));
        expect(m.paths[2].color, [1, 0, 0, 1]);
        final core = glowVertices(m, 2);
        expect(core, hasLength(4 + 1));
        for (final (x, y, glow) in core) {
          expect((x, y), glow == 2 ? (50, 50) : isNot((50, 50)));
        }
        expect(area(m, 2), closeTo(60 * 60, 1e-2));
      });

      test('a thin fill peaks along its middle, whatever its winding', () {
        for (final points in const [
          [(0.0, 0.0), (100.0, 0.0), (100.0, 4.0), (0.0, 4.0)],
          [(0.0, 0.0), (0.0, 4.0), (100.0, 4.0), (100.0, 0.0)],
        ]) {
          final m = glowing(
            [polyline(points, close: true)],
            const [fill],
            widths,
          );
          final peaks = [
            for (final (x, y, glow) in glowVertices(m, 2))
              if (glow == 2) (x, y),
          ];
          expect(peaks, hasLength(2));
          expect(near((2, 2), peaks), isTrue);
          expect(near((98, 2), peaks), isTrue);
        }
      });

      test('a fill of a path that a draw strokes has none', () {
        final m = glowing([square], const [fill, stroked], widths);
        checkWellFormed(m);
        expect(m.paths, hasLength(4), reason: 'halo, fill, stroke, its core');
        expect(glowVertices(m, 1).map((v) => v.$3).toSet(), {1});
        expect(glowVertices(m, 2).map((v) => v.$3).toSet(), {1});
        expect(glowVertices(m, 3).map((v) => v.$3).toSet(), {1, 2});
      });

      test('nested contours have none, unlike ones side by side', () {
        final holed = ui.Path()
          ..addRect(const ui.Rect.fromLTRB(10, 10, 90, 90))
          ..addRect(const ui.Rect.fromLTRB(30, 30, 70, 70));
        expect(glowing([holed], const [fill], widths).paths, hasLength(2));
        final apart = ui.Path()
          ..addRect(const ui.Rect.fromLTRB(10, 10, 40, 20))
          ..addRect(const ui.Rect.fromLTRB(50, 10, 80, 20));
        final m = glowing([apart], const [fill], widths);
        expect(m.paths, hasLength(3));
        expect(coverage(m, 25, 15, 2), 1);
        expect(coverage(m, 65, 15, 2), 1);
      });

      test('contours that are nested only by their bounds have one', () {
        final path = polyline(const [
          (0, 0),
          (100, 0),
          (100, 10),
          (10, 10),
          (10, 100),
          (0, 100),
        ], close: true)..addRect(const ui.Rect.fromLTRB(50, 50, 60, 60));
        final m = glowing([path], const [fill], widths);
        expect(m.paths, hasLength(3));
        expect(coverage(m, 55, 55, 2), 1);
      });
    });
  });

  group('paints', () {
    const rect = '<rect width="100" height="100" fill="url(#g)"/>';

    test("a linear gradient's transform & stops", () {
      final m = mesh(
        '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" '
        'y1="0" x2="100" y2="0"><stop offset="0" stop-color="#f00"/>'
        '<stop offset="1" stop-color="#00f" stop-opacity="0.5"/>'
        '</linearGradient></defs>$rect',
      );
      final p = m.paths.single;
      expect(p.paint, MeshPaint.linearGradient);
      for (final (x, y, t) in [
        (0.0, 0.0, 0.0),
        (100.0, 0.0, 1.0),
        (50.0, 77.0, 0.5),
      ]) {
        expect(apply(p.gradient, x, y).$2, closeTo(t, 1e-5));
      }
      expect(p.stopCount, 2);
      final s = m.stops.sublist(p.stopBegin * 5, (p.stopBegin + 2) * 5);
      expect(s, [0, 1, 0, 0, 1, 1, 0, 0, 1, closeTo(0.5, 1e-2)]);
    });

    test("a radial gradient's transform", () {
      final m = mesh(
        '<defs><radialGradient id="g" gradientUnits="userSpaceOnUse" cx="50" '
        'cy="50" r="25"><stop offset="0" stop-color="#f00"/>'
        '<stop offset="1" stop-color="#00f"/></radialGradient></defs>$rect',
      );
      final p = m.paths.single;
      expect(p.paint, MeshPaint.radialGradient);
      final (x, y) = apply(p.gradient, 75, 50);
      final (cx, cy) = apply(p.gradient, 50, 50);
      expect(math.sqrt(x * x + y * y), closeTo(1, 1e-5));
      expect(math.sqrt(cx * cx + cy * cy), closeTo(0, 1e-5));
    });

    test("stops' offsets never decrease, and a gradient of no length is its "
        "last stop's color", () {
      final m = mesh(
        '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" '
        'y1="0" x2="100" y2="0"><stop offset="0.6" stop-color="#f00"/>'
        '<stop offset="0.2" stop-color="#00f"/></linearGradient>'
        '<linearGradient id="h" gradientUnits="userSpaceOnUse" x1="5" y1="5" '
        'x2="5" y2="5"><stop offset="0" stop-color="#f00"/>'
        '<stop offset="1" stop-color="#0f0"/></linearGradient></defs>'
        '$rect<rect width="10" height="10" fill="url(#h)"/>',
      );
      // NanoSVG sorts them, while SVG would raise the second to 0.6.
      final p = m.paths[0];
      expect(m.stops[p.stopBegin * 5], closeTo(0.2, 1e-6));
      expect(m.stops[(p.stopBegin + 1) * 5], closeTo(0.6, 1e-6));
      expect(m.paths[1].paint, MeshPaint.color);
      expect(m.paths[1].color, [0, 1, 0, 1]);
    });

    test("a mesh is opaque where its colors' and stops' alpha is 1", () {
      String gradient(String opacity) =>
          '<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/>'
          '<stop offset="1" stop-color="#00f" stop-opacity="$opacity"/>'
          '</linearGradient></defs>$rect';
      const square = '<rect width="10" height="10" fill="#f00" stroke="#00f"';
      for (final (body, opaque) in [
        ('$square/>', true),
        ('$square fill-opacity="0.5"/>', false),
        ('$square stroke-opacity="0.5"/>', false),
        ('$square opacity="0.9"/>', false),
        (gradient('1'), true),
        (gradient('0.5'), false),
      ]) {
        expect(mesh(body).isOpaque, opaque, reason: body);
      }
    });

    test('fills paint before strokes, and invisible paths are skipped', () {
      final m = mesh(
        '<rect x="10" y="10" width="20" height="20" fill="#f00" stroke="#00f" '
        'stroke-width="2"/>'
        '<rect x="40" y="10" width="20" height="20" display="none"/>'
        '<rect x="70" y="10" width="20" height="20" fill-opacity="0" '
        'stroke="#0f0"/>',
      );
      checkWellFormed(m);
      expect(
        m.paths.map(
          (p) => p.color[0] > 0
              ? 'r'
              : p.color[1] > 0
              ? 'g'
              : 'b',
        ),
        ['r', 'b', 'g'],
      );
    });

    test('clip paths are ignored, as by the canvas renderer', () {
      final m = mesh(
        '<clipPath id="c"><rect width="10" height="10"/></clipPath>'
        '<rect width="50" height="50" clip-path="url(#c)"/>',
      );
      expect(m.paths, hasLength(1));
      expect(area(m), closeTo(2500, 1e-2));
    });
  });

  group('import', () {
    test('no maxSize throws, and what NanoSVG finds no shapes in is empty', () {
      expect(
        () => mesh('<rect width="1" height="1"/>', maxSize: 0),
        throwsArgumentError,
      );
      for (final empty in [
        mesh(''),
        Mesh.fromSvgBytes(Uint8List.fromList('nope'.codeUnits), maxSize: 100),
      ]) {
        expect(
          [empty.vertexCount, empty.indexCount, empty.paths.length],
          [0, 0, 0],
        );
      }
    });

    test('indices are u32 past 0xFFFF vertices', () {
      String n(double v) => (50 + 40 * v).toStringAsFixed(4);
      final points = [
        for (var i = 0; i < 70000; i++)
          '${n(math.cos(i * 2 * math.pi / 70000))},'
              '${n(math.sin(i * 2 * math.pi / 70000))}',
      ].join(' ');
      final m = mesh('<polygon points="$points"/>');
      checkWellFormed(m);
      expect(m.vertexCount, greaterThan(0xFFFF));
      expect(m.indices, isA<Uint32List>());
    });

    test('the tiger and the test SVGs, timed', () {
      final files = [
        File('example/assets/tiger/tiger.svg'),
        ...[
          for (final e in Directory('test/svgs').listSync())
            if (e is File && e.path.endsWith('.svg')) e,
        ]..sort((a, b) => a.path.compareTo(b.path)),
      ];
      for (final file in files) {
        final bytes = file.readAsBytesSync(), watch = Stopwatch()..start();
        final m = Mesh.fromSvgBytes(bytes, maxSize: 1620);
        final ms = watch.elapsedMicroseconds / 1000;
        checkWellFormed(m);
        expect(m.paths, isNotEmpty);
        final bytesUsed =
            m.vertices.lengthInBytes +
            m.indices.lengthInBytes +
            (m.stripIndices?.lengthInBytes ?? 0);
        print(
          '${file.uri.pathSegments.last}: ${m.paths.length} paths, '
          '${m.vertexCount} vertices, ${m.indexCount ~/ 3} triangles, '
          '$bytesUsed bytes, ${ms.toStringAsFixed(1)} ms',
        );
      }
    });
  });
}
