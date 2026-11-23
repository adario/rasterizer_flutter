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

/// An endless [tube], made as the ship flies along it.
///
/// Its axis bends as [axisAt] says. It's cut into rings [step] apart along
/// the axis, from [behind] behind the ship to [ahead] in front of it. Each
/// [advanceTo] makes the rings that come into that span, and drops those
/// that leave it. Each ring turns from the one before as little as the axis
/// lets it, so that the outline doesn't spin about the axis.
///
/// The eye looks along the axis at the ship's ring, from [Tube.eye] behind
/// it, so that ring is always where Tube Shooter's rim is on screen, and the
/// tube ahead bends away from it.
class EndlessTube(final Tube tube) {
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
  /// ship [distance] along the axis.
  ///
  /// Each point of the outline draws a line along the tube, and every
  /// [ringSpacing] a ring goes across it. Lines get thinner with distance, as
  /// [TubeView.lineWidthOf] says, and the view clips them closer than
  /// [TubeView.near].
  RasterizerPolygons quadsAt(double distance, TubeView view) {
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
    final lines = _Lines(view);
    final every = (ringSpacing / step).round();
    for (var k = 0; k < _rings.length; k++) {
      final outline = seen[k];
      if (k + 1 < _rings.length) {
        final next = seen[k + 1];
        for (var i = 0; i < outline.length; i++) {
          lines.add(outline[i], next[i]);
        }
      }
      if (_rings[k].index % every == 0) {
        for (var i = 0; i < tube.laneCount; i++) {
          lines.add(outline[i], outline[tube.pointAfter(i)]);
        }
      }
    }
    return lines.quads;
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
  /// the line closer than [TubeView.near].
  void add(Point3 from, Point3 to) {
    var (a, b) = (from, to);
    if (a.z < TubeView.near && b.z < TubeView.near) {
      return;
    }
    if (a.z < TubeView.near) {
      a = a + (b - a) * ((TubeView.near - a.z) / (b.z - a.z));
    } else if (b.z < TubeView.near) {
      b = b + (a - b) * ((TubeView.near - b.z) / (a.z - b.z));
    }
    _addQuad(
      _project(a),
      view.lineWidthOf(a.z),
      _project(b),
      view.lineWidthOf(b.z),
    );
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
