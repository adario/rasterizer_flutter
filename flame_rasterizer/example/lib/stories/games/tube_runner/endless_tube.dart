import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame_rasterizer/flame_rasterizer.dart' show RasterizerPolygons;
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A point or a direction in 3D, in tube units.
///
/// The axes are as the eye sees them at the start: x to the right, y down
/// and z forward.
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

/// A cross-section of the tube, [index] steps along its axis.
///
/// It holds where the axis is, and the directions of the axis, of the
/// outline's x and of the outline's y.
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

/// A spike down the middle of a [lane], from [near] to [far] along the
/// axis, in tube units.
///
/// [far] is where its seeder came. [near] is how far the seeder has laid
/// the spike, or where shots have cut it back to.
class Spike(final int lane, final double far) {
  double near = far;
}

/// Where a shape is in the tube: an enemy, a shot or an explosion.
///
/// The shape is down the middle of `lane`, `at` along the axis, in tube
/// units. If it is flipping onto a neighbouring lane, `flip` says how far.
///
/// Its `across`, if given, is where it is across its lane, from 0 at the
/// lane's first point to 1 at the next, instead of the lane's middle.
typedef TubeMark = ({int lane, double at, TubeFlip? flip, double? across});

/// How far a shape has flipped from its lane onto the neighbouring lane `to`,
/// as in Tube Shooter.
///
/// The `turn` is the angle it has turned by about the corner the two lanes
/// share: from 0 up to the angle that `Tube.flipAngle` returns.
typedef TubeFlip = ({int to, double turn});

/// Where a shape at a [TubeMark] shows in the world.
///
/// The `angle` points the shape's tail away along the lane, and the `scale`
/// is the lane's width there.
typedef ShapePlace = ({Offset position, double angle, double scale});

/// A zapper's bolt down the middle of a `lane`, from the ship's ring to the
/// zapper, `far` along the axis in tube units.
typedef TubeBolt = ({int lane, double far});

/// What [EndlessTube.quadsAt] makes.
///
/// It holds:
/// - the quads of the tube, the ship's lane and the spikes;
/// - the quads of the flash's lane and spike, and of their halo;
/// - the quads of the bolts, and of their halo;
/// - the quads of the next tube;
/// - where a shape at each mark shows, or null where it doesn't.
typedef TubeQuads = ({
  RasterizerPolygons tube,
  RasterizerPolygons lane,
  RasterizerPolygons spikes,
  RasterizerPolygons flashLane,
  RasterizerPolygons flashSpike,
  RasterizerPolygons halo,
  RasterizerPolygons bolts,
  RasterizerPolygons boltHalo,
  RasterizerPolygons next,
  List<ShapePlace?> places,
});

/// Where an [EndlessTube]'s axis bends: from `bendFrom` to `bendTo` along
/// it, in tube units.
///
/// The axis eases into its bends over the first `ease` units, and out of
/// them over the last `ease` units. Before and after, it goes straight.
typedef TubeCourse = ({double bendFrom, double bendTo, double ease});

/// A Tube Shooter tube that continues straight on along an [EndlessTube]'s
/// axis, with its rim `rim` along the axis, in tube units.
///
/// See [EndlessTube.quadsAt].
typedef NextTube = ({Tube tube, double rim});

/// An endless tube, built as the ship flies along it.
///
/// Its outline is the tube of the view that [quadsAt] takes, so the outline
/// can change from one frame to the next. Its axis bends as [axisAt] says.
///
/// The tube is cut into rings [step] apart along the axis, from [behind]
/// the ship to [ahead] of it. Each [advanceTo] makes the rings that come
/// into that span and drops those that leave it. Each ring turns from the
/// one before as little as the axis allows, so the outline doesn't spin
/// about the axis.
///
/// The eye looks along the axis at the ship's ring from [Tube.eye] behind
/// it. That ring is therefore always where Tube Shooter's rim is on screen,
/// and the tube ahead bends away from it.
///
/// Given a [course], the axis bends only along it and goes straight before
/// and after it. This lets a Tube Shooter tube lead into the endless tube,
/// and another follow it: see [quadsAt].
class EndlessTube({var TubeCourse? course}) {
  /// The distance between two rings along the axis, in tube units.
  static const step = 0.5;

  /// How far in front of the ship the tube goes, in tube units.
  static const ahead = 16.0;

  /// How far behind the ship the tube goes, in tube units: back to the eye,
  /// as anything closer than [TubeView.near] is clipped anyway.
  static const behind = Tube.eye + step;

  /// The distance between two rings drawn across the tube, in tube units: a
  /// multiple of [step].
  static const ringSpacing = 1.0;

  /// How many times as wide as the tube's lines the spikes are.
  static const spikeWidths = 2.0;

  /// How far the axis bends across and down, in tube units, and how long a
  /// stretch one full bend back and forth takes.
  static const bends = (
    across: (amplitude: 4.0, period: 40.0),
    down: (amplitude: 3.0, period: 56.0),
  );

  /// The rings from [behind] the ship to [ahead] of it, by index.
  final _rings = <Ring>[];

  /// Returns where the axis is, [distance] along it, with no [course].
  static Point3 axisAt(double distance) => _axisOf(distance, distance);

  /// Returns the way the axis goes, [distance] along it, with no [course].
  static Point3 forwardAt(double distance) => _forwardOf(distance, 1);

  /// Returns where the axis is, [distance] along it, when it is [bent] far
  /// into its [bends].
  static Point3 _axisOf(double distance, double bent) {
    final (:across, :down) = bends;
    return Point3(
      across.amplitude * math.sin(2 * math.pi * bent / across.period),
      down.amplitude * math.cos(2 * math.pi * bent / down.period),
      distance,
    );
  }

  /// Returns the way the axis goes when it is [bent] far into its [bends],
  /// and goes into them at [rate] times the distance along it.
  static Point3 _forwardOf(double bent, double rate) {
    final (:across, :down) = bends;
    final acrossRate = 2 * math.pi / across.period;
    final downRate = 2 * math.pi / down.period;
    return Point3(
      across.amplitude * acrossRate * math.cos(acrossRate * bent) * rate,
      -down.amplitude * downRate * math.sin(downRate * bent) * rate,
      1,
    ).normalized;
  }

  /// Returns where the axis is, [distance] along it, along its [course].
  Point3 _axisAt(double distance) => _axisOf(distance, _bentAt(distance));

  /// Returns the way the axis goes, [distance] along it, along its [course].
  Point3 _forwardAt(double distance) =>
      _forwardOf(_bentAt(distance), _rateAt(distance));

  /// Returns how far into its [bends] the axis is, [distance] along it.
  ///
  /// With no [course], that is the distance itself. With a course, it is
  /// how far the bends have gone at [_rateAt], from 0 at the course's start.
  double _bentAt(double distance) {
    final course = this.course;
    if (course == null) {
      return distance;
    }
    final (:bendFrom, :bendTo, :ease) = course;
    final into = distance.clamp(bendFrom, bendTo) - bendFrom;
    final left = bendTo - distance.clamp(bendFrom, bendTo);
    final full = bendTo - bendFrom - ease;
    if (into < ease) {
      return ease * _easedArea(into / ease);
    }
    if (left < ease) {
      return full - ease * _easedArea(left / ease);
    }
    return into - ease / 2;
  }

  /// Returns how fast the axis goes into its [bends], [distance] along it,
  /// for each unit along it.
  ///
  /// With no [course], the rate is 1. With a course, it rises from 0 to 1
  /// over the course's first `ease` units, as [_eased] says, and falls back
  /// to 0 over its last `ease` units. Before and after the course, it is 0.
  double _rateAt(double distance) {
    final course = this.course;
    if (course == null) {
      return 1;
    }
    final (:bendFrom, :bendTo, :ease) = course;
    if (distance <= bendFrom || distance >= bendTo) {
      return 0;
    }
    return _eased(
      math.min(1, math.min(distance - bendFrom, bendTo - distance) / ease),
    );
  }

  /// Returns [t], from 0 to 1, eased in and out with no jump in its slope or
  /// in its curvature: Ken Perlin's smootherstep.
  static double _eased(double t) => t * t * t * (t * (6 * t - 15) + 10);

  /// Returns the area under [_eased] from 0 to [t].
  static double _easedArea(double t) => t * t * t * t * (t * (t - 3) + 2.5);

  /// Makes the rings from [behind] the ship to [ahead] of it, with the ship
  /// [distance] along the axis, and drops the rest.
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

  /// Returns the ring at the ship, [distance] along the axis.
  ///
  /// The last [advanceTo] must have made the rings for that distance.
  Ring ringAt(double distance) {
    final index = (distance / step).floor();
    return _turnTo(_rings[index - _rings.first.index], distance, index);
  }

  /// Returns how far to the right of the ring at [distance] the axis points,
  /// [ahead] farther along.
  ///
  /// The result goes from -1, wholly to the ring's left, to 1, wholly to its
  /// right. It is 0 where the axis goes straight on or bends only up or
  /// down. The last [advanceTo] must have made the rings for [distance].
  double bendAt(double distance, double ahead) =>
      _forwardAt(distance + ahead).dot(ringAt(distance).right);

  /// Returns the tube's lines as quads to fill, as the eye sees them round
  /// the outline of [view]'s tube, with the ship [distance] along the axis.
  ///
  /// Each point of the outline draws a line along the tube, and a ring goes
  /// across it every [ringSpacing]. Lines get thinner with distance, as
  /// [TubeView.lineWidthOf] says, and the view clips them closer than
  /// [TubeView.near].
  ///
  /// A closed tube leaves out the lines between faces that the eye sees
  /// from outside, as other faces always hide those from inside the tube.
  /// It also cuts out the parts of each line that the rings before it hide,
  /// as [_Hiders] says. This way, where the tube bends, its nearer walls and
  /// ridges hide what lies beyond. An open tube that goes more than half
  /// round the axis does the same, with a lid across its gap, as [_lidOf]
  /// says. Any other open tube cuts out what its nearer faces hide, as
  /// [_Faces] says, since the eye sees past its ends and under its faces.
  ///
  /// The lines of [lane], if given, go to `lane` instead of `tube`: its two
  /// edges, and its stretch of each ring across it. The [spikes] go to
  /// `spikes`, [spikeWidths] times as wide as the tube's lines, and walls
  /// hide them as they hide the tube's lines. The `places` say where a shape
  /// at each of [marks] shows, or are null where the tube hides it.
  ///
  /// If [flashLane] is given, its lines go to `flashLane` instead, even if
  /// it is [lane]. If [flashSpike], one of [spikes], is given, it goes to
  /// `flashSpike`. With [halo], `halo` gets all of these again, [halo] times
  /// as wide.
  ///
  /// The [bolts] go to `bolts`, zigzagging with [random] as [_boltCorners]
  /// says. With [halo], they also go to `boltHalo`, [halo] times as wide.
  ///
  /// The tube's lines start at [from] along the axis and end at [until],
  /// with no ring across at either end, as Tube Shooter draws its far end
  /// where this tube starts. The rings past [until] hide nothing, as the
  /// tube ends there.
  ///
  /// The lines of a [next] tube go to `next`, drawn as Tube Shooter draws
  /// them: its rim, its far end and the lines between. The rings before
  /// [until] hide them. The [next] tube must be past the [course]'s end, and
  /// so must the last ring that [advanceTo] made.
  TubeQuads quadsAt(
    double distance,
    TubeView view, {
    int? lane,
    List<Spike> spikes = const [],
    List<TubeMark> marks = const [],
    int? flashLane,
    Spike? flashSpike,
    double? halo,
    List<TubeBolt> bolts = const [],
    math.Random? random,
    double from = double.negativeInfinity,
    double until = double.infinity,
    NextTube? next,
  }) {
    final tube = view.tube;
    final ship = ringAt(distance);
    final eye = ship.center - ship.forward * Tube.eye;
    final turn = _turnOf(tube);
    if (!identical(_hidingTube, tube)) {
      _hidingTube = tube;
      _hiding = _hidingOf(tube, turn);
    }
    final hiders = _hiding!..reset();
    // Each ring's outline as seen from the eye: across, down and along the
    // line of sight. A lid's points come after the tube's.
    final seen = [
      for (final ring in _rings)
        [
          for (final point in hiders.points)
            _fromEye(ring.place(point), eye, ship),
        ],
    ];
    // Whether the eye sees each lane's face between a ring and the next from
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
    final lines = _Lines(view);
    final laneLines = _Lines(view);
    final spikeLines = _Lines(view);
    final flashLines = _Lines(view);
    final flashSpikeLines = _Lines(view);
    final haloLines = _Lines(view);
    final boltLines = _Lines(view);
    final boltHaloLines = _Lines(view);
    final places = List<ShapePlace?>.filled(marks.length, null);
    final boltCorners = [
      for (final bolt in bolts) _boltCorners(bolt, distance, tube, random!),
    ];
    // Adds a line of the flash's lane, or of its spike at [widths] times as
    // wide, and the line's halo.
    void addFlash(
      _Lines to,
      Point3 from,
      Point3 end, {
      bool nearer = false,
      double widths = 1,
    }) {
      to.add(from, end, hiders: hiders, nearer: nearer, widths: widths);
      if (halo != null) {
        haloLines.add(
          from,
          end,
          hiders: hiders,
          nearer: nearer,
          widths: halo * widths,
        );
      }
    }

    // Where the eye sees a point of the outline, or the middle of a lane,
    // [at] along the axis, from ring k.
    Point3 seenAt(int k, double at, Offset point) => _fromEye(
      _turnTo(_rings[k], at, _rings[k].index).place(point),
      eye,
      ship,
    );
    final laneEdges = lane == null
        ? const <int>{}
        : {lane, tube.pointAfter(lane)};
    final flashEdges = flashLane == null
        ? const <int>{}
        : {flashLane, tube.pointAfter(flashLane)};
    final every = (ringSpacing / step).round();
    for (var k = 0; k < _rings.length; k++) {
      final near = _rings[k].index * step;
      if (near > until) {
        break;
      }
      final outline = seen[k];
      hiders.pass(outline, _fromEye(_rings[k].center, eye, ship));
      if (k + 1 < _rings.length) {
        final after = seen[k + 1];
        // The part of the lines from this ring to the next that the tube
        // spans, as fractions of the way.
        final lineFrom = (math.max(near, from) - near) / step;
        final lineTo = (math.min(near + step, until) - near) / step;
        for (var i = 0; lineFrom < lineTo && i < tube.points.length; i++) {
          final before = tube.isOpen
              ? i - 1
              : (i + tube.laneCount - 1) % tube.laneCount;
          if (faces(k, before) || faces(k, i)) {
            final a = lineFrom == 0
                ? outline[i]
                : _lerp(outline[i], after[i], lineFrom);
            final b = lineTo == 1
                ? after[i]
                : _lerp(outline[i], after[i], lineTo);
            if (flashEdges.contains(i)) {
              addFlash(flashLines, a, b);
            } else {
              (laneEdges.contains(i) ? laneLines : lines).add(
                a,
                b,
                hiders: hiders,
              );
            }
          }
        }
        for (var j = 0; j < spikes.length; j++) {
          final spike = spikes[j];
          if (!faces(k, spike.lane)) {
            continue;
          }
          final middle = tube.middles[spike.lane];
          final start = math.max(spike.near, near);
          final end = math.min(spike.far, near + step);
          if (start < end) {
            final a = seenAt(k, start, middle);
            final b = seenAt(k, end, middle);
            if (identical(spike, flashSpike)) {
              addFlash(flashSpikeLines, a, b, widths: spikeWidths);
            } else {
              spikeLines.add(a, b, hiders: hiders, widths: spikeWidths);
            }
          }
        }
        for (var j = 0; j < bolts.length; j++) {
          if (!faces(k, bolts[j].lane)) {
            continue;
          }
          final corners = boltCorners[j];
          for (var c = 0; c + 1 < corners.length; c++) {
            final start = corners[c];
            if (start.at < near || start.at >= near + step) {
              continue;
            }
            final end = corners[c + 1];
            final a = seenAt(k, start.at, start.point);
            final b = seenAt(k, end.at, end.point);
            boltLines.add(a, b, hiders: hiders);
            if (halo != null) {
              boltHaloLines.add(a, b, hiders: hiders, widths: halo);
            }
          }
        }
        for (var j = 0; j < marks.length; j++) {
          final mark = marks[j];
          if (mark.at >= near &&
              mark.at < near + step &&
              (faces(k, mark.lane) ||
                  (mark.flip != null && faces(k, mark.flip!.to)))) {
            places[j] = _placeOf(
              mark,
              (at, point) => seenAt(k, at, point),
              tube,
              lines,
              hiders,
            );
          }
        }
      }
      if (_rings[k].index % every == 0 && near > from) {
        for (var i = 0; i < tube.laneCount; i++) {
          if (faces(k - 1, i) || faces(k, i)) {
            final point = outline[i];
            final after = outline[tube.pointAfter(i)];
            if (i == flashLane) {
              addFlash(flashLines, point, after, nearer: true);
            } else {
              (i == lane ? laneLines : lines).add(
                point,
                after,
                hiders: hiders,
                nearer: true,
              );
            }
          }
        }
      }
    }
    final nextLines = _Lines(view);
    if (next != null) {
      // The next tube goes straight on from the last ring, as the axis is
      // past its course there.
      final last = _rings.last;
      final lastAt = last.index * step;
      Point3 seenOn(double at, Offset point) => _fromEye(
        last.center +
            last.right * point.dx +
            last.down * point.dy +
            last.forward * (at - lastAt),
        eye,
        ship,
      );
      final (tube: nextTube, :rim) = next;
      final far = rim + Tube.depth;
      for (final point in nextTube.points) {
        nextLines.add(seenOn(rim, point), seenOn(far, point), hiders: hiders);
      }
      for (var i = 0; i < nextTube.laneCount; i++) {
        final point = nextTube.points[i];
        final after = nextTube.points[nextTube.pointAfter(i)];
        for (final at in [rim, far]) {
          nextLines.add(seenOn(at, point), seenOn(at, after), hiders: hiders);
        }
      }
    }
    return (
      tube: lines.quads,
      lane: laneLines.quads,
      spikes: spikeLines.quads,
      flashLane: flashLines.quads,
      flashSpike: flashSpikeLines.quads,
      halo: haloLines.quads,
      bolts: boltLines.quads,
      boltHalo: boltHaloLines.quads,
      next: nextLines.quads,
      places: places,
    );
  }

  /// Returns how far along the axis the eye sees down the middle of [lane]
  /// of [view]'s tube, with the ship [distance] along the axis.
  ///
  /// The sight ends where the tube first hides a shape in the lane, as
  /// [quadsAt] places shapes. Otherwise it ends at the last ring, or at
  /// [until].
  double sightAlong(
    int lane,
    double distance,
    TubeView view, {
    double until = double.infinity,
  }) {
    final tube = view.tube;
    final ship = ringAt(distance);
    final eye = ship.center - ship.forward * Tube.eye;
    final turn = _turnOf(tube);
    if (!identical(_hidingTube, tube)) {
      _hidingTube = tube;
      _hiding = _hidingOf(tube, turn);
    }
    final hiders = _hiding!..reset();
    final middle = tube.middles[lane];
    List<Point3> outlineOf(Ring ring) => [
      for (final point in hiders.points) _fromEye(ring.place(point), eye, ship),
    ];
    var seen = distance;
    var outline = outlineOf(_rings.first);
    for (var k = 0; k < _rings.length; k++) {
      final ring = _rings[k];
      final near = ring.index * step;
      if (near > until) {
        return until;
      }
      hiders.pass(outline, _fromEye(ring.center, eye, ship));
      if (k + 1 == _rings.length) {
        return math.max(seen, near);
      }
      final after = outlineOf(_rings[k + 1]);
      if (near + step > distance) {
        if (!tube.isOpen &&
            !_facesEye(
              outline[lane],
              outline[tube.pointAfter(lane)],
              after[lane],
              turn,
            )) {
          return seen;
        }
        for (var i = 0; i < _sightSamples; i++) {
          // Samples between the rings, as on a ring an open tube's faces
          // would hide the point.
          final at = near + step * (i + 0.5) / _sightSamples;
          if (at < distance) {
            continue;
          }
          Point3 seenAt(double at) => _fromEye(
            _turnTo(ring, at, ring.index).place(middle),
            eye,
            ship,
          );
          final point = seenAt(at);
          final ahead = seenAt(at + _look);
          if (point.z < TubeView.near || ahead.z < TubeView.near) {
            return seen;
          }
          final count = hiders.spansOf(
            _sight(point),
            _sight(ahead),
            nearer: false,
          );
          if (count == 0 || hiders.spans[0] > 0) {
            return seen;
          }
          seen = at;
        }
      }
      outline = after;
    }
    return seen;
  }

  /// How many evenly spaced points [sightAlong] looks at between each ring
  /// and the next.
  static const _sightSamples = 4;

  /// Returns twice the signed area of [tube]'s outline: its sign says which
  /// way the outline turns.
  static double _turnOf(Tube tube) {
    var turn = 0.0;
    for (var i = 0; i < tube.laneCount; i++) {
      final point = tube.points[i];
      final next = tube.points[tube.pointAfter(i)];
      turn += point.dx * next.dy - point.dy * next.dx;
    }
    return turn;
  }

  /// Returns the point [t] of the way from [a] to [b].
  static Point3 _lerp(Point3 a, Point3 b, double t) => a + (b - a) * t;

  /// The longest stretch a bolt's segment spans along the axis, in tube
  /// units: half a [step], so that each segment lies between two rings.
  static const boltStep = step / 2;

  /// Returns the corners of [bolt], zigzagging as Tube Shooter's bolts do,
  /// from the ship's ring, [near] along the axis, to its far end.
  ///
  /// The bolt is down the middle of its lane at both ends. In between, it
  /// has a corner at every [boltStep] along the axis, on alternate sides of
  /// the lane's middle. Each corner's place is picked with [random] within
  /// the middle third of the lane.
  static List<({double at, Offset point})> _boltCorners(
    TubeBolt bolt,
    double near,
    Tube tube,
    math.Random random,
  ) {
    final (:lane, :far) = bolt;
    final middle = tube.middles[lane];
    final across = (tube.points[tube.pointAfter(lane)] - tube.points[lane]) / 6;
    final corners = [(at: near, point: middle)];
    for (var i = (near / boltStep).floor() + 1; i * boltStep < far; i++) {
      final side = i.isEven ? 1 : -1;
      corners.add((
        at: i * boltStep,
        point: middle + across * (side * (0.4 + 0.6 * random.nextDouble())),
      ));
    }
    corners.add((at: far, point: middle));
    return corners;
  }

  /// How far ahead of a mark, along the axis, [_placeOf] looks for the way
  /// its lane goes.
  static const _look = 0.05;

  /// Returns where a shape at [mark] shows, or null where [hiders] hide its
  /// middle.
  ///
  /// [seenAt] says where the eye sees a point of the outline at some
  /// distance along the axis, and [lines] says where such points land on
  /// screen.
  ///
  /// A flipping shape turns about the corner its two lanes share, as in Tube
  /// Shooter. Its middle goes round the corner through the inside of the
  /// tube, and the shape turns from its lane's direction by the same angle.
  static ShapePlace? _placeOf(
    TubeMark mark,
    Point3 Function(double at, Offset point) seenAt,
    Tube tube,
    _Lines lines,
    _Hiding hiders,
  ) {
    final (:lane, :at, :flip, :across) = mark;
    final laneMiddle = tube.middles[lane];
    var point = laneMiddle;
    if (flip != null) {
      final corner = tube.points[tube.cornerOf(lane, flip.to)];
      point = corner + Tube.rotate(laneMiddle - corner, flip.turn);
    } else if (across != null) {
      // Kept just inside the lane, so that its walls don't hide a shape on
      // an edge.
      point = Offset.lerp(
        tube.points[lane],
        tube.points[tube.pointAfter(lane)],
        across.clamp(0.03, 0.97),
      )!;
    }
    final onMiddle = flip == null && across == null;
    final middle = seenAt(at, point);
    final ahead = seenAt(at + _look, point);
    final laneAt = onMiddle ? middle : seenAt(at, laneMiddle);
    final laneAhead = onMiddle ? ahead : seenAt(at + _look, laneMiddle);
    final corner = seenAt(at, tube.points[lane]);
    final nextCorner = seenAt(at, tube.points[tube.pointAfter(lane)]);
    if ([
      middle,
      ahead,
      laneAt,
      laneAhead,
      corner,
      nextCorner,
    ].any((p) => p.z < TubeView.near)) {
      return null;
    }
    final count = hiders.spansOf(_sight(middle), _sight(ahead), nearer: false);
    if (count == 0 || hiders.spans[0] > 0) {
      return null;
    }
    final position = lines._project(middle);
    final laneWay = lines._project(laneAhead) - lines._project(laneAt);
    return (
      position: position,
      // The shape's tail, along its y, points away along the lane, turned by
      // the flip.
      angle: laneWay.direction - math.pi / 2 + (flip?.turn ?? 0),
      // The same in every lane, as in Tube Shooter: [Tube.laneWidth] at the
      // mark's distance.
      scale:
          (lines._project(nextCorner) - lines._project(corner)).distance *
          tube.laneWidth /
          (tube.points[tube.pointAfter(lane)] - tube.points[lane]).distance,
    );
  }

  /// The last tube that [quadsAt] drew, and what hides its lines.
  Tube? _hidingTube;
  _Hiding? _hiding;

  /// Returns what hides the lines of [tube]: its rings, with a lid if it has
  /// one, or else its faces.
  ///
  /// The signed area of the tube's outline has [turn]'s sign.
  static _Hiding _hidingOf(Tube tube, double turn) {
    if (!tube.isOpen) {
      return _Hiders(tube.points, turn);
    }
    final lid = _lidOf(tube);
    return lid == null ? _Faces(tube) : _Hiders(lid, turn);
  }

  /// How far from the axis a lid is, in tube units: see [_lidOf].
  static const _lidRadius = 4.0;

  /// Returns the outline of the open [tube] with a lid across its gap, or
  /// null unless the tube goes more than half round the axis, as the
  /// Horseshoe does.
  ///
  /// The outline is the tube's points, then points [_lidRadius] from the
  /// axis, at most an eighth of a turn apart, round the rest of the way.
  ///
  /// The rings of such a tube hide what lies beyond its walls, as a closed
  /// tube's rings do. Without the lid, they would also hide what the eye
  /// sees through the gap. With the lid, they hide only what the eye sees
  /// through the gap farther out than the lid, which is little as the tube
  /// bends. That costs less than hiding with the faces, as [_Faces] does,
  /// and makes about as few mistakes as a closed tube's rings. The lid's
  /// lines aren't drawn.
  static List<Offset>? _lidOf(Tube tube) {
    final points = tube.points;
    var sweep = 0.0;
    for (var i = 0; i + 1 < points.length; i++) {
      var angle = points[i + 1].direction - points[i].direction;
      angle -= 2 * math.pi * (angle / (2 * math.pi)).roundToDouble();
      sweep += angle;
    }
    if (sweep.abs() <= math.pi) {
      return null;
    }
    final rest = sweep.sign * (2 * math.pi - sweep.abs());
    final count = (rest.abs() / (math.pi / 4)).ceil();
    final start = points.last.direction;
    return [
      ...points,
      for (var i = 0; i <= count; i++)
        Offset.fromDirection(start + rest * i / count, _lidRadius),
    ];
  }

  /// How much bigger than each ring the window that the eye sees through it
  /// is, so that the ring's own lines on its edge stay whole.
  static const _windowSlack = 1.002;

  /// The smallest turn at a point for which [_hullOf] keeps the point, so
  /// that rounding errors don't keep points where the outline goes straight
  /// on.
  static const _leastTurn = 1e-9;

  /// Returns where the eye, at the origin, sees [point] on a plane 1 unit in
  /// front of it: across and down.
  static Offset _sight(Point3 point) =>
      Offset(point.x / point.z, point.y / point.z);

  /// Returns the indices of the convex hull of [points], a closed outline
  /// whose signed area has [turn]'s sign, in an order whose signed area is
  /// positive.
  ///
  /// It drops the points where the outline turns inward or goes straight
  /// on, until none are left. That yields the hull for outlines that wind
  /// round their middle, as the tubes' outlines do.
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
  /// face that spans [corner], [along] and [ahead].
  ///
  /// [along] is the outline's next point after [corner], and [ahead] is the
  /// same point as [corner] on the next ring. The outline's signed area has
  /// [turn]'s sign.
  static bool _facesEye(
    Point3 corner,
    Point3 along,
    Point3 ahead,
    double turn,
  ) {
    final outward = (along - corner).cross(ahead - corner) * turn;
    return outward.dot(corner) > 0;
  }

  /// Returns [point] as the eye at [eye] sees it when looking the way [ship]
  /// faces: across, down and along the line of sight.
  static Point3 _fromEye(Point3 point, Point3 eye, Ring ship) {
    final offset = point - eye;
    return Point3(
      offset.dot(ship.right),
      offset.dot(ship.down),
      offset.dot(ship.forward),
    );
  }

  /// Returns the ring at [index], whose outline's x goes to the right.
  Ring _startRing(int index) {
    final forward = _forwardAt(index * step);
    final right = (const Point3(1, 0, 0) - forward * forward.x).normalized;
    return Ring(
      index,
      _axisAt(index * step),
      forward,
      right,
      forward.cross(right),
    );
  }

  /// Returns the ring [distance] along the axis, at [index], turned from
  /// [from] as little as the axis allows.
  ///
  /// This is the double reflection method for rotation minimizing frames, by
  /// Wang, Jüttler, Zheng and Liu (2008).
  Ring _turnTo(Ring from, double distance, int index) {
    final center = _axisAt(distance);
    final forward = _forwardAt(distance);
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

/// Lines in 3D as seen from the eye, made into [quads] to fill, as Tube
/// Shooter's `TubeView` makes its lines.
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

  /// How far the lines move right and down: a sixteenth of a device pixel,
  /// as in `TubeView` and for the same reason.
  late final _lineOffset = Offset(view.devicePixel / 16, view.devicePixel / 16);

  /// Adds a line from [from] to [to], as a quad.
  ///
  /// Each end is [widths] times as wide as the tube's line at its distance,
  /// as [TubeView.tubeLineWidthOf] says. Each end also extends by half that
  /// width, so that lines meeting at a corner close it.
  ///
  /// It clips the line closer than [TubeView.near], and leaves out the
  /// parts that [hiders] hide, if given: the parts the rings before the line
  /// hide. With [nearer], for a line on the last ring passed to [hiders],
  /// it leaves out the parts that the rings before that ring hide.
  void add(
    Point3 from,
    Point3 to, {
    _Hiding? hiders,
    bool nearer = false,
    double widths = 1,
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
      _addLine(a, b, widths);
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
      _addLine(at(spans[2 * s]), at(spans[2 * s + 1]), widths);
    }
  }

  /// Adds a line from [a] to [b], both at least [TubeView.near] away, as a
  /// quad [widths] times as wide as a tube's line.
  void _addLine(Point3 a, Point3 b, double widths) => _addQuad(
    _project(a),
    widths * view.tubeLineWidthOf(a.z),
    _project(b),
    widths * view.tubeLineWidthOf(b.z),
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

/// What hides the tube's lines behind its nearer parts, as the eye sees them
/// on a plane 1 unit away.
///
/// `EndlessTube.quadsAt` passes it the rings of its [points] from the eye
/// out, and asks it which spans of each line the eye sees. It keeps its
/// buffers from one frame to the next, so that it allocates nothing per
/// line.
abstract class _Hiding(final List<Offset> points) {
  /// The spans of the line that [spansOf] last counted: where each starts
  /// and ends, from 0 to 1 along the line.
  Float64List spans = Float64List(2);
  var _spareSpans = Float64List(2);

  /// The span that [_clip] narrows, and that [_cut] cuts out: where it
  /// starts and ends.
  var _start = 0.0;
  var _end = 1.0;

  /// Starts a new frame, before the nearest ring.
  void reset();

  /// Passes the next ring out from the eye: its [outline], where the eye
  /// sees each of [points] round it, and its [center].
  void pass(List<Point3> outline, Point3 center);

  /// Returns how many [spans] of the line from [a] to [b] the eye sees past
  /// the rings passed so far, or with [nearer], past those before the last
  /// one.
  int spansOf(Offset a, Offset b, {required bool nearer});

  /// Makes room in [spans] for as many spans as [count] hiders can cut a
  /// line into. Each hider cuts at most one span in two.
  void _roomForSpans(int count) {
    if (spans.length >= 2 * (count + 1)) {
      return;
    }
    spans = Float64List(2 * (count + 1));
    _spareSpans = Float64List(2 * (count + 1));
  }

  /// Cuts the span from [_start] to [_end] out of each of the first [length]
  /// [spans], and returns how many are left.
  int _cut(int length) {
    final spans = this.spans;
    final spare = _spareSpans;
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
    this.spans = spare;
    _spareSpans = spans;
    return cut;
  }

  /// Narrows the span from [_start] to [_end] of the line from [a] along
  /// [line] to its part inside a convex polygon, with the Cyrus-Beck
  /// algorithm.
  ///
  /// The polygon has [length] points at [offset] in [points], and a positive
  /// signed area. Returns false if nothing is left.
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

  /// The smallest squared length of an edge that [_clip] clips to. Rounding
  /// errors leave shorter edges, which can point any way.
  static const _leastEdgeSquared = 1e-14;
}

/// What the rings of a closed tube hide of the lines beyond them, as the eye
/// sees them on a plane 1 unit away.
///
/// The rings hide everything outside the window through which the eye sees
/// past all the rings so far. They also hide what lies in the notches
/// between each ring's outline and its convex hull, behind the tube's
/// ridges.
///
/// Its [points] are the closed outline of the tube, or of an open tube and
/// its lid. Their signed area has [turn]'s sign.
class _Hiders(super.points, final double turn) extends _Hiding {
  /// The outline's convex hull, as indices in an order whose signed area is
  /// positive.
  late final _hull = EndlessTube._hullOf(points, turn);

  /// The outline's notches, as [_notchesOf] returns them.
  late final _notches = _notchesOf(points, _hull, turn);

  /// Where the eye sees each point of the ring last passed, grown about the
  /// ring's middle by `EndlessTube._windowSlack`: x then y.
  late final _ring = Float64List(2 * points.length);

  /// The window as a convex polygon with a positive signed area: its points,
  /// x then y, and how many there are, or -1 while no ring hides anything.
  var _window = Float64List(64);
  var _windowLength = -1;

  /// The window's bounds: left, top, right and bottom.
  final _windowBounds = Float64List(4);

  /// Where [_intersectRing] puts each step's result, and how far inside an
  /// edge each point is, scaled by the edge's length.
  var _spare = Float64List(64);
  var _sides = Float64List(32);

  /// The window, its number of points and the number of live notches from
  /// before the last ring was passed, for the lines across that ring.
  var _nearerWindow = Float64List(64);
  var _nearerLength = -1;
  var _nearerCount = 0;

  /// How many numbers a notch takes in [_notchPoints]: 2 for each point of
  /// the longest one.
  late final _stride =
      2 * _notches.fold<int>(3, (most, notch) => math.max(most, notch.length));

  /// The notches made so far this frame, by slot:
  /// - their points, x then y, [_stride] apart;
  /// - how many points each notch has;
  /// - their bounds: left, top, right and bottom.
  var _notchPoints = Float64List(0);
  var _notchLengths = Int32List(0);
  var _notchBounds = Float64List(0);
  var _slots = 0;

  /// The slots of the notches whose bounds still overlap the window's,
  /// nearest first, and how many.
  var _live = Int32List(0);
  var _liveCount = 0;

  @override
  void reset() {
    _windowLength = -1;
    _nearerLength = -1;
    _nearerCount = 0;
    _slots = 0;
    _liveCount = 0;
  }

  /// A ring hides something only when all of its outline is at least
  /// [TubeView.near] away. Only the rings nearest the eye fall short of that,
  /// and nothing nearer than them hides anything anyway.
  @override
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

  @override
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
      if (_clip(_notchPoints, _stride * slot, _notchLengths[slot], a, line)) {
        length = _cut(length);
      }
    }
    return length;
  }

  /// Drops the notches whose bounds no longer overlap the window's. As the
  /// window only shrinks, such notches hide nothing that the window doesn't
  /// already hide.
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

  /// Narrows the window to the hull of the ring last passed, with the
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
    _roomForSpans(room);
  }

  /// Returns whether the bounds at [offset] in [bounds] overlap the
  /// window's.
  bool _overlapsWindow(Float64List bounds, int offset) =>
      bounds[offset] <= _windowBounds[2] &&
      bounds[offset + 1] <= _windowBounds[3] &&
      bounds[offset + 2] >= _windowBounds[0] &&
      bounds[offset + 3] >= _windowBounds[1];

  /// Returns [list] if it holds at least [length] numbers, or else a new,
  /// longer list of zeros.
  static Float64List _fit(Float64List list, int length) => list.length >= length
      ? list
      : Float64List(math.max(length, 2 * list.length));

  /// Returns the notches between [points] and its convex [hull], each as the
  /// indices of a convex polygon with a positive signed area.
  ///
  /// The [points] are a closed outline whose signed area has [turn]'s sign.
  /// Each notch runs along the outline from one point of the hull to the
  /// next, and back along the hull. The points where a notch goes straight
  /// on are left out.
  ///
  /// A notch that isn't convex is split as [_convexPiecesOf] says. No closed
  /// tube has such a notch, but a lid's notches beside the tube's walls are
  /// not convex.
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
      notches.addAll(
        _convexPiecesOf(points, area < 0 ? notch.reversed.toList() : notch),
      );
    }
    return notches;
  }

  /// Returns convex polygons that cover [polygon], each with a positive
  /// signed area.
  ///
  /// The [polygon] holds the indices of a simple polygon of [points] with a
  /// positive signed area. If it is convex, the result is the polygon
  /// itself.
  ///
  /// Otherwise, it fans the polygon out from a corner that sees all the
  /// others, as the corners of a lid's notch see each other from the lid.
  /// It then joins neighbouring triangles of the fan as long as they stay
  /// convex. If no corner sees all the others, it returns no polygons, so
  /// the notch hides nothing.
  static List<List<int>> _convexPiecesOf(
    List<Offset> points,
    List<int> polygon,
  ) {
    bool turnsLeft(int before, int point, int after) =>
        _cross(
          points[point] - points[before],
          points[after] - points[point],
        ) >=
        0;
    final count = polygon.length;
    var convex = true;
    for (var k = 0; k < count && convex; k++) {
      convex = turnsLeft(
        polygon[(k + count - 1) % count],
        polygon[k],
        polygon[(k + 1) % count],
      );
    }
    if (convex) {
      return [polygon];
    }
    for (var apex = 0; apex < count; apex++) {
      final origin = polygon[apex];
      final fan = [for (var k = 1; k < count; k++) polygon[(apex + k) % count]];
      var seesAll = true;
      for (var k = 0; k + 1 < fan.length && seesAll; k++) {
        seesAll =
            _cross(
              points[fan[k]] - points[origin],
              points[fan[k + 1]] - points[origin],
            ) >
            0;
      }
      if (!seesAll) {
        continue;
      }
      final pieces = <List<int>>[];
      var piece = [origin, fan[0], fan[1]];
      for (var k = 2; k < fan.length; k++) {
        final point = fan[k];
        if (turnsLeft(piece[piece.length - 2], piece.last, point) &&
            turnsLeft(piece.last, point, origin) &&
            turnsLeft(point, origin, piece[1])) {
          piece.add(point);
        } else {
          pieces.add(piece);
          piece = [origin, piece.last, point];
        }
      }
      return pieces..add(piece);
    }
    return const [];
  }
}

/// What the faces of an open tube hide of the lines beyond them, as the eye
/// sees them on a plane 1 unit away.
///
/// Each face is a lane's face between two rings, as the eye sees its
/// corners, clipped closer than [TubeView.near].
///
/// The eye sees past an open tube's ends, and so under its faces. There,
/// the rings can't hide what lies beyond them as a closed tube's rings do.
/// A line between two rings is hidden by the faces between the rings before
/// it, nearest first. Given how the axis bends, the faces beyond the line
/// never hide it. The faces between the line's own two rings don't hide it
/// either, so a ridge's faces don't hide each other there.
class _Faces(final Tube tube) extends _Hiding {
  this : super(tube.points);

  /// How many numbers a face takes in [_facePoints]: 2 for each of at most 5
  /// points, the most that a quad clipped closer than [TubeView.near] has.
  static const _stride = 10;

  /// The faces between the rings passed so far, nearest first:
  /// - their points, x then y, [_stride] apart, in an order whose signed
  ///   area is positive;
  /// - how many points each face has;
  /// - their bounds: left, top, right and bottom.
  var _facePoints = Float64List(0);
  var _faceLengths = Int32List(0);
  var _faceBounds = Float64List(0);

  /// How many faces lie between the rings passed so far, and between those
  /// before the last one.
  var _count = 0;
  var _nearerCount = 0;

  /// The outline of the ring last passed, if any this frame.
  List<Point3>? _last;

  /// A face's corners as seen from the eye, x, y and z, and the at most 5
  /// corners left after clipping the face closer than [TubeView.near].
  final _corners = Float64List(12);
  final _clipped = Float64List(15);

  @override
  void reset() {
    _count = 0;
    _nearerCount = 0;
    _last = null;
  }

  @override
  void pass(List<Point3> outline, Point3 center) {
    _nearerCount = _count;
    final last = _last;
    _last = outline;
    if (last == null) {
      return;
    }
    _grow(_count + tube.laneCount);
    for (var i = 0; i < tube.laneCount; i++) {
      final after = tube.pointAfter(i);
      _add(last[i], last[after], outline[after], outline[i]);
    }
  }

  @override
  int spansOf(Offset a, Offset b, {required bool nearer}) {
    final count = nearer ? _nearerCount : _count;
    final line = b - a;
    spans[0] = 0;
    spans[1] = 1;
    var length = 1;
    final left = math.min(a.dx, b.dx);
    final right = math.max(a.dx, b.dx);
    final top = math.min(a.dy, b.dy);
    final bottom = math.max(a.dy, b.dy);
    final bounds = _faceBounds;
    for (var f = 0; f < count && length > 0; f++) {
      final o = 4 * f;
      if (bounds[o] > right ||
          bounds[o + 1] > bottom ||
          bounds[o + 2] < left ||
          bounds[o + 3] < top) {
        continue;
      }
      _start = spans[0];
      _end = spans[2 * length - 1];
      if (_clip(_facePoints, _stride * f, _faceLengths[f], a, line)) {
        length = _cut(length);
      }
    }
    return length;
  }

  /// Adds the face with the corners [a], [b], [c] and [d], as seen from the
  /// eye, clipped closer than [TubeView.near], unless nothing of it is left.
  void _add(Point3 a, Point3 b, Point3 c, Point3 d) {
    final corners = _corners;
    _put(0, a);
    _put(1, b);
    _put(2, c);
    _put(3, d);
    // The Sutherland-Hodgman algorithm, against the near plane.
    final clipped = _clipped;
    var length = 0;
    for (var i = 0; i < 4; i++) {
      final from = 3 * i;
      final to = 3 * ((i + 1) % 4);
      final fromIn = corners[from + 2] >= TubeView.near;
      if (fromIn) {
        clipped.setRange(3 * length, 3 * length + 3, corners, from);
        length++;
      }
      if (fromIn != (corners[to + 2] >= TubeView.near)) {
        final t =
            (TubeView.near - corners[from + 2]) /
            (corners[to + 2] - corners[from + 2]);
        for (var j = 0; j < 3; j++) {
          clipped[3 * length + j] =
              corners[from + j] + (corners[to + j] - corners[from + j]) * t;
        }
        length++;
      }
    }
    if (length < 3) {
      return;
    }
    final points = _facePoints;
    final o = _stride * _count;
    var area = 0.0;
    for (var i = 0; i < length; i++) {
      final z = clipped[3 * i + 2];
      points[o + 2 * i] = clipped[3 * i] / z;
      points[o + 2 * i + 1] = clipped[3 * i + 1] / z;
    }
    for (var i = 0; i < length; i++) {
      final j = (i + 1) % length;
      area +=
          points[o + 2 * i] * points[o + 2 * j + 1] -
          points[o + 2 * j] * points[o + 2 * i + 1];
    }
    if (area.abs() < _leastArea) {
      return;
    }
    if (area < 0) {
      for (var i = 0, j = length - 1; i < j; i++, j--) {
        for (var k = 0; k < 2; k++) {
          final swap = points[o + 2 * i + k];
          points[o + 2 * i + k] = points[o + 2 * j + k];
          points[o + 2 * j + k] = swap;
        }
      }
    }
    _boundsOf(points, o, length, _faceBounds, 4 * _count);
    _faceLengths[_count++] = length;
  }

  /// Puts [corner] into [_corners] as the corner at [index].
  void _put(int index, Point3 corner) {
    _corners[3 * index] = corner.x;
    _corners[3 * index + 1] = corner.y;
    _corners[3 * index + 2] = corner.z;
  }

  /// The smallest area, as the eye sees it, of a face that hides anything.
  /// A face seen edge on hides nothing.
  static const _leastArea = 1e-12;

  /// Makes room for [count] faces, and for the spans they can cut a line
  /// into.
  void _grow(int count) {
    if (_faceLengths.length >= count) {
      return;
    }
    final room = math.max(count, 2 * _faceLengths.length);
    _facePoints = Float64List(_stride * room)..setAll(0, _facePoints);
    _faceLengths = Int32List(room)..setAll(0, _faceLengths);
    _faceBounds = Float64List(4 * room)..setAll(0, _faceBounds);
    _roomForSpans(room);
  }
}

/// Puts the bounds of the [length] points at [offset] in [points] into
/// [bounds] at [at]: left, top, right and bottom.
void _boundsOf(
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

/// Returns the cross product of [a] and [b]: positive if [b] turns from [a]
/// the way the outlines with a positive signed area turn.
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
