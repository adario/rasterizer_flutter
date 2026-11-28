import 'dart:math' as math;
import 'dart:ui';

/// A tube, in tube units.
///
/// The outline's [points] lie round the tube's axis, at most 1 from it
/// horizontally and vertically, and run from left to right along the bottom.
/// Each point starts a lane, and all the lanes have the same width. A closed
/// tube's last lane goes back to its first point. An open tube's last point
/// only ends its last lane, and the ship stops there.
///
/// Every tube is [depth] deep, from its rim at depth 0 to its far end. The eye
/// is on the axis, [eye] in front of the rim, so the far end looks
/// (eye + depth) / eye = 3.8 times smaller than the rim.
///
/// Turning a shape by a lane's angle lays its x axis along the lane and points
/// its y axis toward the inside of the tube, which is deeper.
class Tube(
  final String name,
  final List<Offset> points, {
  final bool isOpen = false,
}) {
  /// Creates a closed regular polygon of [sides] sides, with [lanes] lanes a
  /// side and its first corner at angle [first].
  factory Tube.polygon(String name, int sides, int lanes, double first) {
    final turn = 2 * math.pi / sides;
    return Tube(
      name,
      _closed([
        for (var k = 0; k < sides; k++) Offset.fromDirection(first - k * turn),
      ], lanes),
    );
  }

  /// Creates a closed star with [tips] tips and [lanes] lanes an edge.
  ///
  /// Its inner corners are [ratio] times as far from the axis as its tips,
  /// and the first inner corner is at angle [first].
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

  /// Creates a closed gear with [teeth] teeth, with one lane on each tooth's
  /// top, on each of its flanks and in each gap's root.
  ///
  /// The flanks slant by [slant] away from the direction to the axis, so that
  /// each tooth narrows outward and no lane points at the axis. The first
  /// tooth's top is centred at angle [first].
  factory Tube.gear(String name, int teeth, double slant, double first) {
    final turn = 2 * math.pi / teeth;
    // A lane's width is a flank's length, from the rim to the root's radius.
    double widthAt(double root) =>
        math.sqrt(1 + root * root - 2 * root * math.cos(slant));
    // The root's radius is where a tooth's top, its two flanks and a gap's
    // root, all of the same width, together span a tooth's share of the turn.
    final root = _solve(
      (radius) {
        final width = widthAt(radius);
        return 2 * math.asin(width / 2) +
            2 * math.asin(width / (2 * radius)) +
            2 * slant -
            turn;
      },
      0.5,
      1,
    );
    final width = widthAt(root);
    final top = 2 * math.asin(width / 2);
    final gap = 2 * math.asin(width / (2 * root));
    return Tube(
      name,
      _closed([
        for (var k = 0; k < teeth; k++) ...[
          Offset.fromDirection(first - k * turn + top / 2),
          Offset.fromDirection(first - k * turn - top / 2),
          Offset.fromDirection(first - k * turn - top / 2 - slant, root),
          Offset.fromDirection(first - k * turn - top / 2 - slant - gap, root),
        ],
      ], 1),
    );
  }

  /// Creates a closed clover shaped like the outline of the example's
  /// `clover.svg`.
  ///
  /// It has 4 round lobes of [lanes] lanes each, with a one-lane side between
  /// each two lobes. The first side is at the bottom.
  ///
  /// The lobes are the SVG's circles. The sides are a little closer to the
  /// axis than the SVG's, so that they're as long as a lane round a lobe.
  factory Tube.clover(String name, int lanes) {
    // In the SVG's units, from its middle: how far across and down the lobes'
    // middles are, and the lobes' radius.
    const middle = 161.562;
    const radius = 132.188;
    // For sides `distance` from the axis, returns how far along a side its
    // ends are from the lobes' middles. It also returns, seen from a lobe's
    // middle, the angle where the lobe's outer arc starts and the angle that
    // the arc sweeps.
    ({double along, double start, double sweep}) lobe(double distance) {
      final along = math.sqrt(
        radius * radius - (distance - middle) * (distance - middle),
      );
      final start = math.atan2(distance - middle, -along);
      return (
        along: along,
        start: start,
        sweep: start - math.atan2(-along, distance - middle),
      );
    }

    final side = _solve(
      (distance) {
        final (:along, start: _, :sweep) = lobe(distance);
        return 2 * radius * math.sin(sweep / (2 * lanes)) -
            2 * (middle - along);
      },
      middle,
      middle + radius,
    );
    final (:along, :start, :sweep) = lobe(side);
    final quarter = [
      Offset(along - middle, side),
      for (var i = 0; i < lanes; i++)
        const Offset(middle, middle) +
            Offset.fromDirection(start - sweep * i / lanes, radius),
    ];
    return Tube(
      name,
      _closed([
        for (var k = 0; k < 4; k++)
          for (final point in quarter) rotate(point, -k * math.pi / 2),
      ], 1),
    );
  }

  /// Creates an open arc of [lanes] lanes, 1 from the axis, from angle [start]
  /// through [sweep].
  factory Tube.arc(String name, double start, double sweep, int lanes) =>
      Tube(name, [
        for (var i = 0; i <= lanes; i++)
          Offset.fromDirection(start - sweep * i / lanes),
      ], isOpen: true);

  /// Creates an open outline through [corners], with [lanes] lanes between each
  /// two.
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

  /// Each lane's angle, unwound: the first lane's angle, then each next lane's
  /// angle, reached the short way round from the one before. So the change
  /// from one lane to another is how far the outline turns between them.
  late final List<double> headings = () {
    final headings = [angles.first];
    for (var i = 1; i < laneCount; i++) {
      headings.add(headings.last + _shortTurn(angles[i] - angles[i - 1]));
    }
    return headings;
  }();

  /// Returns the angle of a shape at [along] in [lane], unwound as in
  /// [headings].
  ///
  /// [along] runs from 0 at the lane's first point to 1 at its second. Within
  /// a quarter of a lane from a corner, the angle blends between the angles of
  /// the two lanes there, and it's halfway between them at the corner.
  double headingAt(int lane, double along) {
    final own = headings[lane];
    final before = neighbour(lane, -1);
    final after = neighbour(lane, 1);
    if (along < 0.25 && before != null) {
      return own -
          _shortTurn(angles[lane] - angles[before]) * (0.5 - 2 * along);
    }
    if (along > 0.75 && after != null) {
      return own + _shortTurn(angles[after] - angles[lane]) * (2 * along - 1.5);
    }
    return own;
  }

  /// A lane's width, at the rim.
  late final double laneWidth = (points[1] - points[0]).distance;

  /// The lane closest to straight below the axis, where the ship starts.
  ///
  /// If several lanes are equally close, it's the first of them.
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

  /// Returns the point that ends [lane].
  int pointAfter(int lane) => isOpen ? lane + 1 : (lane + 1) % laneCount;

  /// Returns the lane on [side], 1 or -1, of [lane], or null past an open
  /// tube's end.
  int? neighbour(int lane, int side) => _within(lane + side, laneCount);

  /// Returns the point on [side], 1 or -1, of [point], or null past an open
  /// tube's end.
  int? pointBeside(int point, int side) => _within(point + side, points.length);

  /// Returns the point that lane [from] and its neighbour [to] share.
  int cornerOf(int from, int to) => to == pointAfter(from) ? to : from;

  /// Returns the angle by which a shape in lane [from] turns about the corner
  /// it shares with lane [to], to flip onto [to] through the inside of the
  /// tube.
  ///
  /// The angle is half a turn between two lanes on the same side, less round a
  /// convex corner, and more round a concave one. The shape lands half a turn
  /// off [to]'s angle.
  double flipAngle(int from, int to) {
    final corner = points[cornerOf(from, to)];
    final start = middles[from] - corner;
    final end = middles[to] - corner;
    final angle = (end.direction - start.direction) % (2 * math.pi);
    // Turning clockwise about the corner, the lane's middle starts moving a
    // quarter turn clockwise from its direction from the corner. If that
    // isn't toward the inside of the lane (its y axis), the flip turns the
    // other way.
    final inside = rotate(const Offset(0, 1), angles[from]);
    final first = rotate(start, math.pi / 2);
    return first.dx * inside.dx + first.dy * inside.dy > 0
        ? angle
        : angle - 2 * math.pi;
  }

  /// Returns [index] wrapped round a closed tube's [count], or null outside an
  /// open tube's.
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

  /// Returns [angle] within half a turn of 0, the short way round.
  static double _shortTurn(double angle) =>
      angle - 2 * math.pi * (angle / (2 * math.pi)).roundToDouble();

  /// Returns [offset] turned by [angle], clockwise on screen.
  static Offset rotate(Offset offset, double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(
      offset.dx * cos - offset.dy * sin,
      offset.dx * sin + offset.dy * cos,
    );
  }

  /// Returns [from] and the points after it that split the line to [to] into
  /// [lanes] lanes.
  static List<Offset> _split(Offset from, Offset to, int lanes) => [
    for (var i = 0; i < lanes; i++) Offset.lerp(from, to, i / lanes)!,
  ];

  /// Returns where [f] crosses 0 between [low] and [high], where [f] must have
  /// opposite signs.
  static double _solve(double Function(double) f, double low, double high) {
    final rising = f(low) < 0;
    var below = low;
    var above = high;
    for (var i = 0; i < 64; i++) {
      final middle = (below + above) / 2;
      if ((f(middle) < 0) == rising) {
        below = middle;
      } else {
        above = middle;
      }
    }
    return (below + above) / 2;
  }

  /// Returns the points of a closed outline through [corners], with [lanes]
  /// lanes an edge, scaled so that it reaches at most 1 from the axis
  /// horizontally and vertically.
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
  static final gear = Tube.gear('Gear', 6, 8 * math.pi / 180, math.pi / 2);
  static final clover = Tube.clover('Clover', 5);
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
    gear,
    ridge,
    clover,
  ];

  /// The widest lane of any tube, and the most lanes any tube has.
  static final widestLane = all.map((tube) => tube.laneWidth).reduce(math.max);
  static final mostLanes = all.map((tube) => tube.laneCount).reduce(math.max);
}

/// How the game projects its [tube] into the world.
///
/// During play, the rim is [rimScale] times its size in tube units, with
/// lines [rimPixels] device pixels wide. Lines get thinner with depth, but
/// never thinner than a device pixel. During the zoom and the drop,
/// [eyeShift] moves the eye along the axis.
///
/// Each change bumps [version], so that the game rebuilds the view's paths.
class TubeView() {
  /// The width of the tube's lines and of the shapes' strokes at the rim in
  /// play, in device pixels.
  static const rimPixels = 4.0;

  /// The closest to the eye that the view draws lines, in tube units; it clips
  /// anything closer.
  static const near = 0.2 * Tube.eye;

  /// The tube it projects.
  Tube get tube => _tube;
  Tube _tube = Tubes.octagon;

  /// The world units that a tube unit at the rim spans during play.
  double get rimScale => _rimScale;
  double _rimScale = 1;

  /// The world units in a device pixel.
  double get devicePixel => _devicePixel;
  double _devicePixel = 1;

  /// How far the eye has moved into the tube from where it is during play,
  /// in tube units; negative while it zooms in.
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

  /// How many times as wide as [rimPixels] the tube's lines and the shapes'
  /// strokes are.
  ///
  /// It's 1, or more for the app icons, which show the game small. The stars
  /// keep their widths.
  double get lineWidths => _lineWidths;
  double _lineWidths = 1;

  set lineWidths(double value) {
    if (value != _lineWidths) {
      _lineWidths = value;
      _version++;
    }
  }

  /// Bumps [version] for a change outside the view, so that the game rebuilds
  /// the view's paths.
  void invalidate() => _version++;

  /// Returns how far from the eye [depth] is, in tube units.
  double distanceOf(double depth) => Tube.eye + depth - _eyeShift;

  /// Returns the world units that a tube unit at [depth] spans.
  double scaleAt(double depth) => scaleOf(distanceOf(depth));

  /// Returns the world units that a tube unit [distance] from the eye spans.
  double scaleOf(double distance) => _rimScale * Tube.eye / distance;

  /// Returns where an outline [point] at [depth] lands in the world.
  Offset project(Offset point, double depth) => point * scaleAt(depth);

  /// Returns the width of the tube's line at [depth]: [tubeLineWidthOf] its
  /// distance from the eye.
  double lineWidthAt(double depth) => tubeLineWidthOf(distanceOf(depth));

  /// Returns the width of a line [distance] from the eye: [rimPixels] device
  /// pixels at the rim during play, and never thinner than one device pixel.
  double lineWidthOf(double distance) =>
      math.max(_devicePixel, rimPixels * _devicePixel * Tube.eye / distance);

  /// Returns the width of the tube's line [distance] from the eye: the
  /// [lineWidthOf] that distance, times [lineWidths].
  double tubeLineWidthOf(double distance) =>
      _lineWidths * lineWidthOf(distance);

  /// The width of the shapes' strokes, in lane units: [rimPixels] device
  /// pixels at the rim during play, times [lineWidths]. A shape's scale
  /// is its lane's width, so its strokes get thinner with depth, as the
  /// tube's lines do.
  double get shapeStroke =>
      _lineWidths * rimPixels * _devicePixel / (tube.laneWidth * _rimScale);

  /// Returns the tube's lines, as filled quads: its spokes, its rim and its far
  /// end.
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

  /// Returns the 4 lines round [lane], as quads like [tubePath]'s.
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

  /// Returns the spikes of [lengths], each reaching from the far end toward the
  /// rim, as lines like [tubePath]'s.
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

  /// Returns the [bolts] along the middles of their lanes, each from its
  /// depth to the rim, as lines like [tubePath]'s.
  ///
  /// Each bolt zigzags, with a segment every [boltStep] at most, and corners
  /// at random places across the middle third of its lane.
  Path boltsPath(
    Iterable<({int lane, double depth})> bolts,
    math.Random random,
  ) {
    final path = Path();
    for (final (:lane, :depth) in bolts) {
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

  /// How far [_addLine] moves the lines right and down: a sixteenth of a
  /// device pixel.
  ///
  /// With 4x MSAA, an edge's coverage changes a quarter of a pixel at a time,
  /// as it crosses rows of samples a quarter of a pixel apart. A tapering line
  /// whose axis lies on a pixel's edge or middle would have both edges cross a
  /// row at once, so its width would jump by half a pixel. Moved by a
  /// sixteenth, its edges cross the rows in turn, so its width changes a
  /// quarter of a pixel at a time.
  Offset get _lineOffset => Offset(_devicePixel / 16, _devicePixel / 16);

  /// Adds a line from [from] at [fromDepth] to [to] at [toDepth] to [path],
  /// as a quad.
  ///
  /// Each end is [lineWidthAt] its depth wide and extends by half that width,
  /// so that lines meeting at a corner close it. It clips the part of the
  /// line closer than [near], and moves the line by [_lineOffset].
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
  /// Its contour stays open, because the fill closes it anyway. For a closed
  /// contour, Flame's `PathComponent` would compute polygons each time the
  /// game rebuilds a path, and the game doesn't use them.
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
