import 'dart:math' as math;
import 'dart:ui';

/// A tube, in tube units.
///
/// The outline's [points] lie round the tube's axis, at most 1 from it across
/// and down, and go round to the right along the bottom. Each point starts a
/// lane, and all the lanes are as wide. A closed tube's last lane goes back to
/// its first point. An open tube's last point only ends its last lane, and the
/// ship stops there.
///
/// Every tube is [depth] deep, from its rim, at 0, to its far end. The eye is
/// on the axis, [eye] in front of the rim, so the far end looks
/// (eye + depth) / eye, 3.8, times smaller than the rim.
///
/// A lane's angle turns a shape's x axis along the lane, and its y axis
/// toward the inside of the tube, which is deeper.
class Tube(
  final String name,
  final List<Offset> points, {
  final bool isOpen = false,
}) {
  /// A closed regular polygon of [sides] sides, with [lanes] lanes a side and
  /// its first corner at angle [first].
  factory Tube.polygon(String name, int sides, int lanes, double first) {
    final turn = 2 * math.pi / sides;
    return Tube(
      name,
      _closed([
        for (var k = 0; k < sides; k++) Offset.fromDirection(first - k * turn),
      ], lanes),
    );
  }

  /// A closed star of [tips] tips, with [lanes] lanes an edge. Its inner
  /// corners are [ratio] as far from the axis as its tips, the first inner
  /// one at angle [first].
  factory Tube.star(
    String name,
    int tips,
    double ratio,
    int lanes,
    double first,
  ) {
    final turn = math.pi / tips;
    return Tube(
      name,
      _closed([
        for (var k = 0; k < 2 * tips; k++)
          Offset.fromDirection(first - k * turn, k.isEven ? ratio : 1),
      ], lanes),
    );
  }

  /// An open arc of [lanes] lanes, 1 from the axis, from angle [start] through
  /// [sweep].
  factory Tube.arc(String name, double start, double sweep, int lanes) =>
      Tube(name, [
        for (var i = 0; i <= lanes; i++)
          Offset.fromDirection(start - sweep * i / lanes),
      ], isOpen: true);

  /// An open outline through [corners], with [lanes] lanes between each two.
  factory Tube.polyline(String name, List<Offset> corners, int lanes) =>
      Tube(name, [
        for (var k = 0; k + 1 < corners.length; k++)
          ..._split(corners[k], corners[k + 1], lanes),
        corners.last,
      ], isOpen: true);

  static const depth = 2.8;
  static const eye = 1.0;

  /// How many lanes it has.
  late final int laneCount = isOpen ? points.length - 1 : points.length;

  /// The lanes' middles, at the rim.
  late final List<Offset> middles = [
    for (var i = 0; i < laneCount; i++) (points[i] + points[pointAfter(i)]) / 2,
  ];

  /// Each lane's angle, from its second point to its first.
  late final List<double> angles = [
    for (var i = 0; i < laneCount; i++)
      (points[i] - points[pointAfter(i)]).direction,
  ];

  /// A lane's width, at the rim.
  late final double laneWidth = (points[1] - points[0]).distance;

  /// The lane closest to straight below the axis, where the ship starts; the
  /// first one, if several are as close.
  late final int bottomLane = _bottomLane();

  /// Where the camera looks, in tube units: a closed tube's axis, or the
  /// middle of an open tube's drawing, from its rim to its far end.
  late final Offset center = isOpen
      ? (Path()..addPolygon([
              ...points,
              for (final point in points) point * (eye / (eye + depth)),
            ], false))
            .getBounds()
            .center
      : Offset.zero;

  /// The point that ends [lane].
  int pointAfter(int lane) => isOpen ? lane + 1 : (lane + 1) % laneCount;

  /// The lane on [side], 1 or -1, of [lane], or null past an open tube's end.
  int? neighbour(int lane, int side) => _within(lane + side, laneCount);

  /// The point on [side], 1 or -1, of [point], or null past an open tube's
  /// end.
  int? pointBeside(int point, int side) => _within(point + side, points.length);

  /// The point that lane [from] and its neighbour [to] share.
  int cornerOf(int from, int to) => to == pointAfter(from) ? to : from;

  /// The angle a shape in lane [from] turns by, about the corner it shares
  /// with lane [to], to flip onto [to] through the inside of the tube.
  ///
  /// The angle is half a turn along a side, less round a convex corner, and
  /// more round a concave one. The shape lands half a turn off [to]'s angle.
  double flipAngle(int from, int to) {
    final corner = points[cornerOf(from, to)];
    final start = middles[from] - corner;
    final end = middles[to] - corner;
    final angle = (end.direction - start.direction) % (2 * math.pi);
    // Turning clockwise, the lane's middle first moves a quarter turn on from
    // where it is. If that's not toward the inside of the lane, its y axis,
    // the flip turns the other way.
    final inside = rotate(const Offset(0, 1), angles[from]);
    final first = rotate(start, math.pi / 2);
    return first.dx * inside.dx + first.dy * inside.dy > 0
        ? angle
        : angle - 2 * math.pi;
  }

  /// [index] wrapped round a closed tube's [count], or null outside an open
  /// tube's.
  int? _within(int index, int count) {
    if (!isOpen) {
      return index % count;
    }
    return index >= 0 && index < count ? index : null;
  }

  int _bottomLane() {
    var lane = 0;
    var least = double.infinity;
    for (var i = 0; i < laneCount; i++) {
      final off = math.atan2(middles[i].dx, middles[i].dy).abs();
      if (off < least - 1e-9) {
        lane = i;
        least = off;
      }
    }
    return lane;
  }

  /// [offset] turned by [angle], clockwise on screen.
  static Offset rotate(Offset offset, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(
      offset.dx * cos - offset.dy * sin,
      offset.dx * sin + offset.dy * cos,
    );
  }

  /// [from], and the points after it that split the way to [to] into [lanes]
  /// lanes.
  static List<Offset> _split(Offset from, Offset to, int lanes) => [
    for (var i = 0; i < lanes; i++) Offset.lerp(from, to, i / lanes)!,
  ];

  /// The points of a closed outline through [corners], with [lanes] lanes an
  /// edge, scaled to reach 1 from the axis, across or down.
  static List<Offset> _closed(List<Offset> corners, int lanes) {
    final points = [
      for (var k = 0; k < corners.length; k++)
        ..._split(corners[k], corners[(k + 1) % corners.length], lanes),
    ];
    final reach = points
        .map((point) => math.max(point.dx.abs(), point.dy.abs()))
        .reduce(math.max);
    return [for (final point in points) point / reach];
  }
}

/// The game's tubes: closed and open ones, some of each concave.
abstract final class Tubes() {
  static final octagon = Tube.polygon('Octagon', 8, 2, 5 * math.pi / 8);
  static final hexagon = Tube.polygon('Hexagon', 6, 2, 2 * math.pi / 3);
  static final floor = Tube.polyline('Floor', const [
    Offset(-1, 1),
    Offset(1, 1),
  ], 8);
  static final diamond = Tube.polygon('Diamond', 4, 4, math.pi / 2);
  static final star = Tube.star('Star', 5, 0.5, 2, math.pi / 2);
  static final horseshoe = Tube.arc(
    'Horseshoe',
    5 * math.pi / 4,
    3 * math.pi / 2,
    12,
  );
  static final cog = Tube.star('Cog', 9, 0.8, 1, math.pi / 2);
  static final ridge = Tube.polyline('Ridge', const [
    Offset(-1, 1),
    Offset(0, 0.6),
    Offset(1, 1),
  ], 4);

  static final all = [
    octagon,
    hexagon,
    floor,
    diamond,
    star,
    horseshoe,
    cog,
    ridge,
  ];

  /// The widest lane of any tube, and the most lanes any tube has.
  static final widestLane = all.map((tube) => tube.laneWidth).reduce(math.max);
  static final mostLanes = all.map((tube) => tube.laneCount).reduce(math.max);
}

/// How the game projects its [tube] into the world.
///
/// In play, the rim is [rimScale] times its size in tube units, with lines
/// [rimPixels] device pixels wide. Lines get thinner with depth, but never
/// under a device pixel. On the zoom and the drop, [eyeShift] moves the eye
/// along the axis.
///
/// Each change bumps [version], so that the game makes the view's paths
/// again.
class TubeView() {
  /// The width of the tube's lines and of the shapes' strokes at the rim in
  /// play, in device pixels.
  static const rimPixels = 4.0;

  /// The closest to the eye that lines are drawn, in tube units; the view
  /// clips anything closer.
  static const near = 0.2 * Tube.eye;

  /// The tube it projects.
  Tube get tube => _tube;
  Tube _tube = Tubes.octagon;

  /// The world units that a tube unit at the rim takes in play.
  double get rimScale => _rimScale;
  double _rimScale = 1;

  /// The world units in a device pixel.
  double get devicePixel => _devicePixel;
  double _devicePixel = 1;

  /// How far the eye has moved into the tube from where it is in play, in
  /// tube units; negative while it zooms in.
  double get eyeShift => _eyeShift;
  double _eyeShift = 0;

  /// Bumped by each change.
  int get version => _version;
  int _version = 0;

  /// Fits the rim in play within [fit] world units, with [pixel] world units
  /// in a device pixel.
  void fit(double fit, double pixel) {
    if (fit == _rimScale * 2 && pixel == _devicePixel) {
      return;
    }
    _rimScale = fit / 2;
    _devicePixel = pixel;
    _version++;
  }

  set tube(Tube value) {
    if (!identical(value, _tube)) {
      _tube = value;
      _version++;
    }
  }

  set eyeShift(double value) {
    if (value != _eyeShift) {
      _eyeShift = value;
      _version++;
    }
  }

  /// Bumps [version] for a change outside the view, so that the game makes
  /// the view's paths again.
  void invalidate() => _version++;

  /// How far from the eye [depth] is, in tube units.
  double distanceOf(double depth) => Tube.eye + depth - _eyeShift;

  /// The world units that a tube unit at [depth] takes.
  double scaleAt(double depth) => scaleOf(distanceOf(depth));

  /// The world units that a tube unit [distance] from the eye takes.
  double scaleOf(double distance) => _rimScale * Tube.eye / distance;

  /// Where an outline [point] at [depth] lands in the world.
  Offset project(Offset point, double depth) => point * scaleAt(depth);

  /// The width of a line at [depth]: [rimPixels] device pixels at the rim in
  /// play, and never under one device pixel.
  double lineWidthAt(double depth) => lineWidthOf(distanceOf(depth));

  /// The width of a line [distance] from the eye, as for [lineWidthAt].
  double lineWidthOf(double distance) =>
      math.max(_devicePixel, rimPixels * _devicePixel * Tube.eye / distance);

  /// The width of the shapes' strokes, in lane units: [rimPixels] device
  /// pixels at the rim in play. A shape's scale is its lane's width, so its
  /// strokes get thinner with depth, as the tube's lines do.
  double get shapeStroke =>
      rimPixels * _devicePixel / (tube.laneWidth * _rimScale);

  /// The tube's lines, as filled quads: its spokes, its rim and its far end.
  Path tubePath() {
    final path = Path();
    for (final point in tube.points) {
      _addLine(path, point, 0, point, Tube.depth);
    }
    for (var i = 0; i < tube.laneCount; i++) {
      final point = tube.points[i];
      final next = tube.points[tube.pointAfter(i)];
      _addLine(path, point, 0, next, 0);
      _addLine(path, point, Tube.depth, next, Tube.depth);
    }
    return path;
  }

  /// The 4 lines round [lane], as quads like [tubePath]'s.
  Path lanePath(int lane) {
    final point = tube.points[lane];
    final next = tube.points[tube.pointAfter(lane)];
    final path = Path();
    _addLine(path, point, 0, point, Tube.depth);
    _addLine(path, next, 0, next, Tube.depth);
    _addLine(path, point, 0, next, 0);
    _addLine(path, point, Tube.depth, next, Tube.depth);
    return path;
  }

  /// The spikes of [lengths], each reaching from the far end toward the rim,
  /// as lines like [tubePath]'s.
  Path spikesPath(List<double> lengths) {
    final path = Path();
    for (var i = 0; i < tube.laneCount; i++) {
      if (lengths[i] > 0) {
        final middle = tube.middles[i];
        _addLine(path, middle, Tube.depth, middle, Tube.depth - lengths[i]);
      }
    }
    return path;
  }

  /// The most depth that a segment of a bolt spans.
  static const boltStep = Tube.depth / 10;

  /// Bolts down the middles of the lanes of [bolts], each from its depth to
  /// the rim, as lines like [tubePath]'s.
  ///
  /// Each bolt zigzags, with a segment every [boltStep] at most, and corners
  /// at random places across the middle third of its lane.
  Path boltsPath(Iterable<(int, double)> bolts, math.Random random) {
    final path = Path();
    for (final (lane, depth) in bolts) {
      final middle = tube.middles[lane];
      final across =
          (tube.points[tube.pointAfter(lane)] - tube.points[lane]) / 6;
      final count = math.max(2, (depth / boltStep).ceil());
      var (from, fromDepth) = (middle, depth);
      for (var i = 1; i <= count; i++) {
        final toDepth = depth * (1 - i / count);
        final side = i.isEven ? 1 : -1;
        final to = i == count
            ? middle
            : middle + across * (side * (0.4 + 0.6 * random.nextDouble()));
        _addLine(path, from, fromDepth, to, toDepth);
        (from, fromDepth) = (to, toDepth);
      }
    }
    return path;
  }

  /// How far the lines are moved right and down: a sixteenth of a device
  /// pixel.
  ///
  /// With 4x MSAA, an edge's coverage changes a quarter of a pixel at a time,
  /// as it crosses rows of samples a quarter of a pixel apart. A tapering line
  /// whose axis lies on a pixel's edge or middle would have both edges cross a
  /// row at once, so its width would jump by half a pixel. A sixteenth off,
  /// its edges cross the rows in turn, a quarter of a pixel each.
  Offset get _lineOffset => Offset(_devicePixel / 16, _devicePixel / 16);

  /// Adds a line from [from] at [fromDepth] to [to] at [toDepth] to [path],
  /// as a quad.
  ///
  /// Each end is [lineWidthAt] its depth wide, and extends by half that
  /// width, so that lines meeting at a corner close it. The line is clipped
  /// closer than [near], and moved by [_lineOffset].
  void _addLine(
    Path path,
    Offset from,
    double fromDepth,
    Offset to,
    double toDepth,
  ) {
    var (a, aDepth, b, bDepth) = (from, fromDepth, to, toDepth);
    final aDistance = distanceOf(aDepth);
    final bDistance = distanceOf(bDepth);
    if (aDistance < near && bDistance < near) {
      return;
    }
    if (aDistance < near) {
      final t = (near - aDistance) / (bDistance - aDistance);
      a = Offset.lerp(a, b, t)!;
      aDepth += (bDepth - aDepth) * t;
    } else if (bDistance < near) {
      final t = (near - bDistance) / (aDistance - bDistance);
      b = Offset.lerp(b, a, t)!;
      bDepth += (aDepth - bDepth) * t;
    }
    _addQuad(
      path,
      project(a, aDepth) + _lineOffset,
      lineWidthAt(aDepth),
      project(b, bDepth) + _lineOffset,
      lineWidthAt(bDepth),
    );
  }

  /// Adds a filled quad from [a], [aWidth] wide, to [b], [bWidth] wide, to
  /// [path].
  ///
  /// Its contour stays open, as the fill closes it anyway. Each time the game
  /// makes a path again, Flame's `PathComponent` would walk a closed contour
  /// into polygons, which the game doesn't use.
  static void _addQuad(
    Path path,
    Offset a,
    double aWidth,
    Offset b,
    double bWidth,
  ) {
    final length = (b - a).distance;
    if (length == 0) {
      return;
    }
    final along = (b - a) / length;
    final across = Offset(-along.dy, along.dx);
    final start = a - along * (aWidth / 2);
    final end = b + along * (bWidth / 2);
    path.addPolygon([
      start + across * (aWidth / 2),
      end + across * (bWidth / 2),
      end - across * (bWidth / 2),
      start - across * (aWidth / 2),
    ], false);
  }
}
