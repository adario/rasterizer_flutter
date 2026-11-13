import 'dart:math' as math;
import 'dart:ui';

import 'affine.dart';

/// Returns a scale by [s] about the point [f], with y pointing down.
Affine about(Offset f, double s) =>
    Affine(s, 0, 0, s, f.dx * (1 - s), f.dy * (1 - s));

/// The number of frames in the sweep, a camera move over the tiger SVG.
///
/// The sweep zooms into the tiger's left eye up to 20x, zooms out to 0.05x,
/// then pans off the page's bottom left, 60 frames each.
const sweepFrames = 180;

/// The sweep's frames that the goldens check.
const sweepCheckpoints = [30, 59, 90, 119, 150, 179];

/// Returns the sweep's view at frame [i], for a page of [size]. It applies
/// after the transform that fits the scene to the page.
Affine sweepView(int i, Size size) {
  final center = size.center(Offset.zero);
  if (i < 60) {
    return about(
      Offset(0.475 * size.width, 0.656 * size.height),
      math.pow(20, i / 59).toDouble(),
    );
  }
  if (i < 120) {
    return about(center, 20 * math.pow(0.05 / 20, (i - 60) / 59).toDouble());
  }
  final t = (i - 120) / 59;
  return about(
    center,
    1.5,
  ).concat(Affine.translation(-0.8 * size.width * t, -0.3 * size.height * t));
}

/// Returns the transforms that draw a scene of [bounds] [grid] x [grid]
/// times.
///
/// It offsets the copies by whole multiples of the scene's size, rounded up.
/// It fits the whole grid to a page of [size] points, then applies [view],
/// then scales by [ratio] device pixels a point.
List<Affine> gridTransforms(
  Rect bounds,
  int grid,
  Size size,
  Affine view,
  double ratio,
) {
  final cw = bounds.width.ceilToDouble(), ch = bounds.height.ceilToDouble();
  final all = Rect.fromLTRB(
    bounds.left,
    bounds.top,
    bounds.left + cw * (grid - 1) + bounds.width,
    bounds.top + ch * (grid - 1) + bounds.height,
  );
  final ctm = Affine.fit(
    Offset.zero & size,
    all,
  ).concat(view).concat(Affine.scale(ratio));
  return [
    for (var row = 0; row < grid; row++)
      for (var col = 0; col < grid; col++)
        Affine.translation(col * cw, row * ch).concat(ctm),
  ];
}

/// An SVG of gradients, 1024 x 768 like the golden viewport, in a 4 x 3
/// grid.
///
/// Most are bounding box gradients, whose coordinates are fractions of their
/// shapes' bounds, written as numbers or percentages. Some have gradient
/// transforms, some are on shapes in transformed groups, and one paints a
/// stroke. There's also a user space gradient, radial gradients on shapes
/// that aren't square, which turn them into ellipses, and translucent ones,
/// with fill, stroke and stop opacities.
///
/// vector_graphics_compiler draws them all as SVG says, as Chrome does. The
/// strokes' gradients are diagonal: the iOS Simulator's Impeller draws only
/// the inner half of a stroked rectangle whose horizontal or vertical linear
/// gradient ends on its bounds, while macOS's draws the whole stroke from the
/// same canvas calls.
const gradientsSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="768" viewBox="0 0 1024 768">
<defs>
<linearGradient id="h" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#d02020"/><stop offset="1" stop-color="#2040e0"/></linearGradient>
<linearGradient id="v" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#20a040"/><stop offset="1" stop-color="#f0d020"/></linearGradient>
<linearGradient id="p" x1="10%" y1="0%" x2="90%" y2="0%"><stop offset="0" stop-color="#202020"/><stop offset="0.5" stop-color="#f0f0f0"/><stop offset="1" stop-color="#e02080"/></linearGradient>
<linearGradient id="d" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f08020"/><stop offset="1" stop-color="#4020c0"/></linearGradient>
<linearGradient id="t" x1="0" y1="0" x2="1" y2="0" gradientTransform="rotate(45 0.5 0.5)"><stop offset="0" stop-color="#d02020"/><stop offset="1" stop-color="#20c0c0"/></linearGradient>
<linearGradient id="u" gradientUnits="userSpaceOnUse" x1="800" y1="0" x2="960" y2="0"><stop offset="0" stop-color="#2040e0"/><stop offset="1" stop-color="#f0d020"/></linearGradient>
<linearGradient id="b" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#4020c0"/><stop offset="0.3" stop-color="#f0f0f0"/><stop offset="1" stop-color="#20a040"/></linearGradient>
<radialGradient id="r" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#f0f0f0"/><stop offset="1" stop-color="#d02020"/></radialGradient>
<radialGradient id="q" cx="30%" cy="40%" r="60%"><stop offset="0" stop-color="#f0d020"/><stop offset="1" stop-color="#2040e0"/></radialGradient>
<linearGradient id="o"><stop offset="0" stop-color="#202020" stop-opacity="0.2"/><stop offset="1" stop-color="#202020"/></linearGradient>
</defs>
<rect x="28" y="78" width="200" height="100" fill="url(#h)"/>
<rect x="334" y="28" width="100" height="200" fill="url(#v)"/>
<rect x="540" y="68" width="200" height="120" fill="url(#p)"/>
<rect x="806" y="38" width="180" height="180" fill="url(#d)"/>
<rect x="18" y="329" width="220" height="110" fill="url(#r)"/>
<circle cx="384" cy="384" r="100" fill="url(#q)"/>
<rect x="550" y="294" width="180" height="180" fill="url(#t)"/>
<rect x="790" y="314" width="180" height="140" fill="url(#u)"/>
<g transform="rotate(30 128 640)"><rect x="48" y="560" width="160" height="160" fill="url(#h)"/></g>
<g transform="translate(384 640) scale(1.4 0.7)"><rect x="-80" y="-120" width="160" height="240" fill="url(#r)"/></g>
<rect x="556" y="556" width="168" height="168" fill="none" stroke="url(#d)" stroke-width="24"/>
<circle cx="896" cy="640" r="96" fill="url(#b)"/>
<rect x="150" y="150" width="150" height="60" fill="url(#v)" fill-opacity="0.5"/>
<rect x="300" y="440" width="170" height="40" fill="url(#o)" stroke="url(#d)" stroke-width="6" stroke-opacity="0.5"/>
</svg>''';

/// An SVG of gradients that vector_graphics_compiler doesn't draw as SVG
/// says, while Chrome and the core do.
///
/// It has diagonal bounding box gradients on shapes that aren't square, and
/// on a stretched square, whose colour bands follow the bounds' proportions.
/// It also has rotated gradients on shapes that aren't square, and a line
/// with no height, which a bounding box gradient doesn't paint. Last comes a
/// skewed radial gradient, as vector_graphics_compiler reads skew angles as
/// radians rather than degrees.
const gradientsSkewedSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="768" viewBox="0 0 1024 768">
<defs>
<linearGradient id="d" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f08020"/><stop offset="0.5" stop-color="#f0f0f0"/><stop offset="1" stop-color="#4020c0"/></linearGradient>
<linearGradient id="t" x1="0" y1="0" x2="1" y2="0" gradientTransform="rotate(30 0.5 0.5)"><stop offset="0" stop-color="#d02020"/><stop offset="1" stop-color="#20c0c0"/></linearGradient>
<radialGradient id="s" cx="0.5" cy="0.5" r="0.4" gradientTransform="skewX(20)"><stop offset="0" stop-color="#20c0c0"/><stop offset="1" stop-color="#202020"/></radialGradient>
</defs>
<rect x="40" y="80" width="440" height="160" fill="url(#d)"/>
<rect x="560" y="40" width="120" height="320" fill="url(#d)"/>
<g transform="translate(820 200) scale(1.5 0.6)"><rect x="-80" y="-160" width="160" height="320" fill="url(#d)"/></g>
<rect x="40" y="400" width="480" height="200" fill="url(#t)"/>
<path d="M600 700 H980" stroke="url(#d)" stroke-width="20"/>
<rect x="600" y="440" width="380" height="180" fill="url(#t)" stroke="#202020" stroke-width="2"/>
<rect x="40" y="640" width="400" height="100" fill="url(#s)"/>
</svg>''';

/// An SVG of strokes, 1024 x 768 like the golden viewport, for the triangle
/// strips that the mesh renderer builds strokes from.
///
/// It has miter, bevel and round joins, sharp turns past the miter limit
/// and within a larger one, butt, square and round caps, and thin lines.
/// Then come translucent strokes that overlap themselves, whose overlaps
/// must blend once, as SVG says: a curl, a star, a turn back, and a circle
/// thicker than its radius. Last come a translucent fill under a translucent
/// stroke, which blend twice, a dashed curve, a gradient stroke, and a
/// stroke in a rotated, stretched group.
///
/// The GPU renderer blends those overlaps twice, and draws some joins
/// differently, so it has no golden of this SVG.
const strokesSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="768" viewBox="0 0 1024 768">
<defs>
<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d02020"/><stop offset="1" stop-color="#2040e0"/></linearGradient>
</defs>
<g fill="none" stroke-width="24">
<polyline points="30,190 90,50 150,190 210,50" stroke="#d02020" stroke-linejoin="miter"/>
<polyline points="286,190 346,50 406,190 466,50" stroke="#20a040" stroke-linejoin="bevel"/>
<polyline points="542,190 602,50 662,190 722,50" stroke="#2040e0" stroke-linejoin="round"/>
</g>
<g fill="none" stroke="#202020" stroke-width="20">
<polyline points="790,200 815,90 840,200" stroke-miterlimit="4"/>
<polyline points="900,200 925,90 950,200" stroke-miterlimit="10"/>
</g>
<g fill="none" stroke="#e08020" stroke-width="30">
<path d="M40,300 H200" stroke-linecap="butt"/>
<path d="M296,300 H456" stroke-linecap="square"/>
<path d="M552,300 H712" stroke-linecap="round"/>
</g>
<g fill="none" stroke="#202020">
<path d="M40,450 L200,370" stroke-width="0.5"/>
<path d="M260,450 L420,370" stroke-width="1"/>
<path d="M480,450 L640,370" stroke-width="2"/>
<path d="M700,450 L860,370" stroke-width="4"/>
<path d="M880,410.5 H1000" stroke-width="1"/>
</g>
<g fill="none" stroke-opacity="0.5">
<path d="M40,620 C220,440 220,700 40,540" stroke="#2040e0" stroke-width="24"/>
<polygon points="380,490 424.1,625.7 308.7,541.8 451.3,541.8 335.9,625.7" stroke="#d02020" stroke-width="14"/>
<path d="M520,520 H700 H560" stroke="#20a040" stroke-width="20"/>
<circle cx="780" cy="560" r="12" stroke="#2040e0" stroke-width="40"/>
</g>
<rect x="860" y="500" width="120" height="110" fill="#20a040" fill-opacity="0.5" stroke="#202020" stroke-width="16" stroke-opacity="0.5" stroke-linejoin="round"/>
<path d="M40,720 C200,640 300,800 460,700" fill="none" stroke="#d02020" stroke-opacity="0.5" stroke-width="16" stroke-dasharray="36 18" stroke-linecap="round"/>
<path d="M520,740 L620,670 L720,740" fill="none" stroke="url(#g)" stroke-width="26" stroke-linejoin="round"/>
<g transform="translate(880 710) rotate(-25) scale(1.6 0.7)"><rect x="-50" y="-30" width="100" height="60" fill="none" stroke="#e08020" stroke-width="10" stroke-linejoin="round"/></g>
</svg>''';

/// An SVG of strokes thin enough that, drawn small, the mesh renderer widens
/// them to its least width, so that 4x MSAA doesn't break them into dots.
///
/// It has a curve, miter, bevel and round joins, a circle, and opaque
/// strokes that cross and turn back on themselves. Those last three lie over
/// a fill, to check their paint order. A gradient stroke, a translucent one
/// and a dashed line come last.
const thinStrokesSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="768" viewBox="0 0 1024 768">
<defs>
<linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#d02020"/><stop offset="1" stop-color="#2040e0"/></linearGradient>
</defs>
<rect x="60" y="240" width="900" height="120" fill="#a0d0a0"/>
<g fill="none" stroke="#202020" stroke-width="1.2">
<path d="M40,60 C300,-40 400,300 980,40"/>
<polyline points="40,200 120,90 200,200 280,90 360,200" stroke-linejoin="miter"/>
<polyline points="400,200 480,90 560,200 640,90 720,200" stroke-linejoin="bevel"/>
<polyline points="760,200 800,90 840,200 880,90 960,200" stroke-linejoin="round"/>
<circle cx="200" cy="300" r="50"/>
<path d="M340,250 L620,350 M620,250 L340,350"/>
<path d="M680,300 H940 H720"/>
</g>
<path d="M40,520 C300,380 700,660 980,500" fill="none" stroke="url(#g)" stroke-width="1.2"/>
<path d="M40,620 H980" fill="none" stroke="#d02020" stroke-opacity="0.5" stroke-width="1.2"/>
<path d="M40,740 L300,660 L560,740 L820,660 L980,740" fill="none" stroke="#2040e0" stroke-width="1.2" stroke-linejoin="round" stroke-dasharray="40 20"/>
</svg>''';

/// Returns plain Flutter paths on a 1024 x 768 page, each with its paint.
///
/// There are fills with both fill rules, and holes drawn either way round.
/// An open contour is filled and stroked, and another path has both a fill
/// and a stroke. There's a `Path.combine`, curves, joins and caps, and
/// translucent overlaps. There are no bevel joins, which the GPU renderer
/// draws as miters, nor miters past its fixed limit.
List<(Path, Paint)> goldenPaths() {
  Paint fill(int color) => Paint()..color = Color(color);
  Paint stroke(int color, double width) => Paint()
    ..color = Color(color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  Path star(Offset c, double r) => Path()
    ..addPolygon([
      for (var i = 0; i < 5; i++)
        c + Offset.fromDirection(-math.pi / 2 + i * 4 * math.pi / 5, r),
    ], true);
  final rrect = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(260, 50, 200, 180),
        const Radius.circular(30),
      ),
    );
  // A circle drawn counterclockwise, the other way from addOval.
  Path reversedCircle(Offset c, double r) => Path()
    ..moveTo(c.dx + r, c.dy)
    ..arcToPoint(c - Offset(r, 0), radius: Radius.circular(r), clockwise: false)
    ..arcToPoint(c + Offset(r, 0), radius: Radius.circular(r), clockwise: false)
    ..close();
  final arc = Path()..addArc(const Rect.fromLTWH(260, 280, 200, 200), 0.3, 4.5);
  // Its fill type is set again, as CanvasKit gives a combined path a nonzero
  // one, which fills the hole.
  final cut = Path.combine(
    PathOperation.difference,
    Path()..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(520, 290, 200, 180),
        const Radius.circular(40),
      ),
    ),
    Path()
      ..addOval(Rect.fromCircle(center: const Offset(620, 380), radius: 60)),
  )..fillType = PathFillType.evenOdd;
  final wave = Path()
    ..moveTo(770, 440)
    ..cubicTo(830, 260, 920, 520, 980, 320);
  // Its lower miter stays within the scene's bounds, which the triangle sets.
  // The GPU renderer clips runs to those bounds, which take in half a
  // stroke's width but not its miters.
  final zigzag = Path()
    ..addPolygon(const [
      Offset(40, 700),
      Offset(120, 540),
      Offset(200, 700),
      Offset(280, 540),
    ], false);
  final triangle = Path()
    ..addPolygon(const [
      Offset(340, 720),
      Offset(420, 560),
      Offset(500, 720),
    ], true);
  return [
    (
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(130, 140), radius: 90)),
      fill(0xff3060c0),
    ),
    (rrect, fill(0xfff0c040)),
    (rrect, stroke(0xffa07010, 10)),
    (star(const Offset(600, 145), 95), fill(0xffd02020)),
    (
      star(const Offset(830, 145), 95)..fillType = PathFillType.evenOdd,
      fill(0xff20a040),
    ),
    (
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(130, 380), radius: 90))
        ..addPath(reversedCircle(const Offset(130, 380), 45), Offset.zero),
      fill(0xff2040e0),
    ),
    (arc, fill(0xffe08020)),
    (arc, stroke(0xff202020, 12)..strokeCap = StrokeCap.round),
    (cut, fill(0xff8040c0)),
    (wave, stroke(0xff20a0a0, 16)..strokeCap = StrokeCap.square),
    (zigzag, stroke(0xffd02020, 18)),
    (triangle, stroke(0xff2040e0, 14)..strokeJoin = StrokeJoin.round),
    (
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(600, 640), radius: 70)),
      fill(0x80d02020),
    ),
    (
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(670, 640), radius: 70)),
      fill(0x802040e0),
    ),
  ];
}

/// Returns a shape 3 units wide, the size of a Forge2D body, with a stroke
/// 0.05 units wide: a body and two wheels.
///
/// The paths golden draws it on [goldenPaths]' page at 40 pixels a unit.
List<(Path, Paint)> goldenSmallPaths() {
  final body = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 3, 1.2),
        const Radius.circular(0.3),
      ),
    );
  final wheels = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.7, 1.2), radius: 0.4))
    ..addOval(Rect.fromCircle(center: const Offset(2.3, 1.2), radius: 0.4));
  return [
    (body, Paint()..color = const Color(0xff606060)),
    (
      body,
      Paint()
        ..color = const Color(0xff000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05,
    ),
    (wheels, Paint()..color = const Color(0xff202020)),
  ];
}

/// Returns [count] random SVGs, the same for the same [seed].
///
/// Each has 1 to 10 paths in a 100 x 100 view box: circles, stars, rounded
/// rectangles and curves. They're filled, some stroked, some translucent,
/// and every fifth SVG has a gradient.
List<String> generatedSvgs(int count, {int seed = 1}) {
  final random = math.Random(seed);
  return [for (var i = 0; i < count; i++) _svg(random, i)];
}

/// Returns the [index]th SVG of [generatedSvgs], from [r].
String _svg(math.Random r, int index) {
  String color() =>
      '#${(r.nextInt(0xFFFFFF) | 0x202020).toRadixString(16).padLeft(6, '0')}';
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">',
  );
  final gradient = index % 5 == 0;
  if (gradient) {
    out.write(
      '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${color()}"/>'
      '<stop offset="1" stop-color="${color()}"/></linearGradient></defs>',
    );
  }
  final paths = 1 + r.nextInt(10);
  for (var p = 0; p < paths; p++) {
    final fill = gradient && p == 0 ? 'url(#g)' : color();
    final stroke = r.nextInt(3) == 0
        ? ' stroke="${color()}" stroke-width="${1 + r.nextInt(6)}"'
        : '';
    final opacity = r.nextInt(4) == 0 ? ' fill-opacity="0.6"' : '';
    final cx = 20 + r.nextDouble() * 60,
        cy = 20 + r.nextDouble() * 60,
        s = 8 + r.nextDouble() * 30;
    switch (r.nextInt(4)) {
      case 0:
        out.write(
          '<circle cx="$cx" cy="$cy" r="$s" fill="$fill"$stroke$opacity/>',
        );
      case 1:
        final points = [
          for (var k = 0; k < 10; k++)
            '${cx + (k.isEven ? s : s / 2.5) * math.cos(k * math.pi / 5)},'
                '${cy + (k.isEven ? s : s / 2.5) * math.sin(k * math.pi / 5)}',
        ];
        out.write(
          '<polygon points="${points.join(' ')}" fill="$fill"$stroke$opacity/>',
        );
      case 2:
        out.write(
          '<rect x="${cx - s}" y="${cy - s / 2}" width="${2 * s}" height="$s" rx="${s / 4}" fill="$fill"$stroke$opacity/>',
        );
      default:
        out.write(
          '<path d="M${cx - s},$cy C${cx - s},${cy - s} ${cx + s},${cy - s} '
          '${cx + s},$cy Q$cx,${cy + 2 * s} ${cx - s},$cy Z" '
          'fill="$fill"$stroke$opacity/>',
        );
    }
  }
  out.write('</svg>');
  return out.toString();
}

/// The motion of the atlas frame's entries: [entries] entries of [svgCount]
/// generated SVGs, each moving and spinning across the viewport.
///
/// Their positions wrap around the viewport, so many entries cross its
/// edges.
class AtlasMotion({final int svgCount = 50, required final int entries}) {
  this {
    final random = math.Random(8);
    _motion = [
      for (var i = 0; i < entries; i++)
        (
          random.nextInt(svgCount),
          random.nextDouble(),
          random.nextDouble(),
          0.4 + 1.2 * random.nextDouble(),
          random.nextDouble() * 2 * math.pi,
          random.nextDouble() * 2 - 1,
        ),
    ];
  }

  /// Each entry's SVG index, starting x and y as fractions of the viewport,
  /// scale, starting angle and spin.
  late final List<(int, double, double, double, double, double)> _motion;

  /// Returns the index of entry [i]'s SVG.
  int svg(int i) => _motion[i].$1;

  /// Returns entry [i]'s affine transform at time [t], in device pixels for
  /// a viewport of [px].
  ///
  /// It spins and scales the SVG's 100 x 100 view box about its centre, and
  /// moves it across the viewport.
  (double, double, double, double, double, double) transform(
    int i,
    double t,
    Size px,
  ) {
    final (_, x0, y0, scale, angle, spin) = _motion[i];
    final s = scale * px.shortestSide / 12,
        a = angle + spin * t,
        cs = s / 100 * math.cos(a),
        sn = s / 100 * math.sin(a);
    final x = (x0 + 0.05 * t * spin) % 1.0 * px.width,
        y = (y0 + 0.03 * t) % 1.0 * px.height;
    return (cs, sn, -sn, cs, x - 50 * cs + 50 * sn, y - 50 * sn - 50 * cs);
  }
}
