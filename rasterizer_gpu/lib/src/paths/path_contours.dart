// Flattens plain paths' contours to polylines for the GPU renderers.
//
// The sampler comes from Flame's `PathMetricExtension.walkContour` and its
// `_ContourSampler` (packages/flame/lib/src/extensions/path.dart, main at
// 8fa5abf04), MIT, © 2021 Blue Fire (THIRD_PARTY_NOTICES.md), with Flame's
// `Offset.distanceToSegmentSquared`. The changes for drawing:
// - It leaves out what only hitboxes' bounds need: the points where a contour
//   turns back horizontally or vertically, and the three vertices that a
//   closed contour always got.
// - A contour is closed only if its metric is. Flame's also took a contour
//   that ends where it starts as closed, and dropped its last point. Drawn
//   open, as Flutter strokes it, that contour lost its last segment.
// - The sampling step is 4 times the tolerance. That kept every path measured
//   within the tolerance, while a coarser step strays past it on some curves.

import 'dart:math' show max, min, sqrt;
import 'dart:typed_data';
import 'dart:ui' show Offset, Path, PathMetric, Tangent;

/// Paths' contours, flattened to polylines within a tolerance.
///
/// The GPU renderers draw them as they draw an SVG's paths. A [Path] doesn't
/// expose its commands, so [Path.computeMetrics] reads its contours back, and
/// a sampler walks them along their tangents. Each contour keeps its
/// direction, so holes stay holes with either fill type. It also keeps its
/// corners, located exactly. An open contour stays open, as a stroke needs,
/// and a fill closes it. Contours without a length are left out, as
/// [Path.computeMetrics] skips them.
final class PathContours._(
  /// The polylines' points, x then y, contour after contour, in the paths'
  /// units. A closed contour's first point isn't repeated at its end.
  final Float32List points,

  /// Each contour's number of points, at least 2.
  final Int32List pointCounts,

  /// 1 for each closed contour, 0 for each open one.
  final Uint8List closed,

  /// Each path's number of contours, in the paths' order.
  final Int32List contourCounts,
) {
  /// Flattens [paths]' contours to within [tolerance] of them, in their units.
  ///
  /// Throws [ArgumentError] if [tolerance] isn't a positive finite number.
  factory PathContours(Iterable<Path> paths, {required double tolerance}) {
    if (!tolerance.isFinite || tolerance <= 0) {
      throw ArgumentError.value(
        tolerance,
        'tolerance',
        'Not a positive number',
      );
    }
    final points = <double>[];
    final pointCounts = <int>[];
    final closed = <int>[];
    final contourCounts = <int>[];
    for (final path in paths) {
      var contours = 0;
      for (final metric in path.computeMetrics()) {
        final (polyline, isClosed) = _flatten(metric, tolerance);
        if (polyline.length < 2) {
          continue;
        }
        for (final point in polyline) {
          points
            ..add(point.dx)
            ..add(point.dy);
        }
        pointCounts.add(polyline.length);
        closed.add(isClosed ? 1 : 0);
        contours++;
      }
      contourCounts.add(contours);
    }
    return PathContours._(
      Float32List.fromList(points),
      Int32List.fromList(pointCounts),
      Uint8List.fromList(closed),
      Int32List.fromList(contourCounts),
    );
  }
}

/// The sampling step, as a multiple of the tolerance.
const _samplingPerTolerance = 4;

/// The most sampling steps in one contour. A longer contour gets a longer
/// step.
const _maxSteps = 1 << 20;

/// [metric]'s contour as a polyline within [tolerance] of it, and whether
/// it's closed.
///
/// The sampler keeps the contour within a sixth of [tolerance] of its samples.
/// The polyline then keeps the corners, and only the samples it needs to stay
/// within [tolerance].
(List<Offset>, bool) _flatten(PathMetric metric, double tolerance) {
  final length = metric.length;
  if (!length.isFinite || length <= 0) {
    return (const [], false);
  }
  final sampling = _samplingPerTolerance * tolerance;
  // A closed contour takes at least three steps, so it stays a polygon however
  // coarse the sampling.
  final step = metric.isClosed
      ? min(max(sampling, length / _maxSteps), length / 3)
      : max(sampling, length / _maxSteps);
  final sampler = _ContourSampler(metric, step, tolerance / 6)..sample();
  final points = _simplify(
    sampler.points,
    sampler.anchors,
    closed: sampler.isClosed,
    tolerance: tolerance,
  );
  return (points, sampler.isClosed);
}

/// Removes the [points] that lie within [tolerance] of the edge that replaces
/// them, extending each edge as far as that allows.
///
/// This needs fewer points than splitting at the farthest point, which halves
/// stretches that would fit in one and a half edges.
///
/// [anchors] holds the ascending indices of the points to keep. Each stretch
/// between two anchors is simplified on its own, the one that wraps around a
/// [closed] contour's end included. An open contour also keeps its ends. A
/// closed one with fewer than two anchors keeps its anchor, or its first
/// point, and the point farthest from it.
List<Offset> _simplify(
  List<Offset> points,
  List<int> anchors, {
  required bool closed,
  required double tolerance,
}) {
  final count = points.length;
  if (count < 3 || tolerance <= 0) {
    return points;
  }
  final fixed = [...anchors];
  if (!closed) {
    if (fixed.isEmpty || fixed.first != 0) {
      fixed.insert(0, 0);
    }
    if (fixed.last != count - 1) {
      fixed.add(count - 1);
    }
  } else if (fixed.length < 2) {
    final origin = fixed.isEmpty ? 0 : fixed.first;
    final farthest = _farthestFrom(points, origin);
    fixed
      ..clear()
      ..add(min(origin, farthest));
    if (farthest != origin) {
      fixed.add(max(origin, farthest));
    }
  }

  final toleranceSquared = tolerance * tolerance;
  final keep = List.filled(count, false);
  for (var i = 0; i < fixed.length; i++) {
    keep[fixed[i]] = true;
    final isLast = i == fixed.length - 1;
    if (isLast && !closed) {
      break;
    }
    final to = isLast ? fixed.first + count : fixed[i + 1];
    var from = fixed[i];
    while (from < to) {
      from = _reach(points, from, to, toleranceSquared);
      keep[from % count] = true;
    }
  }
  return [
    for (var i = 0; i < count; i++)
      if (keep[i]) points[i],
  ];
}

/// The farthest index after [from], up to [to], whose edge from [from] keeps
/// the points between them within the tolerance.
///
/// It doubles the stride until an edge fails, then bisects, so it may miss a
/// farther index that fits. Indices past the end of [points] wrap around, for
/// a closed contour's last stretch.
int _reach(List<Offset> points, int from, int to, double toleranceSquared) {
  var reached = from + 1;
  var failed = -1;
  for (var stride = 2; reached < to; stride *= 2) {
    final candidate = min(from + stride, to);
    if (!_fits(points, from, candidate, toleranceSquared)) {
      failed = candidate;
      break;
    }
    reached = candidate;
  }
  while (failed - reached > 1) {
    final middle = (reached + failed) >> 1;
    if (_fits(points, from, middle, toleranceSquared)) {
      reached = middle;
    } else {
      failed = middle;
    }
  }
  return reached;
}

/// Whether the points between [from] and [to] all lie within the tolerance of
/// the edge between them.
bool _fits(List<Offset> points, int from, int to, double toleranceSquared) {
  final count = points.length;
  final start = points[from % count];
  final end = points[to % count];
  for (var i = from + 1; i < to; i++) {
    final distance = _distanceToSegmentSquared(points[i % count], start, end);
    if (distance > toleranceSquared) {
      return false;
    }
  }
  return true;
}

int _farthestFrom(List<Offset> points, int origin) {
  var farthest = origin;
  var farthestDistance = 0.0;
  for (var i = 0; i < points.length; i++) {
    final distance = (points[i] - points[origin]).distanceSquared;
    if (distance > farthestDistance) {
      farthestDistance = distance;
      farthest = i;
    }
  }
  return farthest;
}

/// The squared distance from [point] to the closest point on the line segment
/// between [from] and [to].
double _distanceToSegmentSquared(Offset point, Offset from, Offset to) {
  final segmentX = to.dx - from.dx;
  final segmentY = to.dy - from.dy;
  final pointX = point.dx - from.dx;
  final pointY = point.dy - from.dy;
  final lengthSquared = segmentX * segmentX + segmentY * segmentY;
  final along = pointX * segmentX + pointY * segmentY;
  if (along <= 0) {
    return pointX * pointX + pointY * pointY;
  }
  if (along >= lengthSquared) {
    final endX = pointX - segmentX;
    final endY = pointY - segmentY;
    return endX * endX + endY * endY;
  }
  final across = pointX * segmentY - pointY * segmentX;
  return across * across / lengthSquared;
}

/// Samples a contour so that the polyline through [points] stays within
/// [_maxDeviation] of it, with as few tangent lookups as it can.
///
/// It predicts the stride to the next sample from how much the contour bent
/// over the previous one. So it crosses straight stretches in a few lookups,
/// and follows tight curves in strides shorter than the step. A sample that
/// turns out to be too far ahead waits in [_ahead] until the walk reaches it.
/// [anchors] collects the corners' indices.
class _ContourSampler(
  final PathMetric _metric,
  final double _step,
  final double _maxDeviation,
) {
  /// The longest stride, in steps.
  static const _maxStepsPerStride = 32;

  /// The shortest stride, as a fraction of the step: 1 in 4.
  static const _subdivisionsPerStep = 4;

  /// The samples, in order along the contour. A closed contour's first point
  /// isn't repeated at its end.
  final List<Offset> points = [];

  /// The ascending indices of the corners in [points].
  final List<int> anchors = [];

  /// Whether the contour is closed, once [sample] has run.
  bool isClosed = false;

  /// The longest stride over a curved stretch.
  ///
  /// A feature that the length check of a curved stretch misses is at most a
  /// 25th of the stretch deep. That depth must stay within the tolerance,
  /// which is 6 times [_maxDeviation].
  late final double _maxCurveStride = 150 * _maxDeviation;

  final List<Tangent> _ahead = [];
  final List<double> _aheadOffsets = [];

  /// A lookup that [_addCorner] made this round, between the samples. It
  /// joins [_ahead] if the stride shrinks.
  Tangent? _spare;
  double _spareOffset = 0;

  Tangent? _lookup(double offset) => _metric.getTangentForOffset(offset);

  /// Walks the contour, filling [points] and [anchors].
  void sample() {
    final length = _metric.length;
    final first = _lookup(0);
    if (first == null) {
      return;
    }
    // On flat stretches the strides grow past the step. A closed contour caps
    // them too, to keep its three steps.
    final maxStride = _metric.isClosed
        ? min(_step * _maxStepsPerStride, length / 3)
        : _step * _maxStepsPerStride;
    final minStride = _maxDeviation > 0 ? _step / _subdivisionsPerStep : _step;

    points.add(first.position);
    var from = first;
    var fromOffset = 0.0;
    var stride = _step;
    // Each round either moves on or shortens the stride by at least a fifth.
    // The limit only keeps an unforeseen case from looping forever.
    final maxRounds = 64 * (length / minStride).ceil() + 64;
    for (var round = 0; fromOffset < length && round < maxRounds; round++) {
      _spare = null;
      while (_ahead.isNotEmpty && _aheadOffsets.last <= fromOffset) {
        _ahead.removeLast();
        _aheadOffsets.removeLast();
      }
      final Tangent? to;
      final double toOffset;
      if (_ahead.isNotEmpty &&
          _aheadOffsets.last <= fromOffset + stride * 1.2) {
        to = _ahead.removeLast();
        toOffset = _aheadOffsets.removeLast();
      } else {
        final isLast = length - fromOffset <= stride * 1.2;
        toOffset = isLast ? length : fromOffset + stride;
        to = _lookup(toOffset);
      }
      if (to == null) {
        break;
      }
      final arc = toOffset - fromOffset;
      final bend = _bend(from, to, arc);
      if (bend <= 1) {
        _add(to.position);
        stride = bend < 1e-3 ? maxStride : arc * 0.9 / sqrt(bend);
        if (stride > maxStride) {
          stride = maxStride;
        } else if (stride < minStride) {
          stride = minStride;
        }
      } else if (_addCorner(fromOffset, from, to, arc)) {
        stride = max(arc, minStride);
      } else if (arc <= minStride * 1.2) {
        _add(to.position);
        stride = minStride;
      } else {
        _ahead.add(to);
        _aheadOffsets.add(toOffset);
        final spare = _spare;
        if (spare != null) {
          _ahead.add(spare);
          _aheadOffsets.add(_spareOffset);
          _spare = null;
        }
        var shrink = bend.isFinite ? 0.9 / sqrt(bend) : 0.5;
        if (shrink > 0.8) {
          shrink = 0.8;
        } else if (shrink < 0.25) {
          shrink = 0.25;
        }
        stride = max(arc * shrink, minStride);
        continue;
      }
      from = to;
      fromOffset = toOffset;
    }
    if (fromOffset < length) {
      final last = _lookup(length);
      if (last != null) {
        _add(last.position);
        from = last;
      }
    }
    _close(first, from);
  }

  /// Joins a closed contour's end to its start: the same point, possibly with
  /// different tangents, so a corner if they differ.
  ///
  /// Only a contour whose metric is closed counts as closed. One that ends
  /// where it starts without being closed is drawn open, so it keeps both
  /// ends.
  void _close(Tangent first, Tangent last) {
    isClosed = points.length > 1 && _metric.isClosed;
    if (!isClosed) {
      return;
    }
    points.removeLast();
    final seam = points.length;
    final from = last.vector;
    final to = first.vector;
    if (from.dx * to.dx + from.dy * to.dy < 0.9999) {
      anchors.add(0);
    }
    final fixed = <int>{
      for (final index in anchors)
        if (index == seam) 0 else index,
    };
    anchors
      ..clear()
      ..addAll(fixed)
      ..sort();
  }

  void _add(Offset point, {bool isAnchor = false}) {
    if (point != points.last) {
      points.add(point);
    }
    if (isAnchor) {
      _anchorLast();
    }
  }

  void _anchorLast() {
    final index = points.length - 1;
    if (anchors.isEmpty || anchors.last != index) {
      anchors.add(index);
    }
  }

  /// How far the contour between the two samples bends away from the chord
  /// between them, as a share of [_maxDeviation].
  ///
  /// The stretch is flat enough when this is at most 1. It's infinite when a
  /// tangent points back along the chord.
  ///
  /// When both tangents line up with the chord, the stretch is a line, unless
  /// something hides between the samples. A stretch of length `arc` between
  /// two points can't leave the ellipse with them as its foci, whose
  /// semi-minor axis is `sqrt(arc² - chord²) / 2`. Lengths are exact along
  /// lines, so that settles it.
  ///
  /// Along curves, lengths are off by up to a third over short stretches. So
  /// there the bend comes from the tangents: a curve whose end tangents make
  /// the angles `a` and `b` with its chord strays about `chord * (a + b) / 8`
  /// from it. Its length only has to be plausible. That, with
  /// [_maxCurveStride], limits what could hide between the samples.
  double _bend(Tangent from, Tangent to, double arc) {
    final dx = to.position.dx - from.position.dx;
    final dy = to.position.dy - from.position.dy;
    final fromVector = from.vector;
    final toVector = to.vector;
    if (dx * fromVector.dx + dy * fromVector.dy <= 0 ||
        dx * toVector.dx + dy * toVector.dy <= 0) {
      return double.infinity;
    }
    final sway =
        (dx * fromVector.dy - dy * fromVector.dx).abs() +
        (dx * toVector.dy - dy * toVector.dx).abs();
    final chordSquared = dx * dx + dy * dy;
    final arcSquared = arc * arc;
    if (sway <= 1e-4 * arc) {
      final limit = 4 * _maxDeviation * _maxDeviation;
      return arcSquared - chordSquared > limit ? double.infinity : 0;
    }
    if (arc > _maxCurveStride ||
        (arc > _step && chordSquared < 0.85 * arcSquared)) {
      return double.infinity;
    }
    return sway / (8 * _maxDeviation);
  }

  /// Adds the corner between the two samples, and the `to` sample, if the
  /// contour between them is two straight lines. Returns whether it did.
  ///
  /// That's the case when the legs from the samples to where their tangent
  /// lines meet add up to the contour's length between them.
  bool _addCorner(double fromOffset, Tangent from, Tangent to, double arc) {
    final fromVector = from.vector;
    final toVector = to.vector;
    final cross = fromVector.dx * toVector.dy - fromVector.dy * toVector.dx;
    if (cross.abs() < 1e-6) {
      return false;
    }
    final dx = to.position.dx - from.position.dx;
    final dy = to.position.dy - from.position.dy;
    final fromLeg = (dx * toVector.dy - dy * toVector.dx) / cross;
    final toLeg = (fromVector.dx * dy - fromVector.dy * dx) / cross;
    final slack = max(2 * _maxDeviation * _maxDeviation / arc, arc * 1e-6);
    if (fromLeg < -slack ||
        toLeg < -slack ||
        (fromLeg + toLeg - arc).abs() > slack) {
      return false;
    }
    final corner = from.position + fromVector * fromLeg;
    final merge = max(_maxDeviation / 2, arc * 1e-6);
    if (fromLeg > merge && toLeg > merge) {
      // A staircase between the samples is as long as a single corner, so
      // check that the contour passes through the corner too.
      final sample = _lookup(fromOffset + fromLeg);
      if (sample == null) {
        return false;
      }
      if ((sample.position - corner).distance > slack) {
        if (toLeg > arc / 8 && fromLeg > arc / 8) {
          _spare = sample;
          _spareOffset = fromOffset + fromLeg;
        }
        return false;
      }
    }
    if (fromLeg <= merge) {
      points.last = corner;
      _anchorLast();
      _add(to.position);
    } else if (toLeg <= merge) {
      _add(corner, isAnchor: true);
    } else {
      _add(corner, isAnchor: true);
      _add(to.position);
    }
    return true;
  }
}
