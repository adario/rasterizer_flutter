// Checks how PathContours flattens Flutter paths' contours to polylines,
// from this package's folder:
//   flutter test test/path_contours_test.dart
//
// The polylines must stay within the tolerance of their contours, in any
// units. They must also keep the contours' directions, holes, corners and
// open ends.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/paths/path_contours.dart';

/// A flattened contour: its points, and whether it's closed.
typedef Polyline = ({List<ui.Offset> points, bool closed});

/// The polylines of [contours], one list per path.
List<List<Polyline>> unpack(PathContours contours) {
  final paths = <List<Polyline>>[];
  var contour = 0;
  var point = 0;
  for (final count in contours.contourCounts) {
    final polylines = <Polyline>[];
    for (var i = 0; i < count; i++, contour++) {
      final points = <ui.Offset>[];
      for (var j = 0; j < contours.pointCounts[contour]; j++, point++) {
        points.add(
          ui.Offset(contours.points[2 * point], contours.points[2 * point + 1]),
        );
      }
      polylines.add((points: points, closed: contours.closed[contour] == 1));
    }
    paths.add(polylines);
  }
  return paths;
}

/// The polylines of [path], flattened to [tolerance].
List<Polyline> flatten(ui.Path path, double tolerance) =>
    unpack(PathContours([path], tolerance: tolerance)).single;

/// The tolerance for paths [side] units long, drawn at most [maxSize] pixels
/// long: 1/4 of a pixel, as the mesh renderer uses.
double toleranceFor(double side, double maxSize) => 0.25 * side / maxSize;

/// The signed area of [polyline], positive if it goes clockwise with y down.
double area(List<ui.Offset> polyline) {
  var sum = 0.0;
  for (var i = 0; i < polyline.length; i++) {
    final a = polyline[i];
    final b = polyline[(i + 1) % polyline.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}

/// Points every [step] along each of [path]'s contours, ends included.
List<List<ui.Offset>> dense(ui.Path path, double step) => [
  for (final metric in path.computeMetrics())
    [
      for (var d = 0.0; d < metric.length; d += step)
        metric.getTangentForOffset(d)!.position,
      metric.getTangentForOffset(metric.length)!.position,
    ],
];

double distanceToSegment(ui.Offset p, ui.Offset a, ui.Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  final t = lengthSquared == 0
      ? 0.0
      : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
          0.0,
          1.0,
        );
  return (p - (a + ab * t)).distance;
}

double distanceToPolyline(ui.Offset p, List<ui.Offset> points, bool closed) {
  final segments = closed ? points.length : points.length - 1;
  var best = double.infinity;
  for (var i = 0; i < segments; i++) {
    best = math.min(
      best,
      distanceToSegment(p, points[i], points[(i + 1) % points.length]),
    );
  }
  return best;
}

/// How far [path]'s contours and [polylines] get from each other.
///
/// It measures from points every [step] along [path] to the polylines, and
/// from points along the polylines' segments back to those points.
double deviation(ui.Path path, List<Polyline> polylines, double step) {
  final samples = dense(path, step);
  expect(polylines, hasLength(samples.length));
  var worst = 0.0;
  for (var i = 0; i < samples.length; i++) {
    final (:points, :closed) = polylines[i];
    for (final sample in samples[i]) {
      worst = math.max(worst, distanceToPolyline(sample, points, closed));
    }
    final segments = closed ? points.length : points.length - 1;
    for (var s = 0; s < segments; s++) {
      final a = points[s];
      final b = points[(s + 1) % points.length];
      for (var t = 0.0; t <= 1; t += 0.25) {
        final p = ui.Offset.lerp(a, b, t)!;
        worst = math.max(worst, distanceToPolyline(p, samples[i], false));
      }
    }
  }
  return worst;
}

/// A path of [polylines], filled by [fillType].
ui.Path polylinePath(List<Polyline> polylines, ui.PathFillType fillType) {
  final path = ui.Path()..fillType = fillType;
  for (final (:points, :closed) in polylines) {
    path.addPolygon(points, closed);
  }
  return path;
}

/// The alpha values of [path], filled at [scale] pixels per unit into a
/// square [size] pixels wide.
Future<Uint8List> fill(ui.Path path, double scale, int size) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..scale(scale)
    ..drawPath(path, ui.Paint()..color = const ui.Color(0xff000000));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData();
  image.dispose();
  final rgba = data!.buffer.asUint8List();
  return Uint8List.fromList([for (var i = 3; i < rgba.length; i += 4) rgba[i]]);
}

void main() {
  // Shapes 3 units wide, as Forge2D bodies are, drawn at most 512 pixels
  // wide.
  const side = 3.0;
  final tolerance = toleranceFor(side, 512);
  const center = ui.Offset(1.5, 1.5);
  final circle = ui.Path()
    ..addOval(ui.Rect.fromCircle(center: center, radius: 1.5));
  final rrect = ui.Path()
    ..addRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0.5, 3, 2),
        const ui.Radius.circular(0.4),
      ),
    );
  final starVertices = [
    for (var i = 0; i < 10; i++)
      center +
          ui.Offset.fromDirection(
            -math.pi / 2 + i * math.pi / 5,
            i.isEven ? 1.5 : 0.6,
          ),
  ];
  final star = ui.Path()..addPolygon(starVertices, true);
  // A circle drawn the other way, counterclockwise.
  final hole = ui.Path()
    ..moveTo(2.2, 1.5)
    ..arcToPoint(
      const ui.Offset(0.8, 1.5),
      radius: const ui.Radius.circular(0.7),
      clockwise: false,
    )
    ..arcToPoint(
      const ui.Offset(2.2, 1.5),
      radius: const ui.Radius.circular(0.7),
      clockwise: false,
    )
    ..close();
  final ring = ui.Path()
    ..addPath(circle, ui.Offset.zero)
    ..addPath(hole, ui.Offset.zero);
  final evenOdd = ui.Path()
    ..fillType = ui.PathFillType.evenOdd
    ..addOval(const ui.Rect.fromLTWH(0, 0, 2, 2))
    ..addOval(const ui.Rect.fromLTWH(1, 1, 2, 2));
  final arc = ui.Path()..addArc(const ui.Rect.fromLTWH(0, 0, 3, 3), 0, 4);
  final wave = ui.Path()
    ..moveTo(0, 1.5)
    ..cubicTo(1, -1, 2, 4, 3, 1.5);
  final difference = ui.Path.combine(
    ui.PathOperation.difference,
    rrect,
    circle,
  );
  final shapes = {
    'circle': circle,
    'rrect': rrect,
    'star': star,
    'ring': ring,
    'evenOdd': evenOdd,
    'arc': arc,
    'wave': wave,
    'difference': difference,
  };

  test('throws for a tolerance that is not a positive number', () {
    for (final tolerance in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => PathContours([circle], tolerance: tolerance),
        throwsArgumentError,
      );
    }
  });

  test('counts each path\'s contours and their points', () {
    final contours = PathContours([
      star,
      ui.Path(),
      ring,
    ], tolerance: tolerance);
    expect(contours.contourCounts, [1, 0, 2]);
    expect(contours.pointCounts, hasLength(3));
    expect(contours.closed, [1, 1, 1]);
    expect(contours.pointCounts.first, 10);
    final points = contours.pointCounts.fold(0, (sum, count) => sum + count);
    expect(contours.points, hasLength(2 * points));
  });

  test('leaves out contours without a length', () {
    final path = ui.Path()
      ..moveTo(1, 1)
      ..lineTo(1, 1)
      ..addPath(star, ui.Offset.zero)
      ..moveTo(2, 2);
    expect(flatten(path, tolerance), hasLength(1));
    expect(flatten(ui.Path()..moveTo(1, 1), tolerance), isEmpty);
  });

  test('keeps corners exactly', () {
    final [(:points, :closed)] = flatten(star, tolerance);
    expect(closed, isTrue);
    expect(points, hasLength(starVertices.length));
    for (final (i, point) in points.indexed) {
      expect((point - starVertices[i]).distance, lessThan(1e-5));
    }

    final zigzag = [
      const ui.Offset(0, 0),
      const ui.Offset(2, 0.5),
      const ui.Offset(1, 2),
      const ui.Offset(3, 3),
    ];
    final [open] = flatten(ui.Path()..addPolygon(zigzag, false), tolerance);
    expect(open.closed, isFalse);
    expect(open.points, hasLength(zigzag.length));
    for (final (i, point) in open.points.indexed) {
      expect((point - zigzag[i]).distance, lessThan(1e-5));
    }
  });

  test('keeps directions, so holes stay holes', () {
    for (final MapEntry(key: name, value: path) in shapes.entries) {
      final polylines = flatten(path, tolerance);
      final samples = dense(path, tolerance);
      final lengths = [
        for (final metric in path.computeMetrics()) metric.length,
      ];
      // Each polyline stays within the tolerance of its contour, so their
      // signed areas are close. A reversed polyline would flip the sign,
      // unless the contour has no area.
      for (final (i, (:points, closed: _)) in polylines.indexed) {
        expect(
          area(points),
          closeTo(area(samples[i]), tolerance * lengths[i]),
          reason: '$name, contour $i',
        );
      }
    }
    final [outer, inner] = flatten(ring, tolerance);
    expect(area(outer.points).sign, -area(inner.points).sign);
  });

  test('keeps open contours open', () {
    final [(:points, :closed)] = flatten(arc, tolerance);
    expect(closed, isFalse);
    final metric = arc.computeMetrics().single;
    expect(points.first, metric.getTangentForOffset(0)!.position);
    expect(
      (points.last - metric.getTangentForOffset(metric.length)!.position)
          .distance,
      lessThan(1e-5),
    );
  });

  test('keeps contours that end at their start open', () {
    final corners = [
      const ui.Offset(0, 0),
      const ui.Offset(3, 0),
      const ui.Offset(3, 3),
      const ui.Offset(0, 0),
    ];
    final [open] = flatten(ui.Path()..addPolygon(corners, false), tolerance);
    expect(open.closed, isFalse);
    expect(open.points, corners);
    final [closed] = flatten(ui.Path()..addPolygon(corners, true), tolerance);
    expect(closed.closed, isTrue);
    expect(closed.points, corners.take(3));

    final loop = ui.Path()
      ..moveTo(3, 1.5)
      ..arcToPoint(
        const ui.Offset(0, 1.5),
        radius: const ui.Radius.circular(1.5),
      )
      ..arcToPoint(
        const ui.Offset(3, 1.5),
        radius: const ui.Radius.circular(1.5),
      );
    final [(:points, closed: isClosed)] = flatten(loop, tolerance);
    expect(isClosed, isFalse);
    expect(points.first, points.last);
  });

  test('stays within the tolerance', () {
    for (final MapEntry(key: name, value: path) in shapes.entries) {
      // The samples form a polyline too, up to 1/8 of the tolerance off
      // their curves.
      final error = deviation(path, flatten(path, tolerance), tolerance / 4);
      expect(error, lessThanOrEqualTo(1.25 * tolerance), reason: name);
    }
  });

  test('flattens the same in any units', () {
    for (final MapEntry(key: name, value: path) in shapes.entries) {
      final counts = <List<int>>[];
      for (final scale in [0.001, 1.0, 1000.0]) {
        final scaled = path.transform(
          Float64List.fromList([
            scale, 0, 0, 0, //
            0, scale, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
        );
        final polylines = flatten(scaled, tolerance * scale);
        counts.add([
          for (final (:points, closed: _) in polylines) points.length,
        ]);
        final error = deviation(scaled, polylines, tolerance * scale / 4);
        expect(
          error,
          lessThanOrEqualTo(1.25 * tolerance * scale),
          reason: '$name at $scale',
        );
      }
      // Flutter measures a curve's length on a flattening of its own, which
      // is finer in larger units. A circle 3 units wide measures as long as
      // its inscribed square, though the points along it lie on the circle.
      // So larger units can take a few fewer points.
      for (final count in counts) {
        expect(count, hasLength(counts[1].length), reason: name);
        for (final (i, points) in count.indexed) {
          expect(
            points,
            closeTo(counts[1][i], counts[1][i] / 5),
            reason: '$name: $counts',
          );
        }
      }
    }
  });

  test('fills the same pixels', () async {
    const size = 256;
    const scale = size / side;
    final fillTolerance = toleranceFor(side, size.toDouble());
    for (final MapEntry(key: name, value: path) in shapes.entries) {
      final polylines = flatten(path, fillTolerance);
      final expected = await fill(path, scale, size);
      final actual = await fill(
        polylinePath(polylines, path.fillType),
        scale,
        size,
      );
      var differing = 0;
      for (var i = 0; i < expected.length; i++) {
        if ((expected[i] - actual[i]).abs() > 64) {
          differing++;
        }
      }
      // Only antialiased edge pixels may differ.
      expect(differing, lessThan(expected.length * 0.005), reason: name);
    }
  });
}
