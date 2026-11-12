import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../rasterizer_gpu.dart';

/// Wraps a canvas for one frame, so that scenes drawn with [drawScene] go
/// into a [RasterizerFrame].
///
/// Scenes drawn one after another make up a run: the renderer draws them as
/// one image, at the run's place in the paint order. Everything else is drawn
/// straight into the wrapped canvas.
///
/// A run ends when:
/// - anything else is drawn, as the run's image must be drawn before it.
/// - the clip changes, by a clip, a saveLayer or a restore that undoes one.
///   The run's image is drawn under the canvas state at the run's end, which
///   must clip it as its entries were clipped.
/// - a scene is drawn with another paint, as the run's image is drawn with
///   one paint: see [drawScene].
///
/// Transforms don't end runs, as each entry has its own. So runs only split
/// where other content is drawn between scenes, where a clip or layer
/// separates them, or where their paints differ.
///
/// A scene drawn under a transform with perspective is drawn in perspective,
/// in its run. With the GPU renderer, it's a run of its own instead, whose
/// image is drawn warped by the perspective: see [drawScene].
///
/// A run that ends while the canvas's transform can't be inverted, as under a
/// scale of 0, is drawn once a restore undoes that transform. If that restore
/// also undoes a clip the run was drawn under, the run is drawn without that
/// clip. That happens when the clip and the transform are in one save. A
/// transform made in a save of its own, before what it draws, never does
/// this. Flame's components make theirs that way.
///
/// When a run ends, it's placed at once ([RasterizerRun.place]), and its
/// image is drawn, before the frame has rendered. So render the frame after
/// [end], before Flutter rasterizes the painting. With the canvas renderer,
/// the run's paths are drawn at once instead.
///
/// ```dart
/// final frame = renderer.beginFrame(widthPx, heightPx);
/// rasterizerCanvas.begin(canvas, frame, devicePixelRatio);
/// rasterizerCanvas.drawScene(coin, 1, 0, 0, 1, x, y);
/// rasterizerCanvas.drawRect(rect, paint); // Ends the run.
/// rasterizerCanvas.drawScene(coin, 1, 0, 0, 1, x2, y2);
/// rasterizerCanvas.end();
/// frame.render();
/// ```
class RasterizerCanvas() implements ui.Canvas {
  late ui.Canvas _canvas;
  late RasterizerFrame _frame;
  RasterizerRun? _run;
  double _pixelRatio = 1;
  ui.FilterQuality _filterQuality = ui.FilterQuality.none;
  bool _warpPerspective = false;

  // The current run's paint: a copy of the fields that draw it, or null for
  // the default paint.
  ui.Paint? _runPaint;

  // Maps recorder space, the canvas's own, to the viewport's device pixels,
  // as a, b, c, d, tx and ty. It's the inverse of the canvas's transform at
  // [begin], which includes the viewport's offset in its layer, then the
  // device pixel ratio.
  double _pa = 1, _pb = 0, _pc = 0, _pd = 1, _ptx = 0, _pty = 0;

  // The canvas's transform at [begin].
  late Float64List _base;

  // The base's determinant, which singular transforms are measured against.
  double _baseDet = 1;

  // Whether the base can't be inverted, as under a parent scaled to 0. The
  // frame then covers no pixels, and scenes aren't added to it.
  bool _singularBase = false;

  // Per save since [begin], whether it clips, by a clip or as a layer.
  // Restoring a save that clips ends the current run.
  final List<bool> _clips = [];

  // Runs that ended but aren't drawn yet, with their paints: see
  // [_drawPending].
  final List<(RasterizerRun, ui.Paint?)> _pending = [];

  /// The canvas that it wraps, as of [begin].
  ui.Canvas get canvas => _canvas;

  /// How many runs the frame has so far.
  int get runCount => _runCount;
  int _runCount = 0;

  /// Whether runs under perspective are drawn as warped images.
  ///
  /// True warps them for every renderer, and false for none. Null, the
  /// default, warps them only for the GPU renderer. [begin] reads it.
  @visibleForTesting
  bool? warpPerspective;

  /// Begins wrapping [canvas] for [frame].
  ///
  /// The frame's viewport is the area drawn into, in device pixels:
  /// [pixelRatio] times its logical size, from the canvas's current origin.
  ///
  /// The GPU renderer's runs only take affine transforms
  /// ([RasterizerRun.addProjective]). So with it, perspective is drawn by
  /// warping runs' images: see [drawScene].
  ///
  /// Runs' images are drawn with [filterQuality]. With the default, none,
  /// they're sharp at the device's pixel ratio. A [pixelRatio] below that, as
  /// for a viewport larger than the renderer takes
  /// ([RasterizerRenderer.maxViewportSize]), scales them up, and
  /// [ui.FilterQuality.low] smooths them.
  void begin(
    ui.Canvas canvas,
    RasterizerFrame frame,
    double pixelRatio, {
    ui.FilterQuality filterQuality = ui.FilterQuality.none,
  }) {
    _canvas = canvas;
    _frame = frame;
    _run = null;
    _pixelRatio = pixelRatio;
    _filterQuality = filterQuality;
    _warpPerspective =
        warpPerspective ?? frame.backend == RasterizerBackend.gpu;
    _clips.clear();
    _pending.clear();
    _runCount = 0;
    _base = canvas.getTransform();
    // The inverse of the base's 2D affine part, scaled by the pixel ratio.
    final a = _base[0],
        b = _base[1],
        c = _base[4],
        d = _base[5],
        tx = _base[12],
        ty = _base[13];
    final det = a * d - b * c, s = pixelRatio / det;
    _baseDet = det;
    _singularBase = !(det.abs() > 0) || !det.isFinite;
    _pa = d * s;
    _pb = -b * s;
    _pc = -c * s;
    _pd = a * s;
    _ptx = (c * ty - d * tx) * s;
    _pty = (b * tx - a * ty) * s;
  }

  /// Ends the frame's last run, so the frame is ready to render.
  ///
  /// Runs still waiting for an invertible transform are dropped, as they'd
  /// cover no pixels.
  void end() {
    _endRun();
    _pending.clear();
  }

  /// Draws [scene] into the current run.
  ///
  /// [a], [b], [c], [d], [tx] and [ty] map the scene's coordinates into the
  /// canvas's current ones: (x, y) goes to (a * x + c * y + tx,
  /// b * x + d * y + ty).
  ///
  /// [paint]'s color's alpha fades each of the scene's paths, so paths that
  /// overlap show through each other, unlike in a sprite. A scene whose alpha
  /// is 0 isn't drawn. The paint's other fields apply as a sprite's do: the
  /// run is drawn as one image with its color filter, blend mode, image
  /// filter, mask filter and inverted colors.
  ///
  /// Entries share a run while those fields draw alike, whatever their alphas.
  /// Another paint ends the run. A paint that only fades (srcOver, no
  /// filters) makes the run draw with no paint. So does a paint whose only
  /// filter is a color filter that a [RasterizerColorTransform] made, such as
  /// a tint. The scene's paths are filtered instead, which gives the same
  /// pixels, so tinted scenes share runs too.
  ///
  /// Under a transform with perspective, the mesh and canvas renderers draw
  /// the scene in perspective, in the current run. The GPU renderer ends the
  /// current run, and gives the scene a run of its own, ended at once. It
  /// renders the scene with the transform's affine part, scaled to the
  /// perspective's scale at the scene's center. It then draws the run's image
  /// warped by the transform after that affine part's inverse, which puts
  /// each of the image's points where the perspective puts them. The image is
  /// resampled with [ui.FilterQuality.low]. What the affine part puts outside
  /// the viewport isn't drawn.
  void drawScene(
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty, {
    ui.Paint? paint,
  }) {
    final opacity = paint?.color.a ?? 1;
    // Nothing is drawn, so the run doesn't end either.
    if (!(opacity > 0) || _singularBase) {
      return;
    }
    RasterizerColorTransform? colorTransform;
    if (paint != null &&
        (_isDefaultPaint(paint) ||
            (colorTransform = _pathColorTransform(paint)) != null)) {
      paint = null;
    }
    final m = _canvas.getTransform();
    var m0 = m[0], m1 = m[1], m4 = m[4], m5 = m[5], m12 = m[12], m13 = m[13];
    // The w row, on the plane z = 0.
    var g = m[3], h = m[7], i = m[15];
    final warped = _warpPerspective && (g != 0 || h != 0 || i != 1);
    if (warped) {
      _endRun();
      // Runs that ended still wait, so the transform can't be inverted: what's
      // drawn covers no pixels.
      if (_pending.isNotEmpty) {
        return;
      }
      // The perspective's w at the scene's center, which scales the affine
      // part to the perspective's size there.
      final center = scene.bounds.center;
      final x = a * center.dx + c * center.dy + tx,
          y = b * center.dx + d * center.dy + ty;
      final w = m[3] * x + m[7] * y + m[15];
      // Behind the eye.
      if (!(w > 0)) {
        return;
      }
      m0 /= w;
      m1 /= w;
      m4 /= w;
      m5 /= w;
      m12 /= w;
      m13 /= w;
      g = h = 0;
      i = 1;
    } else if (_run != null && !_drawsAlike(_runPaint, paint)) {
      _endRun();
    }
    final run = _run ??= _startRun(paint);
    // The canvas's current transform, then the map from recorder space to the
    // viewport's device pixels. That map is affine, so the w row stays.
    final ma = _pa * m0 + _pc * m1 + _ptx * g,
        mb = _pb * m0 + _pd * m1 + _pty * g;
    final mc = _pa * m4 + _pc * m5 + _ptx * h,
        md = _pb * m4 + _pd * m5 + _pty * h;
    final mtx = _pa * m12 + _pc * m13 + _ptx * i,
        mty = _pb * m12 + _pd * m13 + _pty * i;
    final sa = ma * a + mc * b, sb = mb * a + md * b;
    final sc = ma * c + mc * d, sd = mb * c + md * d;
    final stx = ma * tx + mc * ty + mtx, sty = mb * tx + md * ty + mty;
    if (g == 0 && h == 0 && i == 1) {
      run.add(
        scene,
        sa,
        sb,
        sc,
        sd,
        stx,
        sty,
        opacity: opacity,
        colorTransform: colorTransform,
      );
    } else {
      run.addProjective(
        scene,
        sa,
        sb,
        sc,
        sd,
        stx,
        sty,
        g * a + h * b,
        g * c + h * d,
        g * tx + h * ty + i,
        opacity: opacity,
        colorTransform: colorTransform,
      );
    }
    if (warped) {
      _endWarped(m0, m1, m4, m5, m12, m13);
    }
  }

  /// Ends the current run and draws its image at once, warped.
  ///
  /// The run's one entry was rendered with the affine transform [a], [b], [c],
  /// [d], [tx] and [ty], in place of the canvas's current transform, which has
  /// perspective. The image is drawn under the current transform, after that
  /// affine one's inverse, then the base.
  void _endWarped(
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
  ) {
    final run = _run!;
    _run = null;
    _runCount++;
    run.place();
    if (run.isEmpty) {
      return;
    }
    final t = _toBase(a, c, tx, b, d, ty, 0, 0, 1);
    if (t == null) {
      return;
    }
    _canvas
      ..save()
      ..transform(t);
    run.draw(
      _canvas,
      scale: _pixelRatio,
      paint: _runPaint,
      filterQuality: ui.FilterQuality.low,
    );
    _canvas.restore();
  }

  /// The transform that takes the canvas back to the base, from a canvas
  /// whose transform maps the plane z = 0 by the homography [h0] to [h8].
  ///
  /// The homography is given by rows, from x, y and 1 to x, y and w. The
  /// result is its inverse, then the base's 2D affine part. It's null if the
  /// homography can't be inverted: below a millionth of the base's
  /// determinant (a scale of about 1/1000), the inverse loses precision, and
  /// what's drawn covers about a pixel at most. It's null for NaN too.
  Float64List? _toBase(
    double h0,
    double h1,
    double h2,
    double h3,
    double h4,
    double h5,
    double h6,
    double h7,
    double h8,
  ) {
    final c0 = h4 * h8 - h5 * h7,
        c1 = h5 * h6 - h3 * h8,
        c2 = h3 * h7 - h4 * h6;
    final det = h0 * c0 + h1 * c1 + h2 * c2;
    // A homography scaled by s has s³ times the determinant.
    final s = h8.abs();
    if (!(det.abs() > 1e-6 * _baseDet.abs() * s * s * s)) {
      return null;
    }
    // The inverse, by rows: the adjugate over the determinant.
    final i0 = c0 / det,
        i1 = (h2 * h7 - h1 * h8) / det,
        i2 = (h1 * h5 - h2 * h4) / det,
        i3 = c1 / det,
        i4 = (h0 * h8 - h2 * h6) / det,
        i5 = (h2 * h3 - h0 * h5) / det,
        i6 = c2 / det,
        i7 = (h1 * h6 - h0 * h7) / det,
        i8 = (h0 * h4 - h1 * h3) / det;
    final base = _base;
    final b0 = base[0], b1 = base[1], b4 = base[4], b5 = base[5];
    final b12 = base[12], b13 = base[13];
    // Column by column, with x, y and w in rows and columns 0, 1 and 3 of a
    // 4 × 4 matrix.
    return Float64List(16)
      ..[0] = i0 * b0 + i1 * b1
      ..[1] = i3 * b0 + i4 * b1
      ..[3] = i6 * b0 + i7 * b1
      ..[4] = i0 * b4 + i1 * b5
      ..[5] = i3 * b4 + i4 * b5
      ..[7] = i6 * b4 + i7 * b5
      ..[10] = 1
      ..[12] = i0 * b12 + i1 * b13 + i2
      ..[13] = i3 * b12 + i4 * b13 + i5
      ..[15] = i6 * b12 + i7 * b13 + i8;
  }

  // The run's copy of the paint is opaque, as each entry has its own opacity.
  RasterizerRun _startRun(ui.Paint? paint) {
    _runPaint = paint == null ? null : _layerPaint(paint);
    return _frame.addRun();
  }

  /// Draws vector content into [canvas] with [paint], as [drawScene] takes it.
  ///
  /// It's for a canvas that isn't a [RasterizerCanvas], such as a picture's.
  /// [draw] draws the content with each path's alpha scaled by the opacity
  /// it's passed, and its color filtered by the color transform's filter, if
  /// any. [paint]'s other fields apply to the content as a whole, in a layer.
  /// Nothing is drawn if [paint]'s alpha is 0.
  static void drawWithPaint(
    ui.Canvas canvas,
    ui.Paint? paint,
    void Function(double opacity, RasterizerColorTransform? colorTransform)
    draw,
  ) {
    final opacity = paint?.color.a ?? 1;
    if (!(opacity > 0)) {
      return;
    }
    final colorTransform = paint == null ? null : _pathColorTransform(paint);
    // The layer is in the canvas's current units, as a sprite's paint is. It's
    // unbounded, as paths can draw outside their scene's rect.
    final layer =
        paint != null && colorTransform == null && !_isDefaultPaint(paint);
    if (layer) {
      canvas.saveLayer(null, _layerPaint(paint));
    }
    draw(opacity, colorTransform);
    if (layer) {
      canvas.restore();
    }
  }

  /// Whether a scene drawn with [paint] is drawn as with no paint.
  ///
  /// The paint's alpha fades each path instead, and its RGB isn't used, as
  /// for a sprite.
  static bool _isDefaultPaint(ui.Paint paint) =>
      paint.blendMode == ui.BlendMode.srcOver &&
      paint.colorFilter == null &&
      paint.imageFilter == null &&
      paint.maskFilter == null &&
      !paint.invertColors;

  /// [paint]'s color filter as a transform that each path takes, with the
  /// same pixels, or null.
  ///
  /// It's null unless the filter is one that [RasterizerColorTransform] made,
  /// and the only field that makes [paint] not a default one
  /// ([_isDefaultPaint]). A scene drawn with [paint] is then drawn as with no
  /// paint, its paths filtered.
  static RasterizerColorTransform? _pathColorTransform(ui.Paint paint) {
    final filter = paint.colorFilter;
    if (filter == null ||
        paint.blendMode != ui.BlendMode.srcOver ||
        paint.imageFilter != null ||
        paint.maskFilter != null ||
        paint.invertColors) {
      return null;
    }
    return RasterizerColorTransform.of(filter);
  }

  /// The paint of the layer that a scene drawn with [paint] is drawn into.
  ///
  /// It copies the fields that apply as a sprite's do. It's opaque, as
  /// [paint]'s alpha fades each path instead.
  static ui.Paint _layerPaint(ui.Paint paint) => ui.Paint()
    ..colorFilter = paint.colorFilter
    ..blendMode = paint.blendMode
    ..imageFilter = paint.imageFilter
    ..maskFilter = paint.maskFilter
    ..invertColors = paint.invertColors;

  /// Whether images drawn with [p] and [q] look the same, whatever the
  /// paints' colors, as their alphas fade the entries instead.
  ///
  /// Null stands for the default paint.
  static bool _drawsAlike(ui.Paint? p, ui.Paint? q) {
    if (p == null || q == null) {
      return p == q;
    }
    return p.blendMode == q.blendMode &&
        p.colorFilter == q.colorFilter &&
        p.imageFilter == q.imageFilter &&
        p.maskFilter == q.maskFilter &&
        p.invertColors == q.invertColors;
  }

  /// Ends the current run: places it in the atlas, then draws its image, or
  /// its paths, with any runs that ended before it ([_drawPending]).
  void _endRun() {
    final run = _run;
    if (run != null) {
      _run = null;
      _runCount++;
      run.place();
      if (!run.isEmpty) {
        _pending.add((run, _runPaint));
      }
    }
    _drawPending();
  }

  /// Draws the runs that ended, each with its paint, in the canvas's space as
  /// at [begin].
  ///
  /// It can't while the canvas's transform can't be inverted to get back
  /// there, as under a scale of 0, such as one animated from or to zero. The
  /// runs then wait for the restore that undoes that transform. What's drawn
  /// meanwhile covers no pixels, so they're still drawn before anything that
  /// shows. As clips end runs, they're drawn under the clip they ended under,
  /// unless that restore undoes it too: see [RasterizerCanvas].
  void _drawPending() {
    if (_pending.isEmpty) {
      return;
    }
    // The current transform's inverse, then the base, so the canvas's
    // transform becomes the base. It's the full transform on the plane z = 0,
    // perspective included.
    final m = _canvas.getTransform();
    final t = _toBase(m[0], m[4], m[12], m[1], m[5], m[13], m[3], m[7], m[15]);
    if (t == null) {
      return;
    }
    _canvas
      ..save()
      ..transform(t);
    for (final (run, paint) in _pending) {
      run.draw(
        _canvas,
        scale: _pixelRatio,
        paint: paint,
        filterQuality: _filterQuality,
      );
    }
    _canvas.restore();
    _pending.clear();
  }

  // State.

  @override
  void save() {
    _clips.add(false);
    _canvas.save();
  }

  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) {
    _endRun();
    _clips.add(true);
    _canvas.saveLayer(bounds, paint);
  }

  @override
  void restore() {
    if (_clips.isNotEmpty && _clips.removeLast()) {
      _endRun();
    }
    _canvas.restore();
    _drawPending();
  }

  @override
  void restoreToCount(int count) {
    final saves = _canvas.getSaveCount() - (count < 1 ? 1 : count);
    for (var i = 0; i < saves && _clips.isNotEmpty; i++) {
      if (_clips.removeLast()) {
        _endRun();
      }
    }
    _canvas.restoreToCount(count);
    _drawPending();
  }

  @override
  int getSaveCount() => _canvas.getSaveCount();

  void _clip() {
    _endRun();
    if (_clips.isNotEmpty) {
      _clips[_clips.length - 1] = true;
    }
  }

  // Transforms, which runs don't depend on.

  @override
  void translate(double dx, double dy) => _canvas.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => _canvas.scale(sx, sy);

  @override
  void rotate(double radians) => _canvas.rotate(radians);

  @override
  void skew(double sx, double sy) => _canvas.skew(sx, sy);

  @override
  void transform(Float64List matrix4) => _canvas.transform(matrix4);

  @override
  Float64List getTransform() => _canvas.getTransform();

  // Clips.

  @override
  void clipRect(
    ui.Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    _clip();
    _canvas.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  }

  @override
  void clipRRect(ui.RRect rrect, {bool doAntiAlias = true}) {
    _clip();
    _canvas.clipRRect(rrect, doAntiAlias: doAntiAlias);
  }

  @override
  void clipRSuperellipse(
    ui.RSuperellipse rsuperellipse, {
    bool doAntiAlias = true,
  }) {
    _clip();
    _canvas.clipRSuperellipse(rsuperellipse, doAntiAlias: doAntiAlias);
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    _clip();
    _canvas.clipPath(path, doAntiAlias: doAntiAlias);
  }

  @override
  ui.Rect getLocalClipBounds() => _canvas.getLocalClipBounds();

  @override
  ui.Rect getDestinationClipBounds() => _canvas.getDestinationClipBounds();

  // Draws, which end the current run.

  @override
  void drawColor(ui.Color color, ui.BlendMode blendMode) {
    _endRun();
    _canvas.drawColor(color, blendMode);
  }

  @override
  void drawLine(ui.Offset p1, ui.Offset p2, ui.Paint paint) {
    _endRun();
    _canvas.drawLine(p1, p2, paint);
  }

  @override
  void drawPaint(ui.Paint paint) {
    _endRun();
    _canvas.drawPaint(paint);
  }

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    _endRun();
    _canvas.drawRect(rect, paint);
  }

  @override
  void drawRRect(ui.RRect rrect, ui.Paint paint) {
    _endRun();
    _canvas.drawRRect(rrect, paint);
  }

  @override
  void drawDRRect(ui.RRect outer, ui.RRect inner, ui.Paint paint) {
    _endRun();
    _canvas.drawDRRect(outer, inner, paint);
  }

  @override
  void drawRSuperellipse(ui.RSuperellipse rsuperellipse, ui.Paint paint) {
    _endRun();
    _canvas.drawRSuperellipse(rsuperellipse, paint);
  }

  @override
  void drawOval(ui.Rect rect, ui.Paint paint) {
    _endRun();
    _canvas.drawOval(rect, paint);
  }

  @override
  void drawCircle(ui.Offset c, double radius, ui.Paint paint) {
    _endRun();
    _canvas.drawCircle(c, radius, paint);
  }

  @override
  void drawArc(
    ui.Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) {
    _endRun();
    _canvas.drawPath(path, paint);
  }

  @override
  void drawImage(ui.Image image, ui.Offset offset, ui.Paint paint) {
    _endRun();
    _canvas.drawImage(image, offset, paint);
  }

  @override
  void drawImageRect(ui.Image image, ui.Rect src, ui.Rect dst, ui.Paint paint) {
    _endRun();
    _canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  void drawImageNine(
    ui.Image image,
    ui.Rect center,
    ui.Rect dst,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawImageNine(image, center, dst, paint);
  }

  @override
  void drawPicture(ui.Picture picture) {
    _endRun();
    _canvas.drawPicture(picture);
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, ui.Offset offset) {
    _endRun();
    _canvas.drawParagraph(paragraph, offset);
  }

  @override
  void drawPoints(
    ui.PointMode pointMode,
    List<ui.Offset> points,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawPoints(pointMode, points, paint);
  }

  @override
  void drawRawPoints(
    ui.PointMode pointMode,
    Float32List points,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawRawPoints(pointMode, points, paint);
  }

  @override
  void drawVertices(
    ui.Vertices vertices,
    ui.BlendMode blendMode,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawVertices(vertices, blendMode, paint);
  }

  @override
  void drawAtlas(
    ui.Image atlas,
    List<ui.RSTransform> transforms,
    List<ui.Rect> rects,
    List<ui.Color>? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawAtlas(
      atlas,
      transforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawRawAtlas(
    ui.Image atlas,
    Float32List rstTransforms,
    Float32List rects,
    Int32List? colors,
    ui.BlendMode? blendMode,
    ui.Rect? cullRect,
    ui.Paint paint,
  ) {
    _endRun();
    _canvas.drawRawAtlas(
      atlas,
      rstTransforms,
      rects,
      colors,
      blendMode,
      cullRect,
      paint,
    );
  }

  @override
  void drawShadow(
    ui.Path path,
    ui.Color color,
    double elevation,
    bool transparentOccluder,
  ) {
    _endRun();
    _canvas.drawShadow(path, color, elevation, transparentOccluder);
  }
}
