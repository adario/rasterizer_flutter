import 'dart:math' show max;
import 'dart:ui' as ui;

import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:xml/xml_events.dart';

import '../canvas_paths.dart';
import 'vector_graphics_compiler_extensions.dart';

/// An SVG's paths, parsed in Dart by vector_graphics_compiler, to draw with a
/// [ui.Canvas]: the canvas renderer's scenes.
///
/// Based on SvgPaths, which this package's author wrote for flame_svg and
/// Flame didn't merge. It drops that class's hitboxes, animations and Flame
/// types, and draws as the core's scenes do:
/// - It imports only paths, as the core's NanoSVG does. It removes clip paths
///   before parsing. It skips masks' own shapes, patterns' tiles and the
///   shapes painted with patterns. It doesn't import text or images.
/// - It multiplies opacity into the paints' colors, as the core does, where
///   vector_graphics_compiler draws it as layers.
/// - It doesn't fill paths without an area, such as a line with SVG's default
///   fill. A canvas would paint a hairline, which shows under their strokes
///   once those are translucent.
/// - It draws in the SVG's coordinates. vector_graphics_compiler moves their
///   origin to the viewBox's, so [draw] moves it back.
class SvgPaths(
  String svg, {

  /// Whether to merge consecutive paths with the same paint, which keeps the
  /// SVG's paint order.
  ///
  /// It doesn't merge paths with both a fill and a stroke, with another fill
  /// type, or whose bounds with their strokes overlap those of a path merged
  /// so far.
  final bool merge = true,
}) implements CanvasPaths {
  /// Parses [svg], and with [merge], merges consecutive paths with the same
  /// paint into one.
  ///
  /// Throws if [svg] can't be parsed.
  this {
    _import(svg);
  }

  /// The paths, in paint order. Their 0, 0 is the viewBox's origin, [origin].
  final List<VectorPath> paths = [];

  /// Where the paths' 0, 0 lies in the SVG's coordinates: its viewBox's
  /// origin.
  late final ui.Offset origin;

  /// The SVG's own rectangle in its coordinates: its viewBox, or else from 0, 0
  /// to its width and height.
  @override
  late final ui.Rect viewBox;

  /// The paths' bounds in the SVG's coordinates, with half their strokes'
  /// widths, as the core computes them, or [ui.Rect.zero] if there are none.
  @override
  late final ui.Rect bounds;

  /// What [draw] can paint, in the SVG's coordinates: the paths' bounds with
  /// all of their strokes, joins and caps, or [ui.Rect.zero] if there are
  /// none.
  @override
  late final ui.Rect paintedBounds;

  /// How many draws [draw] makes: one per fill and one per stroke.
  @override
  int get drawCount => paths.fold(
    0,
    (n, p) => n + (p.paint.isFilled ? 1 : 0) + (p.paint.isStroked ? 1 : 0),
  );

  /// Draws the paths into [canvas], in the SVG's coordinates.
  ///
  /// [opacity] scales each path's alpha, so paths that overlap show through
  /// each other, as the core's do. [colorFilter] filters each path's color.
  @override
  void draw(
    ui.Canvas canvas, {
    double opacity = 1,
    ui.ColorFilter? colorFilter,
  }) {
    final o = origin;
    if (o != ui.Offset.zero) {
      canvas.save();
      canvas.translate(o.dx, o.dy);
    }
    for (final path in paths) {
      path.draw(canvas, opacity: opacity, colorFilter: colorFilter);
    }
    if (o != ui.Offset.zero) {
      canvas.restore();
    }
  }

  /// Parses [source] into [paths], [origin], [viewBox] and the bounds.
  void _import(String source) {
    final (svg, viewBoxOrigin) = _prepared(source);
    final instructions = parseWithoutOptimizers(svg);
    origin = viewBoxOrigin;
    viewBox = origin & ui.Size(instructions.width, instructions.height);

    // The converted paints, by paint ID and opacity, and the converted paths,
    // by path ID and paint. vector_graphics_compiler shares a path among the
    // draws with the same path data, so each converts once.
    final paints = <(int, double), VectorPaint>{};
    // The same paints without their fills, for paths without an area.
    final unfilled = <VectorPaint, VectorPaint>{};
    final converted = <(int, VectorPaint), VectorPath>{};

    // The consecutive paths to merge, added to [paths] when the run ends.
    // Merging only consecutive paths keeps the SVG's paint order. Merging only
    // paths whose bounds with their strokes don't overlap keeps their look.
    // Overlapping contours of a merged path could cancel each other out,
    // depending on their direction and fill type. Overlapping translucent
    // paints wouldn't add up either.
    final run = <VectorPath>[];
    final runBounds = <ui.Rect>[];
    // The union of their bounds. A path that misses it can't overlap any of
    // them, so it's checked first.
    ui.Rect? runUnion;
    VectorPaint? runPaint;

    void endRun() {
      if (run.isEmpty) {
        return;
      }
      if (run.length == 1) {
        paths.add(run.first);
      } else {
        final merged = ui.Path()..fillType = run.first.path.fillType;
        for (final path in run) {
          merged.addPath(path.path, ui.Offset.zero);
        }
        paths.add(VectorPath(merged, run.first.paint));
      }
      run.clear();
      runBounds.clear();
      runUnion = null;
      runPaint = null;
    }

    // How deep the commands are in a mask or a pattern, whose own shapes are
    // skipped. A mask's shapes only say which parts of its content show, and
    // a pattern's shapes are its tile.
    var skipDepth = 0;
    // The product of the opacities of the layers the commands are in, and its
    // value before each save, which each restore pops.
    var opacity = 1.0;
    final saved = <double>[];

    for (final c in instructions.commands) {
      if (c.type != DrawCommandType.path) {
        // Other commands, such as clips, aren't imported, but they still end
        // the run of paths to merge.
        endRun();
        switch (c.type) {
          case DrawCommandType.saveLayer ||
              DrawCommandType.clip ||
              DrawCommandType.mask ||
              DrawCommandType.pattern:
            saved.add(opacity);
            final layer = c.type == DrawCommandType.saveLayer
                ? instructions.paints[c.paintId!]
                : null;
            if (skipDepth > 0) {
              skipDepth++;
            } else if (c.type == DrawCommandType.mask ||
                c.type == DrawCommandType.pattern) {
              skipDepth = 1;
            } else if (layer?.blendMode == BlendMode.dstIn) {
              // Only alpha masks use this blend mode, which SVG groups can't
              // have.
              skipDepth = 1;
            } else if (layer != null) {
              opacity *= ((layer.fill?.color.value ?? 0xFF000000) >>> 24) / 255;
            }
          case DrawCommandType.restore:
            if (skipDepth > 0) {
              skipDepth--;
            }
            if (saved.isNotEmpty) {
              opacity = saved.removeLast();
            }
          default:
        }
        continue;
      }
      // Paths painted with a pattern are skipped too, as they'd be painted
      // white.
      if (skipDepth > 0 || c.patternId != null) {
        continue;
      }

      final paintId = c.paintId, pathId = c.objectId;
      if (paintId == null || pathId == null) {
        endRun();
        continue;
      }
      var paint = paints[(paintId, opacity)] ??= instructions.paints[paintId]
          .toVectorPaint(opacity);
      if (paint.isFilled && !instructions.paths[pathId].hasArea) {
        paint = unfilled[paint] ??= VectorPaint(stroke: paint.stroke);
      }
      // Skip paths that paint nothing, such as with a gradient without
      // colors, or with only a fill and no area.
      if (!paint.isFilled && !paint.isStroked) {
        continue;
      }
      final path = converted[(pathId, paint)] ??= VectorPath(
        instructions.paths[pathId].toUiPath(),
        paint,
      );

      // Paths with both a fill and a stroke aren't merged: a merged path paints
      // its fill for all its paths, then its stroke, which would change the
      // paint order. Paths with another fill type aren't merged either, as a
      // merged path has only one.
      final canMerge = merge && !(paint.isFilled && paint.isStroked);
      final b = _paintedBounds(path);
      if (!canMerge ||
          !identical(paint, runPaint) ||
          path.path.fillType != run.first.path.fillType ||
          (runUnion != null &&
              runUnion!.overlaps(b) &&
              runBounds.any(b.overlaps))) {
        endRun();
      }
      run.add(path);
      runBounds.add(b);
      runUnion = runUnion?.expandToInclude(b) ?? b;
      runPaint = paint;
      if (!canMerge) {
        endRun();
      }
    }
    endRun();

    ui.Rect? all, painted;
    for (final path in paths) {
      final stroke = path.paint.stroke;
      final b = path.path.getBounds().inflate(
        stroke == null ? 0 : stroke.strokeWidth / 2,
      );
      all = all?.expandToInclude(b) ?? b;
      final p = _paintedBounds(path);
      painted = painted?.expandToInclude(p) ?? p;
    }
    bounds = all == null || all.isEmpty ? ui.Rect.zero : all.shift(origin);
    paintedBounds = painted == null || painted.isEmpty
        ? ui.Rect.zero
        : painted.shift(origin);
  }

  /// The bounds of [path] with its stroke, if any, for merging.
  static ui.Rect _paintedBounds(VectorPath path) =>
      paintedBoundsOf(path.path.getBounds(), path.paint.stroke);

  /// A path's [bounds], grown to take in its [stroke], if any.
  ///
  /// A miter join can reach the miter limit times half the stroke's width.
  /// Other joins and caps reach less than twice its width.
  static ui.Rect paintedBoundsOf(ui.Rect bounds, ui.Paint? stroke) {
    if (stroke == null) {
      return bounds;
    }
    final reach = stroke.strokeJoin == ui.StrokeJoin.miter
        ? max(2.0, miterLimitOf(stroke) / 2)
        : 2.0;
    return bounds.inflate(stroke.strokeWidth * reach);
  }

  /// [svg], edited so that vector_graphics_compiler parses it into the core's
  /// paths, and the root `<svg>`'s viewBox origin.
  ///
  /// vector_graphics_compiler parses that origin the same way, but only to
  /// move the paths by it. The edits:
  /// - The root gets SVG's default stroke width, 1, unless it sets one.
  ///   vector_graphics_compiler scales a stroke's width by its transform only
  ///   when the SVG sets the width. It gives other strokes a width of 1 after
  ///   the transform, while the core's NanoSVG scales the default 1 too. Set
  ///   on the root, the default is inherited as set, and scaled. It goes
  ///   before the root's other attributes, so the root's `style` still
  ///   overrides it.
  /// - Clip-path attributes go, in `style` too, as NanoSVG ignores them.
  ///   vector_graphics_compiler would draw a group once per clip path, where a
  ///   `<clipPath>` mixes clip rules.
  static (String, ui.Offset) _prepared(String svg) {
    final edits = <(int, int, String)>[];
    ui.Offset? origin;
    // Parse past the root only if the SVG has clip paths, as parsing all of it
    // costs about a quarter of an import.
    final clips = _clipPath.hasMatch(svg);
    for (final event in parseEvents(svg, withLocation: true)) {
      if (event is! XmlStartElementEvent) {
        continue;
      }
      final start = event.start!, stop = event.stop!;
      String? tag;
      if (origin == null) {
        origin = ui.Offset.zero;
        var hasWidth = false;
        for (final attribute in event.attributes) {
          if (attribute.name == 'stroke-width') {
            hasWidth = true;
          }
          if (attribute.name != 'viewBox') {
            continue;
          }
          final parts = attribute.value.trim().split(RegExp(r'[ ,]+'));
          if (parts.length >= 4) {
            origin = ui.Offset(
              double.tryParse(parts[0]) ?? 0,
              double.tryParse(parts[1]) ?? 0,
            );
          }
        }
        if (!hasWidth) {
          // Insert it right after the root's name, which follows its '<'.
          final at = 1 + event.name.length;
          final root = svg.substring(start, stop);
          tag =
              '${root.substring(0, at)} stroke-width="1"${root.substring(at)}';
        }
      }
      if (event.attributes.any(
        (a) =>
            a.name == 'clip-path' ||
            (a.name == 'style' && a.value.contains('clip-path')),
      )) {
        tag = (tag ?? svg.substring(start, stop))
            .replaceAll(_clipPathAttribute, '')
            .replaceAll(_clipPathStyle, '');
      }
      if (tag != null) {
        edits.add((start, stop, tag));
      }
      if (!clips) {
        break;
      }
    }
    if (edits.isEmpty) {
      return (svg, origin ?? ui.Offset.zero);
    }
    final prepared = StringBuffer();
    var from = 0;
    for (final (start, stop, tag) in edits) {
      prepared
        ..write(svg.substring(from, start))
        ..write(tag);
      from = stop;
    }
    prepared.write(svg.substring(from));
    return (prepared.toString(), origin ?? ui.Offset.zero);
  }

  // Searched with a RegExp, as String.contains took longer than the rest of
  // _prepared on a 100 KB SVG.
  static final _clipPath = RegExp('clip-path');

  static final _clipPathAttribute = RegExp(
    r"""\sclip-path\s*=\s*("[^"]*"|'[^']*')""",
  );

  // Matches clip-path in a style attribute's value, the only place left in a
  // tag once _clipPathAttribute's matches are gone.
  static final _clipPathStyle = RegExp(r"""clip-path\s*:[^;"']*;?""");
}

/// A path's fill and stroke paints, either of which may be null.
class const VectorPaint({final ui.Paint? fill, final ui.Paint? stroke}) {
  bool get isFilled => fill != null;
  bool get isStroked => stroke != null;
}

/// A path and its paints.
class VectorPath(final ui.Path path, final VectorPaint paint) {
  /// Draws the fill, then the stroke, both from [path].
  ///
  /// The fill closes open contours, as in SVG. [opacity] scales both paints'
  /// alpha, and [colorFilter] filters their colors.
  void draw(
    ui.Canvas canvas, {
    double opacity = 1,
    ui.ColorFilter? colorFilter,
  }) {
    final fill = paint.fill, stroke = paint.stroke;
    if (fill != null) {
      _drawPath(canvas, fill, opacity, colorFilter);
    }
    if (stroke != null) {
      _drawPath(canvas, stroke, opacity, colorFilter);
    }
  }

  /// Draws [path] with [paint], its alpha scaled by [opacity] and its color
  /// filtered by [colorFilter].
  ///
  /// The paint color's alpha scales a gradient's too. The paint is restored
  /// afterwards, as the canvas reads it when it draws.
  void _drawPath(
    ui.Canvas canvas,
    ui.Paint paint,
    double opacity,
    ui.ColorFilter? colorFilter,
  ) {
    if (opacity == 1 && colorFilter == null) {
      return canvas.drawPath(path, paint);
    }
    final color = paint.color;
    if (opacity != 1) {
      paint.color = color.withValues(alpha: color.a * opacity);
    }
    paint.colorFilter = colorFilter;
    canvas.drawPath(path, paint);
    paint
      ..color = color
      ..colorFilter = null;
  }
}
