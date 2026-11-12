import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/rendering.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// The demo's content as plain data, so that the game and the check's
/// reference, which composes the same frame without Flame, draw the same
/// thing.
///
/// `count` vector items come in [groups], with a separator drawn after each
/// group but the last. An optional group of `clipped` items and the optional
/// painted items follow. The groups draw in order, so each is one run: a
/// batch of SVGs that flame_rasterizer draws together. The painted items
/// make runs of their own: see [paintedRuns].
///
/// The items draw `svgCount` generated SVGs, or the [svgs] given, named
/// [svgName].
class DemoLayout({
  required int count,
  required int separators,
  int clipped = 0,
  bool painted = false,
  List<String>? svgs,
  final String svgName = 'generated',
  int svgCount = 50,
  int seed = 1,
}) {
  this {
    final r = math.Random(seed);
    this.svgs = svgs ?? [for (var i = 0; i < svgCount; i++) demoSvg(r, i)];
    final n = this.svgs.length;
    final groups = separators + 1;
    items = [
      for (var i = 0; i < count; i++)
        VectorItem(
          svg: r.nextInt(n),
          group: i * groups ~/ count,
          x: (r.nextDouble() - 0.5) * worldWidth,
          y: (r.nextDouble() - 0.5) * worldHeight,
          size: 40 + r.nextDouble() * 80,
          angle: r.nextDouble() * 2 * math.pi,
          spin: (r.nextDouble() - 0.5) * 2,
          phase: r.nextDouble() * 2 * math.pi,
        ),
    ];
    this.separators = [
      for (var g = 0; g < separators; g++)
        SeparatorItem(
          group: g,
          x: (r.nextDouble() - 0.5) * worldWidth * 0.6,
          y: (r.nextDouble() - 0.5) * worldHeight * 0.6,
          width: 150 + r.nextDouble() * 250,
          height: 40 + r.nextDouble() * 60,
          angle: (r.nextDouble() - 0.5) * 1.2,
          color: Color(0xC0000000 | r.nextInt(0xFFFFFF) | 0x404040),
        ),
    ];
    clippedItems = [
      for (var i = 0; i < clipped; i++)
        VectorItem(
          svg: r.nextInt(n),
          group: groups,
          x: r.nextDouble() * clipRect.width,
          y: r.nextDouble() * clipRect.height,
          size: 60 + r.nextDouble() * 80,
          angle: r.nextDouble() * 2 * math.pi,
          spin: (r.nextDouble() - 0.5) * 2,
          phase: r.nextDouble() * 2 * math.pi,
        ),
    ];
    paintedItems = [
      if (painted)
        for (final kind in paintedKinds)
          (
            VectorItem(
              svg: r.nextInt(n),
              group: groups + 1,
              x: (r.nextDouble() - 0.5) * worldWidth * 0.6,
              y: (r.nextDouble() - 0.5) * worldHeight * 0.6,
              size: 120 + r.nextDouble() * 80,
              angle: r.nextDouble() * 2 * math.pi,
              spin: (r.nextDouble() - 0.5) * 2,
              phase: r.nextDouble() * 2 * math.pi,
            ),
            kind,
          ),
    ];
  }

  /// The painted items' kinds of paint, in paint order. They make
  /// [paintedRuns] runs.
  static const paintedKinds = [
    PaintKind.faded,
    PaintKind.tinted,
    PaintKind.hued,
    PaintKind.blurred,
    PaintKind.shared,
    PaintKind.shared,
    PaintKind.shared,
  ];

  /// How many runs the painted items make: 3, or 0 without them.
  ///
  /// The faded, tinted and hued items share one run, as their paints fold
  /// into their entries. The blurred item has a run of its own. The 3 items
  /// that share a paint share the last run. flame_rasterizer can't fold that
  /// paint's tint, as it recognises only the filters it made itself.
  int get paintedRuns => paintedItems.isEmpty ? 0 : 3;

  /// Whether the paint of a [kind] of painted item folds into its entry.
  ///
  /// Opacities fold, and so do the tints and hues that
  /// `RasterizerSvgComponent` makes with [RasterizerColorTransform].
  static bool folds(PaintKind kind) =>
      kind == PaintKind.faded ||
      kind == PaintKind.tinted ||
      kind == PaintKind.hued;

  /// The color transform that a [kind] of painted item's entry takes, if any,
  /// as `RasterizerSvgComponent`'s `tint` and `hue` make it.
  static RasterizerColorTransform? transformOf(PaintKind kind) =>
      switch (kind) {
        PaintKind.tinted => RasterizerColorTransform.mode(
          tintColor,
          BlendMode.srcATop,
        ),
        PaintKind.hued => RasterizerColorTransform.matrix(
          hueRotationMatrix(hue),
        ),
        _ => null,
      };

  /// The faded item's opacity.
  static const fadedOpacity = 0.45;

  /// The hued item's hue rotation, in radians.
  static const hue = 2.0;

  /// The blurred item's blur sigma.
  static const blurSigma = 3.0;

  /// The tinted item's tint.
  static const tintColor = Color(0xC0FF4081);

  /// The shared paint's color, whose alpha fades its items.
  static const sharedColor = Color(0xB3FFFFFF);

  /// The shared paint's tint.
  static const sharedTint = Color(0xFF40C4FF);

  /// The paint that a [kind] of painted item draws with, for the check's
  /// reference.
  ///
  /// The game sets its components' paints with `HasPaint`'s API instead,
  /// except for the shared paint, which it uses as it is.
  static Paint paintOf(PaintKind kind) => switch (kind) {
    PaintKind.faded =>
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: fadedOpacity),
    PaintKind.tinted =>
      Paint()
        ..colorFilter = const ColorFilter.mode(tintColor, BlendMode.srcATop),
    PaintKind.hued =>
      Paint()..colorFilter = ColorFilter.matrix(hueRotationMatrix(hue)),
    PaintKind.blurred =>
      Paint()
        ..imageFilter = ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    PaintKind.shared =>
      Paint()
        ..color = sharedColor
        ..colorFilter = const ColorFilter.mode(sharedTint, BlendMode.srcATop),
  };

  /// The width of the area items start in, centred on the world's origin.
  static const worldWidth = 1000.0;

  /// The height of the area items start in.
  static const worldHeight = 700.0;

  /// The clipped group's clip rectangle, in world coordinates. Its items'
  /// positions are relative to the rectangle's top left corner.
  static const clipRect = Rect.fromLTWH(-150, -100, 300, 200);

  /// The SVGs' sources, which the items pick by index.
  late final List<String> svgs;

  /// The items of all the groups, group by group.
  late final List<VectorItem> items;

  /// The clipped group's items.
  late final List<VectorItem> clippedItems;

  /// The painted items, each with its kind of paint.
  late final List<(VectorItem, PaintKind)> paintedItems;

  /// The separators, one after each group but the last.
  late final List<SeparatorItem> separators;

  /// How many groups the items come in.
  int get groups => separators.length + 1;

  /// The camera at time [t], for a viewport [width] by [height]: the world
  /// position at the viewport's centre, and the zoom.
  ///
  /// The camera drifts, and zooms between 0.5 and 1.7 times the zoom that
  /// fits the area the items start in.
  static (double, double, double) camera(
    double t,
    double width,
    double height,
  ) {
    final fit = math.min(width / worldWidth, height / worldHeight);
    return (
      120 * math.cos(t * 0.21),
      80 * math.sin(t * 0.17),
      fit * (1.1 + 0.6 * math.sin(t * 0.3)),
    );
  }
}

/// How a painted item draws: faded, tinted, with its hue shifted, blurred, or
/// with a faded and tinted paint that it shares with its neighbours.
enum PaintKind() {
  faded,
  tinted,
  hued,
  blurred,
  shared,
}

/// An item that draws one of the layout's SVGs, moving and spinning.
///
/// [svg] is an index into [DemoLayout.svgs], and [size] the item's width and
/// height in world units. [spin] is in radians a second, and [phase] offsets
/// its drift.
class VectorItem({
  required final int svg,
  required final int group,
  required final double x,
  required final double y,
  required final double size,
  required final double angle,
  required final double spin,
  required final double phase,
}) {
  /// Its position and angle at time [t].
  (double, double, double) at(double t) => (
    x + 60 * math.sin(t * 0.7 + phase),
    y + 40 * math.cos(t * 0.9 + phase),
    angle + spin * t,
  );
}

/// A separator between two groups, drawn after [group]'s items.
///
/// The game draws it as a rectangle, a sprite or a text, as its
/// `Separators` say, centred on [x] and [y] and turned by [angle].
class SeparatorItem({
  /// The group that it's drawn after.
  required final int group,
  required final double x,
  required final double y,
  required final double width,
  required final double height,
  required final double angle,
  required final Color color,
});

/// Creates a random SVG, from [r], of 1 to 10 paths in a 100 x 100 viewBox,
/// as rasterizer_gpu's example does in `generatedSvgs`.
///
/// Every fifth one, from [index] 0, fills its first path with a gradient.
String demoSvg(math.Random r, int index) {
  String color() =>
      '#${(r.nextInt(0xFFFFFF) | 0x202020).toRadixString(16).padLeft(6, '0')}';
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">',
  );
  final gradient = index % 5 == 0;
  if (gradient) {
    out.write(
      '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${color()}"/><stop offset="1" stop-color="${color()}"/></linearGradient></defs>',
    );
  }
  final paths = 1 + r.nextInt(10);
  for (var p = 0; p < paths; p++) {
    final fill = gradient && p == 0 ? 'url(#g)' : color();
    final stroke = r.nextInt(3) == 0
        ? ' stroke="${color()}" stroke-width="${1 + r.nextInt(6)}"'
        : '';
    final opacity = r.nextInt(4) == 0 ? ' fill-opacity="0.6"' : '';
    final cx = 20 + r.nextDouble() * 60;
    final cy = 20 + r.nextDouble() * 60;
    final s = 8 + r.nextDouble() * 30;
    switch (r.nextInt(4)) {
      case 0:
        out.write(
          '<circle cx="$cx" cy="$cy" r="$s" fill="$fill"$stroke$opacity/>',
        );
      case 1:
        String point(int k) {
          final x = cx + (k.isEven ? s : s / 2.5) * math.cos(k * math.pi / 5);
          final y = cy + (k.isEven ? s : s / 2.5) * math.sin(k * math.pi / 5);
          return '$x,$y';
        }

        final points = [for (var k = 0; k < 10; k++) point(k)];
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
