import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_rasterizer/flame_rasterizer.dart' show RasterizerPolygons;
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A point or a direction in 3D, in tube units: x to the right, y down and z
/// forward, as the eye looks at the start.
class const Point3(final double x, final double y, final double z) {
  Point3 operator +(Point3 other) =>
      Point3(x + other.x, y + other.y, z + other.z);

  Point3 operator -(Point3 other) =>
      Point3(x - other.x, y - other.y, z - other.z);

  Point3 operator *(double factor) =>
      Point3(x * factor, y * factor, z * factor);

  double dot(Point3 other) => x * other.x + y * other.y + z * other.z;

  Point3 cross(Point3 other) => Point3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// The same direction, 1 long.
  Point3 get normalized => this * (1 / math.sqrt(dot(this)));
}

/// A cross-section of the tube, [index] steps along its axis: where the axis
/// is, and which ways the axis, the outline's x and the outline's y go.
class const Ring(
  final int index,
  final Point3 center,
  final Point3 forward,
  final Point3 right,
  final Point3 down,
) {
  /// Returns where an outline [point] of this ring lies in 3D.
  Point3 place(Offset point) => center + right * point.dx + down * point.dy;
}

/// An endless tube, made as the ship flies along it.
///
/// Its outline is the view's tube, which [quadsAt] takes, so it can change
/// from one frame to the next. Its axis bends as [axisAt] says. It's cut into
/// rings [step] apart along the axis, from [behind] behind the ship to [ahead]
/// in front of it. Each [advanceTo] makes the rings that come into that span,
/// and drops those that leave it. Each ring turns from the one before as
/// little as the axis lets it, so that the outline doesn't spin about the
/// axis.
///
/// The eye looks along the axis at the ship's ring, from [Tube.eye] behind
/// it, so that ring is always where Tube Shooter's rim is on screen, and the
/// tube ahead bends away from it.
class EndlessTube() {
  /// The distance between two rings along the axis, in tube units.
  static const step = 0.5;

  /// How far in front of the ship the tube goes, in tube units.
  static const ahead = 16.0;

  /// How far behind the ship the tube goes, in tube units: to the eye, as
  /// anything closer than [TubeView.near] is clipped anyway.
  static const behind = Tube.eye + step;

  /// The distance between two rings drawn across the tube, in tube units: a
  /// multiple of [step].
  static const ringSpacing = 1.0;

  /// How far the axis bends across and down, in tube units, and over how
  /// long a stretch it bends back and forth once.
  static const bends = (
    across: (amplitude: 4.0, period: 40.0),
    down: (amplitude: 3.0, period: 56.0),
  );

  /// The rings from [behind] the ship to [ahead] of it, by index.
  final _rings = <Ring>[];

  /// Returns where the axis is, [distance] along it.
  static Point3 axisAt(double distance) {
    final (:across, :down) = bends;
    return Point3(
      across.amplitude * math.sin(2 * math.pi * distance / across.period),
      down.amplitude * math.cos(2 * math.pi * distance / down.period),
      distance,
    );
  }

  /// Returns the way the axis goes, [distance] along it.
  static Point3 forwardAt(double distance) {
    final (:across, :down) = bends;
    final acrossRate = 2 * math.pi / across.period;
    final downRate = 2 * math.pi / down.period;
    return Point3(
      across.amplitude * acrossRate * math.cos(acrossRate * distance),
      -down.amplitude * downRate * math.sin(downRate * distance),
      1,
    ).normalized;
  }

  /// Makes the rings from [behind] the ship to [ahead] of it, with the ship
  /// [distance] along the axis, and drops the others.
  void advanceTo(double distance) {
    final first = ((distance - behind) / step).floor();
    final last = ((distance + ahead) / step).ceil();
    if (_rings.isEmpty || _rings.first.index > first) {
      _rings
        ..clear()
        ..add(_startRing(first));
    }
    while (_rings.last.index < last) {
      final index = _rings.last.index + 1;
      _rings.add(_turnTo(_rings.last, index * step, index));
    }
    final gone = first - _rings.first.index;
    if (gone > 0) {
      _rings.removeRange(0, gone);
    }
  }

  /// Returns the ring at the ship, [distance] along the axis, which
  /// [advanceTo] made the rings for.
  Ring ringAt(double distance) {
    final index = (distance / step).floor();
    return _turnTo(_rings[index - _rings.first.index], distance, index);
  }

  /// Returns the tube's lines, as quads to fill, as the eye sees them with the
  /// ship [distance] along the axis, round the outline of [view]'s tube.
  ///
  /// Each point of the outline draws a line along the tube, and every
  /// [ringSpacing] a ring goes across it. Lines get thinner with distance, as
  /// [TubeView.lineWidthOf] says, and the view clips them closer than
  /// [TubeView.near].
  ///
  /// A closed tube leaves out the lines between faces that the eye sees from
  /// outside: from inside the tube, other faces always hide those. It also
  /// cuts its lines to the window through which the eye sees past the rings
  /// before them, so that where the tube bends, its nearer walls hide what's
  /// beyond. Each ring hides as its outline's convex hull, so a concave
  /// outline's ridges hide less than they would.
  RasterizerPolygons quadsAt(double distance, TubeView view) {
    final tube = view.tube;
    final ship = ringAt(distance);
    final eye = ship.center - ship.forward * Tube.eye;
    // Each ring's outline, from the eye: across, down and along its line of
    // sight.
    final seen = [
      for (final ring in _rings)
        [
          for (final point in tube.points)
            _fromEye(ring.place(point), eye, ship),
        ],
    ];
    // Twice the outline's signed area: its sign says which way it turns.
    var turn = 0.0;
    for (var i = 0; i < tube.laneCount; i++) {
      final point = tube.points[i];
      final next = tube.points[tube.pointAfter(i)];
      turn += point.dx * next.dy - point.dy * next.dx;
    }
    // Whether the eye sees each lane's face, from a ring to the next, from
    // inside the tube, by ring and lane.
    final facing = [
      for (var k = 0; k + 1 < _rings.length; k++)
        [
          for (var i = 0; i < tube.laneCount; i++)
            tube.isOpen ||
                _facesEye(
                  seen[k][i],
                  seen[k][tube.pointAfter(i)],
                  seen[k + 1][i],
                  turn,
                ),
        ],
    ];
    bool faces(int k, int lane) =>
        k >= 0 &&
        k < facing.length &&
        lane >= 0 &&
        lane < tube.laneCount &&
        facing[k][lane];
    final hull = tube.isOpen ? null : _hullOf(tube.points, turn);
    // Where the eye sees past the rings so far, as seen from 1 away from it:
    // null while none hides anything.
    List<Offset>? window;
    final lines = _Lines(view);
    final every = (ringSpacing / step).round();
    for (var k = 0; k < _rings.length; k++) {
      final outline = seen[k];
      final nearer = window;
      if (hull != null && hull.every((i) => outline[i].z > TubeView.near)) {
        final middle = _sight(_fromEye(_rings[k].center, eye, ship));
        final ring = [
          for (final i in hull)
            middle + (_sight(outline[i]) - middle) * _windowSlack,
        ];
        window = nearer == null ? ring : _intersect(nearer, ring);
      }
      if (k + 1 < _rings.length) {
        final next = seen[k + 1];
        for (var i = 0; i < outline.length; i++) {
          final before = tube.isOpen
              ? i - 1
              : (i + tube.laneCount - 1) % tube.laneCount;
          if (faces(k, before) || faces(k, i)) {
            lines.add(outline[i], next[i], window);
          }
        }
      }
      if (_rings[k].index % every == 0) {
        for (var i = 0; i < tube.laneCount; i++) {
          if (faces(k - 1, i) || faces(k, i)) {
            lines.add(outline[i], outline[tube.pointAfter(i)], nearer);
          }
        }
      }
    }
    return lines.quads;
  }

  /// How much bigger than each ring the window lets the eye see through it,
  /// so that the ring's own lines, on its edge, stay whole.
  static const _windowSlack = 1.002;

  /// The least turn at a point that [_hullOf] keeps it for, so that rounding
  /// errors don't keep points where the outline goes straight on.
  static const _leastTurn = 1e-9;

  /// Returns where the eye, at the origin, sees [point], as seen from 1 away
  /// from it: across and down.
  static Offset _sight(Point3 point) =>
      Offset(point.x / point.z, point.y / point.z);

  /// Returns the indices of the convex hull of [points], a closed outline
  /// whose signed area has [turn]'s sign, in an order whose signed area is
  /// positive.
  ///
  /// It drops the points where the outline turns in or goes straight on,
  /// until none is left, which holds for outlines that wind round their
  /// middle, as the tubes' do.
  static List<int> _hullOf(List<Offset> points, double turn) {
    final order = List.generate(points.length, (i) => i);
    final hull = turn < 0 ? order.reversed.toList() : order;
    var dropped = false;
    do {
      dropped = false;
      for (var k = 0; k < hull.length && hull.length > 3; k++) {
        final before = points[hull[(k + hull.length - 1) % hull.length]];
        final point = points[hull[k]];
        final after = points[hull[(k + 1) % hull.length]];
        if (_cross(point - before, after - point) < _leastTurn) {
          hull.removeAt(k);
          k--;
          dropped = true;
        }
      }
    } while (dropped);
    return hull;
  }

  /// Returns the part of convex [polygon] inside convex [clip], both with a
  /// positive signed area: the Sutherland-Hodgman algorithm.
  static List<Offset> _intersect(List<Offset> polygon, List<Offset> clip) {
    var result = polygon;
    for (var e = 0; e < clip.length && result.isNotEmpty; e++) {
      final from = clip[e];
      final edge = clip[(e + 1) % clip.length] - from;
      final points = result;
      // How far inside the edge each point is, scaled by the edge's length.
      final sides = [for (final point in points) _cross(edge, point - from)];
      result = [];
      for (var i = 0; i < points.length; i++) {
        final j = (i + 1) % points.length;
        if (sides[i] >= 0) {
          result.add(points[i]);
        }
        if ((sides[i] >= 0) != (sides[j] >= 0)) {
          result.add(
            Offset.lerp(
              points[i],
              points[j],
              sides[i] / (sides[i] - sides[j]),
            )!,
          );
        }
      }
    }
    return result;
  }

  /// Returns whether the eye, at the origin, sees from inside the tube the
  /// face from [corner] to [along], the next point of its outline, and to
  /// [ahead], the same point of the next ring, for an outline whose signed
  /// area has [turn]'s sign.
  static bool _facesEye(
    Point3 corner,
    Point3 along,
    Point3 ahead,
    double turn,
  ) {
    final outward = (along - corner).cross(ahead - corner) * turn;
    return outward.dot(corner) > 0;
  }

  /// Returns [point] as the eye at [eye] sees it, looking as [ship] faces:
  /// across, down and along its line of sight.
  static Point3 _fromEye(Point3 point, Point3 eye, Ring ship) {
    final offset = point - eye;
    return Point3(
      offset.dot(ship.right),
      offset.dot(ship.down),
      offset.dot(ship.forward),
    );
  }

  /// Returns the ring at [index], whose outline's x goes to the right.
  static Ring _startRing(int index) {
    final forward = forwardAt(index * step);
    final right = (const Point3(1, 0, 0) - forward * forward.x).normalized;
    return Ring(
      index,
      axisAt(index * step),
      forward,
      right,
      forward.cross(right),
    );
  }

  /// Returns the ring [distance] along the axis, at [index], turned from
  /// [from] as little as the axis lets it.
  ///
  /// This is the double reflection method for rotation minimizing frames, by
  /// Wang, Jüttler, Zheng and Liu (2008).
  static Ring _turnTo(Ring from, double distance, int index) {
    final center = axisAt(distance);
    final forward = forwardAt(distance);
    final move = center - from.center;
    final moveSquared = move.dot(move);
    if (moveSquared == 0) {
      return from;
    }
    final reflectedRight =
        from.right - move * (2 * move.dot(from.right) / moveSquared);
    final reflectedForward =
        from.forward - move * (2 * move.dot(from.forward) / moveSquared);
    final turn = forward - reflectedForward;
    final turnSquared = turn.dot(turn);
    var right = turnSquared == 0
        ? reflectedRight
        : reflectedRight - turn * (2 * turn.dot(reflectedRight) / turnSquared);
    // Keeps the ring square to the axis, as rounding errors add up.
    right = (right - forward * forward.dot(right)).normalized;
    return Ring(index, center, forward, right, forward.cross(right));
  }
}

/// Lines in 3D, from the eye, made into [quads] to fill, as Tube Shooter's
/// `TubeView` makes its own.
class _Lines(final TubeView view) {
  /// The quads' corners, x then y.
  final _corners = <double>[];

  /// The quads added so far.
  RasterizerPolygons get quads {
    final count = _corners.length ~/ 8;
    return RasterizerPolygons(
      Float32List.fromList(_corners),
      Int32List(count)..fillRange(0, count, 4),
    );
  }

  /// How far it moves the lines right and down: a sixteenth of a device
  /// pixel, as `TubeView` does, and for the same reason.
  late final _lineOffset = Offset(view.devicePixel / 16, view.devicePixel / 16);

  /// Adds a line from [from] to [to], as a quad.
  ///
  /// Each end is [TubeView.lineWidthOf] its distance wide, and extends by
  /// half that width, so that lines meeting at a corner close it. It clips
  /// the line closer than [TubeView.near], and outside [window], a convex
  /// polygon with a positive signed area as `EndlessTube._sight` places it,
  /// if any.
  void add(Point3 from, Point3 to, [List<Offset>? window]) {
    var (a, b) = (from, to);
    if (a.z < TubeView.near && b.z < TubeView.near) {
      return;
    }
    if (a.z < TubeView.near) {
      a = a + (b - a) * ((TubeView.near - a.z) / (b.z - a.z));
    } else if (b.z < TubeView.near) {
      b = b + (a - b) * ((TubeView.near - b.z) / (a.z - b.z));
    }
    if (window != null) {
      final span = _spanIn(
        window,
        EndlessTube._sight(a),
        EndlessTube._sight(b),
      );
      if (span == null) {
        return;
      }
      // The eye sees 1 / z change evenly along a line.
      Point3 at(double t) {
        final inverse = (1 - t) / a.z + t / b.z;
        return a + (b - a) * (t / b.z / inverse);
      }

      final start = at(span.start);
      b = at(span.end);
      a = start;
    }
    _addQuad(
      _project(a),
      view.lineWidthOf(a.z),
      _project(b),
      view.lineWidthOf(b.z),
    );
  }

  /// The least squared length of a window's edge that [_spanIn] clips to:
  /// rounding errors leave shorter ones, which point any way.
  static const _leastEdgeSquared = 1e-14;

  /// Returns the part of the line from [a] to [b] inside convex [window],
  /// whose signed area is positive, from 0 at [a] to 1 at [b]: null if none.
  ///
  /// This is the Cyrus-Beck algorithm.
  static ({double start, double end})? _spanIn(
    List<Offset> window,
    Offset a,
    Offset b,
  ) {
    if (window.isEmpty) {
      return null;
    }
    var start = 0.0;
    var end = 1.0;
    final line = b - a;
    for (var e = 0; e < window.length; e++) {
      final from = window[e];
      final edge = window[(e + 1) % window.length] - from;
      if (edge.distanceSquared < _leastEdgeSquared) {
        continue;
      }
      // How far inside the edge a is, and how fast the line goes inward.
      final inside = _cross(edge, a - from);
      final inward = _cross(edge, line);
      if (inward == 0) {
        if (inside < 0) {
          return null;
        }
        continue;
      }
      final t = -inside / inward;
      if (inward > 0) {
        start = math.max(start, t);
      } else {
        end = math.min(end, t);
      }
      if (start > end) {
        return null;
      }
    }
    return (start: start, end: end);
  }

  /// Returns where [point] lands in the world.
  Offset _project(Point3 point) =>
      Offset(point.x, point.y) * view.scaleOf(point.z) + _lineOffset;

  /// Adds a quad from [a], [aWidth] wide, to [b], [bWidth] wide.
  void _addQuad(Offset a, double aWidth, Offset b, double bWidth) {
    final length = (b - a).distance;
    if (length == 0) {
      return;
    }
    final along = (b - a) / length;
    final across = Offset(-along.dy, along.dx);
    final start = a - along * (aWidth / 2);
    final end = b + along * (bWidth / 2);
    for (final corner in [
      start + across * (aWidth / 2),
      end + across * (bWidth / 2),
      end - across * (bWidth / 2),
      start - across * (aWidth / 2),
    ]) {
      _corners
        ..add(corner.dx)
        ..add(corner.dy);
    }
  }
}

/// Returns the cross product of [a] and [b]: positive if [b] turns from [a]
/// the way the outlines with a positive signed area turn.
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
