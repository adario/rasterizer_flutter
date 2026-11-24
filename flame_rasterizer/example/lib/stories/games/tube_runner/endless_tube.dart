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
  /// cuts out what the rings before each line hide of it, as [_Hiders] says,
  /// so that where the tube bends, its nearer walls and ridges hide what's
  /// beyond.
  ///
  /// The lines of [lane], if any, go to `lane` instead of `tube`: its two
  /// edges, and its stretch of each ring across it.
  ({RasterizerPolygons tube, RasterizerPolygons lane}) quadsAt(
    double distance,
    TubeView view, {
    int? lane,
  }) {
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
    _Hiders? hiders;
    if (!tube.isOpen) {
      if (_hiders?.tube != tube) {
        _hiders = _Hiders(tube, turn);
      }
      hiders = _hiders!..reset();
    }
    final lines = _Lines(view);
    final laneLines = _Lines(view);
    final laneEdges = lane == null
        ? const <int>{}
        : {lane, tube.pointAfter(lane)};
    final every = (ringSpacing / step).round();
    for (var k = 0; k < _rings.length; k++) {
      final outline = seen[k];
      hiders?.pass(outline, _fromEye(_rings[k].center, eye, ship));
      if (k + 1 < _rings.length) {
        final next = seen[k + 1];
        for (var i = 0; i < outline.length; i++) {
          final before = tube.isOpen
              ? i - 1
              : (i + tube.laneCount - 1) % tube.laneCount;
          if (faces(k, before) || faces(k, i)) {
            (laneEdges.contains(i) ? laneLines : lines).add(
              outline[i],
              next[i],
              hiders: hiders,
            );
          }
        }
      }
      if (_rings[k].index % every == 0) {
        for (var i = 0; i < tube.laneCount; i++) {
          if (faces(k - 1, i) || faces(k, i)) {
            (i == lane ? laneLines : lines).add(
              outline[i],
              outline[tube.pointAfter(i)],
              hiders: hiders,
              nearer: true,
            );
          }
        }
      }
    }
    return (tube: lines.quads, lane: laneLines.quads);
  }

  /// What the rings hide, for the last closed tube that [quadsAt] drew.
  _Hiders? _hiders;

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
  /// the line closer than [TubeView.near], and leaves out what [hiders]
  /// hide of it, if any: what the rings before it hide, or [nearer] those
  /// before the last ring passed to them, for a line on that ring.
  void add(
    Point3 from,
    Point3 to, {
    _Hiders? hiders,
    bool nearer = false,
  }) {
    var (a, b) = (from, to);
    if (a.z < TubeView.near && b.z < TubeView.near) {
      return;
    }
    if (a.z < TubeView.near) {
      a = a + (b - a) * ((TubeView.near - a.z) / (b.z - a.z));
    } else if (b.z < TubeView.near) {
      b = b + (a - b) * ((TubeView.near - b.z) / (a.z - b.z));
    }
    if (hiders == null) {
      _addLine(a, b);
      return;
    }
    final count = hiders.spansOf(
      EndlessTube._sight(a),
      EndlessTube._sight(b),
      nearer: nearer,
    );
    final spans = hiders.spans;
    // The eye sees 1 / z change evenly along a line.
    Point3 at(double t) {
      final inverse = (1 - t) / a.z + t / b.z;
      return a + (b - a) * (t / b.z / inverse);
    }

    for (var s = 0; s < count; s++) {
      _addLine(at(spans[2 * s]), at(spans[2 * s + 1]));
    }
  }

  /// Adds a line from [a] to [b], both at least [TubeView.near] away, as a
  /// quad.
  void _addLine(Point3 a, Point3 b) => _addQuad(
    _project(a),
    view.lineWidthOf(a.z),
    _project(b),
    view.lineWidthOf(b.z),
  );

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

/// What the rings of a closed tube hide of the lines beyond them, as the eye
/// sees them from 1 away: all but the window through which it sees past the
/// rings so far, and the notches between each ring's outline and its convex
/// hull, behind the tube's ridges.
///
/// `EndlessTube.quadsAt` passes it the rings from the eye out, and asks it
/// which spans of each line the eye sees. It keeps its buffers from one frame
/// to the next, so that it allocates nothing per line.
class _Hiders(final Tube tube, final double turn) {
  /// The outline's convex hull, as indices in an order whose signed area is
  /// positive.
  late final _hull = EndlessTube._hullOf(tube.points, turn);

  /// The outline's notches, as [_notchesOf] returns them.
  late final _notches = _notchesOf(tube.points, _hull, turn);

  /// Where the eye sees each point of the ring last passed, grown about the
  /// ring's middle by `EndlessTube._windowSlack`: x then y.
  late final _ring = Float64List(2 * tube.points.length);

  /// The window, as the points of a convex polygon with a positive signed
  /// area, x then y, and how many: -1 while no ring hides anything.
  var _window = Float64List(64);
  var _windowLength = -1;

  /// The window's bounds: left, top, right and bottom.
  final _windowBounds = Float64List(4);

  /// Where [_intersectRing] puts each step's result, and how far inside an
  /// edge each point is, scaled by the edge's length.
  var _spare = Float64List(64);
  var _sides = Float64List(32);

  /// The window, how many points it has and how many notches were live
  /// before the ring last passed, for the lines across that ring.
  var _nearerWindow = Float64List(64);
  var _nearerLength = -1;
  var _nearerCount = 0;

  /// How many numbers a notch takes in [_notchPoints]: 2 for each point of
  /// the longest one.
  late final _stride =
      2 * _notches.fold<int>(3, (most, notch) => math.max(most, notch.length));

  /// The notches made so far this frame, by slot: their points, x then y,
  /// [_stride] apart, how many points each has, and their bounds (left, top,
  /// right and bottom).
  var _notchPoints = Float64List(0);
  var _notchLengths = Int32List(0);
  var _notchBounds = Float64List(0);
  var _slots = 0;

  /// The slots of the notches whose bounds still overlap the window's,
  /// nearest first, and how many.
  var _live = Int32List(0);
  var _liveCount = 0;

  /// The spans of the line that [spansOf] last returned the count of: where
  /// each starts and ends, from 0 to 1 along the line.
  Float64List spans = Float64List(2);
  var _spareSpans = Float64List(2);

  /// The span that [_clip] narrows: where it starts and ends.
  var _start = 0.0;
  var _end = 1.0;

  /// Starts a new frame, before the nearest ring.
  void reset() {
    _windowLength = -1;
    _nearerLength = -1;
    _nearerCount = 0;
    _slots = 0;
    _liveCount = 0;
  }

  /// Passes the next ring from the eye: its [outline] and [center], from the
  /// eye.
  ///
  /// A ring hides something only when all of its outline is at least
  /// [TubeView.near] away. Only the rings nearest the eye aren't, and before
  /// them nothing hides anything anyway.
  void pass(List<Point3> outline, Point3 center) {
    _prune();
    _nearerLength = _windowLength;
    if (_windowLength > 0) {
      _nearerWindow = _fit(_nearerWindow, 2 * _windowLength);
      _nearerWindow.setRange(0, 2 * _windowLength, _window);
    }
    _nearerCount = _liveCount;
    for (final i in _hull) {
      if (outline[i].z <= TubeView.near) {
        return;
      }
    }
    final middleX = center.x / center.z;
    final middleY = center.y / center.z;
    for (var i = 0; i < outline.length; i++) {
      final point = outline[i];
      _ring[2 * i] =
          middleX + (point.x / point.z - middleX) * EndlessTube._windowSlack;
      _ring[2 * i + 1] =
          middleY + (point.y / point.z - middleY) * EndlessTube._windowSlack;
    }
    _intersectRing();
    if (_windowLength > 0) {
      _boundsOf(_window, 0, _windowLength, _windowBounds, 0);
      _addNotches();
    }
  }

  /// Returns how many [spans] of the line from [a] to [b] the eye sees past
  /// the rings passed so far, or [nearer] those before the last one.
  int spansOf(Offset a, Offset b, {required bool nearer}) {
    final windowLength = nearer ? _nearerLength : _windowLength;
    final count = nearer ? _nearerCount : _liveCount;
    final line = b - a;
    _start = 0;
    _end = 1;
    if (windowLength == 0) {
      return 0;
    }
    if (windowLength > 0 &&
        !_clip(nearer ? _nearerWindow : _window, 0, windowLength, a, line)) {
      return 0;
    }
    var spans = this.spans;
    var spare = _spareSpans;
    spans[0] = _start;
    spans[1] = _end;
    var length = 1;
    final left = math.min(a.dx, b.dx);
    final right = math.max(a.dx, b.dx);
    final top = math.min(a.dy, b.dy);
    final bottom = math.max(a.dy, b.dy);
    final bounds = _notchBounds;
    for (var c = 0; c < count && length > 0; c++) {
      final slot = _live[c];
      final o = 4 * slot;
      if (bounds[o] > right ||
          bounds[o + 1] > bottom ||
          bounds[o + 2] < left ||
          bounds[o + 3] < top) {
        continue;
      }
      _start = spans[0];
      _end = spans[2 * length - 1];
      if (!_clip(_notchPoints, _stride * slot, _notchLengths[slot], a, line)) {
        continue;
      }
      // Cuts the notch's span out of each span.
      var cut = 0;
      for (var s = 0; s < length; s++) {
        final start = spans[2 * s];
        final end = spans[2 * s + 1];
        if (_end <= start || _start >= end) {
          spare[2 * cut] = start;
          spare[2 * cut + 1] = end;
          cut++;
          continue;
        }
        if (_start > start) {
          spare[2 * cut] = start;
          spare[2 * cut + 1] = _start;
          cut++;
        }
        if (_end < end) {
          spare[2 * cut] = _end;
          spare[2 * cut + 1] = end;
          cut++;
        }
      }
      final swap = spans;
      spans = spare;
      spare = swap;
      length = cut;
    }
    this.spans = spans;
    _spareSpans = spare;
    return length;
  }

  /// Drops the notches whose bounds no longer overlap the window's: as the
  /// window only shrinks, they hide nothing that it doesn't.
  void _prune() {
    if (_windowLength < 0) {
      return;
    }
    if (_windowLength == 0) {
      _liveCount = 0;
      return;
    }
    var kept = 0;
    for (var c = 0; c < _liveCount; c++) {
      final slot = _live[c];
      if (_overlapsWindow(_notchBounds, 4 * slot)) {
        _live[kept++] = slot;
      }
    }
    _liveCount = kept;
  }

  /// Narrows the window to the hull of the ring last passed: the
  /// Sutherland-Hodgman algorithm.
  void _intersectRing() {
    final hull = _hull;
    if (_windowLength < 0) {
      _window = _fit(_window, 2 * hull.length);
      for (var h = 0; h < hull.length; h++) {
        _window[2 * h] = _ring[2 * hull[h]];
        _window[2 * h + 1] = _ring[2 * hull[h] + 1];
      }
      _windowLength = hull.length;
      return;
    }
    for (var e = 0; e < hull.length && _windowLength > 0; e++) {
      final fromX = _ring[2 * hull[e]];
      final fromY = _ring[2 * hull[e] + 1];
      final next = hull[(e + 1) % hull.length];
      final edgeX = _ring[2 * next] - fromX;
      final edgeY = _ring[2 * next + 1] - fromY;
      final points = _window;
      final length = _windowLength;
      if (_sides.length < length) {
        _sides = Float64List(2 * length);
      }
      final sides = _sides;
      for (var i = 0; i < length; i++) {
        sides[i] =
            edgeX * (points[2 * i + 1] - fromY) -
            edgeY * (points[2 * i] - fromX);
      }
      // Clipping a convex polygon to an edge adds at most one point.
      final result = _spare = _fit(_spare, 2 * (length + 1));
      var count = 0;
      for (var i = 0; i < length; i++) {
        final j = (i + 1) % length;
        if (sides[i] >= 0) {
          result[2 * count] = points[2 * i];
          result[2 * count + 1] = points[2 * i + 1];
          count++;
        }
        if ((sides[i] >= 0) != (sides[j] >= 0)) {
          final t = sides[i] / (sides[i] - sides[j]);
          result[2 * count] =
              points[2 * i] + (points[2 * j] - points[2 * i]) * t;
          result[2 * count + 1] =
              points[2 * i + 1] + (points[2 * j + 1] - points[2 * i + 1]) * t;
          count++;
        }
      }
      _spare = points;
      _window = result;
      _windowLength = count;
    }
  }

  /// Adds the notches of the ring last passed whose bounds overlap the
  /// window's.
  void _addNotches() {
    _grow(_slots + _notches.length);
    for (final notch in _notches) {
      final o = _stride * _slots;
      for (var j = 0; j < notch.length; j++) {
        _notchPoints[o + 2 * j] = _ring[2 * notch[j]];
        _notchPoints[o + 2 * j + 1] = _ring[2 * notch[j] + 1];
      }
      _boundsOf(_notchPoints, o, notch.length, _notchBounds, 4 * _slots);
      if (_overlapsWindow(_notchBounds, 4 * _slots)) {
        _notchLengths[_slots] = notch.length;
        _live[_liveCount++] = _slots++;
      }
    }
  }

  /// Makes room for [slots] notches, and for the spans they can cut a line
  /// into.
  void _grow(int slots) {
    if (_notchLengths.length >= slots) {
      return;
    }
    final room = math.max(slots, 2 * _notchLengths.length);
    _notchPoints = Float64List(_stride * room)..setAll(0, _notchPoints);
    _notchLengths = Int32List(room)..setAll(0, _notchLengths);
    _notchBounds = Float64List(4 * room)..setAll(0, _notchBounds);
    _live = Int32List(room)..setAll(0, _live);
    // Each notch cuts at most one span in two.
    spans = Float64List(2 * (room + 1));
    _spareSpans = Float64List(2 * (room + 1));
  }

  /// Returns whether the bounds at [offset] in [bounds] overlap the
  /// window's.
  bool _overlapsWindow(Float64List bounds, int offset) =>
      bounds[offset] <= _windowBounds[2] &&
      bounds[offset + 1] <= _windowBounds[3] &&
      bounds[offset + 2] >= _windowBounds[0] &&
      bounds[offset + 3] >= _windowBounds[1];

  /// Narrows the span from [_start] to [_end] of the line from [a], going
  /// [line], to the part inside the convex polygon of [length] points at
  /// [offset] in [points], whose signed area is positive. Returns false if
  /// none is left: the Cyrus-Beck algorithm.
  bool _clip(
    Float64List points,
    int offset,
    int length,
    Offset a,
    Offset line,
  ) {
    var start = _start;
    var end = _end;
    for (var e = 0; e < length; e++) {
      final from = offset + 2 * e;
      final to = offset + 2 * ((e + 1) % length);
      final fromX = points[from];
      final fromY = points[from + 1];
      final edgeX = points[to] - fromX;
      final edgeY = points[to + 1] - fromY;
      if (edgeX * edgeX + edgeY * edgeY < _leastEdgeSquared) {
        continue;
      }
      // How far inside the edge a is, and how fast the line goes inward.
      final inside = edgeX * (a.dy - fromY) - edgeY * (a.dx - fromX);
      final inward = edgeX * line.dy - edgeY * line.dx;
      if (inward == 0) {
        if (inside < 0) {
          return false;
        }
        continue;
      }
      final t = -inside / inward;
      if (inward > 0) {
        start = math.max(start, t);
      } else {
        end = math.min(end, t);
      }
      if (start >= end) {
        return false;
      }
    }
    _start = start;
    _end = end;
    return true;
  }

  /// The least squared length of an edge that [_clip] clips to: rounding
  /// errors leave shorter ones, which point any way.
  static const _leastEdgeSquared = 1e-14;

  /// Returns [list] if it holds at least [length] numbers, else a longer
  /// one, whose numbers are all 0.
  static Float64List _fit(Float64List list, int length) => list.length >= length
      ? list
      : Float64List(math.max(length, 2 * list.length));

  /// Puts the bounds of the [length] points at [offset] in [points] into
  /// [bounds] at [at]: left, top, right and bottom.
  static void _boundsOf(
    Float64List points,
    int offset,
    int length,
    Float64List bounds,
    int at,
  ) {
    var left = points[offset];
    var top = points[offset + 1];
    var right = left;
    var bottom = top;
    for (var i = 1; i < length; i++) {
      final x = points[offset + 2 * i];
      final y = points[offset + 2 * i + 1];
      left = math.min(left, x);
      top = math.min(top, y);
      right = math.max(right, x);
      bottom = math.max(bottom, y);
    }
    bounds[at] = left;
    bounds[at + 1] = top;
    bounds[at + 2] = right;
    bounds[at + 3] = bottom;
  }

  /// Returns the notches between [points], a closed outline whose signed
  /// area has [turn]'s sign, and its convex [hull]: each as the indices of a
  /// convex polygon whose signed area is positive.
  ///
  /// Each notch runs along the outline from one point of the hull to the
  /// next, and back along the hull. It leaves out the points where a notch
  /// goes straight on, and the notches that aren't convex, which hide
  /// nothing then: none of the tubes' are.
  static List<List<int>> _notchesOf(
    List<Offset> points,
    List<int> hull,
    double turn,
  ) {
    final count = points.length;
    final way = turn < 0 ? count - 1 : 1;
    final notches = <List<int>>[];
    for (var h = 0; h < hull.length; h++) {
      final to = hull[(h + 1) % hull.length];
      final notch = [hull[h]];
      while (notch.last != to) {
        notch.add((notch.last + way) % count);
      }
      var dropped = false;
      do {
        dropped = false;
        for (var k = 0; k < notch.length && notch.length > 2; k++) {
          final before = points[notch[(k + notch.length - 1) % notch.length]];
          final point = points[notch[k]];
          final after = points[notch[(k + 1) % notch.length]];
          if (_cross(point - before, after - point).abs() <
              EndlessTube._leastTurn) {
            notch.removeAt(k);
            k--;
            dropped = true;
          }
        }
      } while (dropped);
      if (notch.length < 3) {
        continue;
      }
      var area = 0.0;
      for (var k = 0; k < notch.length; k++) {
        area += _cross(
          points[notch[k]],
          points[notch[(k + 1) % notch.length]],
        );
      }
      final positive = area < 0 ? notch.reversed.toList() : notch;
      var convex = true;
      for (var k = 0; k < positive.length; k++) {
        final before =
            points[positive[(k + positive.length - 1) % positive.length]];
        final point = points[positive[k]];
        final after = points[positive[(k + 1) % positive.length]];
        if (_cross(point - before, after - point) < 0) {
          convex = false;
        }
      }
      if (convex) {
        notches.add(positive);
      }
    }
    return notches;
  }
}

/// Returns the cross product of [a] and [b]: positive if [b] turns from [a]
/// the way the outlines with a positive signed area turn.
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
