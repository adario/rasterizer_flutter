import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWasm, kIsWeb;

import '../rasterizer_gpu.dart';
import 'canvas_paths.dart';
import 'paths/scene_paths.dart';
import 'svg_paths/svg_paths.dart';
import 'viewport_clip.dart';

/// A scene that the canvas renderer draws with dart:ui: an SVG parsed in
/// Dart, or plain paths.
class CanvasScene._(final CanvasPaths paths) implements RasterizerScene {
  /// Parses [bytes] as SVG data in UTF-8.
  ///
  /// Throws [ArgumentError] if they aren't parseable SVG data.
  factory CanvasScene(Uint8List bytes) {
    final SvgPaths paths;
    try {
      paths = SvgPaths(utf8.decode(bytes));
    } catch (e, stackTrace) {
      Error.throwWithStackTrace(
        ArgumentError('Not parseable SVG data: $e'),
        stackTrace,
      );
    }
    return CanvasScene._(paths);
  }

  /// Creates a scene of plain [paths].
  factory CanvasScene.fromPaths(ScenePaths paths) => CanvasScene._(paths);

  /// The paths, recorded once, for [RasterizerGpu.canvasPictures].
  ui.Picture? _picture;

  @override
  RasterizerBackend get backend => RasterizerBackend.canvas;

  @override
  ui.Rect get bounds => paths.bounds;

  @override
  ui.Rect get viewBox => paths.viewBox;

  /// What [draw] can paint, in the scene's coordinates
  /// ([CanvasPaths.paintedBounds]).
  ui.Rect get paintedBounds => paths.paintedBounds;

  @override
  int get pathCount => paths.drawCount;

  /// Draws the paths into [canvas], in the scene's coordinates.
  ///
  /// [opacity] scales each path's alpha, and [colorFilter] filters its color.
  /// With [RasterizerGpu.canvasPictures], an [opacity] of 1 and no filter, it
  /// draws a picture of the paths, recorded once.
  void draw(
    ui.Canvas canvas, {
    double opacity = 1,
    ui.ColorFilter? colorFilter,
  }) {
    if (!RasterizerGpu.canvasPictures || opacity != 1 || colorFilter != null) {
      return paths.draw(canvas, opacity: opacity, colorFilter: colorFilter);
    }
    canvas.drawPicture(
      _picture ??= () {
        final recorder = ui.PictureRecorder();
        paths.draw(ui.Canvas(recorder));
        return recorder.endRecording();
      }(),
    );
  }

  @override
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) => draw(canvas, opacity: opacity, colorFilter: colorTransform?.filter);

  @override
  void dispose() {
    _picture?.dispose();
    _picture = null;
  }
}

/// The canvas renderer: each run draws its entries' paths straight into the
/// canvas it's drawn into.
///
/// It has no atlas, so a frame's [CanvasFrame.render] does nothing, and runs
/// have no images.
class CanvasRenderer(@override final int slots) implements RasterizerRenderer {
  @override
  RasterizerBackend get backend => RasterizerBackend.canvas;

  @override
  int? get maxViewportSize => null;

  @override
  int get atlasResizes => 0;

  @override
  int get atlasBytes => 0;

  @override
  void trimAtlas() {}

  bool _disposed = false;

  /// The one frame, which each [beginFrame] reuses.
  late final CanvasFrame _frame = CanvasFrame._(this);

  @override
  CanvasFrame beginFrame(int width, int height, {bool curves = true}) {
    if (_disposed) {
      throw StateError('RasterizerRenderer disposed');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid viewport size $width×$height');
    }
    return _frame.._begin(width, height);
  }

  @override
  void dispose() => _disposed = true;
}

/// A canvas renderer's frame: its runs, which draw their entries when they're
/// drawn.
///
/// The renderer reuses one frame, and the frame reuses its runs.
class CanvasFrame._(final CanvasRenderer _renderer) implements RasterizerFrame {
  /// The runs, reused from frame to frame. The first [_runCount] are this
  /// frame's.
  final List<CanvasRun> _runs = [];
  int _runCount = 0, _width = 0, _height = 0;
  bool _rendered = false;

  @override
  int get cpuMicros => 0;
  @override
  int get uploadMicros => 0;
  @override
  int get encodeMicros => 0;

  @override
  List<RasterizerPixelSize> get pageSizes => const [];

  @override
  RasterizerBackend get backend => RasterizerBackend.canvas;

  @override
  int get width => _width;
  @override
  int get height => _height;
  @override
  int get entryCount => runs.fold(0, (n, run) => n + run._count);

  @override
  Iterable<CanvasRun> get runs => _runs.take(_runCount);

  void _begin(int width, int height) {
    _width = width;
    _height = height;
    _rendered = false;
    _runCount = 0;
  }

  @override
  CanvasRun addRun({ui.Rect? clip}) {
    _checkOpen();
    if (_runCount == _runs.length) {
      _runs.add(CanvasRun._(this, _runCount));
    }
    return _runs[_runCount++].._reset(viewportClip(clip, _width, _height, 0));
  }

  @override
  void render() {
    _checkOpen();
    _rendered = true;
  }

  void _checkOpen() {
    if (_renderer._disposed) {
      throw StateError('RasterizerRenderer disposed');
    }
    if (_rendered) {
      throw StateError('RasterizerFrame already rendered: begin a new one');
    }
  }
}

/// A canvas renderer's run: [draw] draws its entries, transformed and clipped
/// to the viewport, and skips those that paint nothing in it or in the run's
/// clip.
class CanvasRun._(final CanvasFrame _frame, @override final int index)
    extends RasterizerRun {
  // The entries' scenes, and their transforms, 9 values each:
  // a b c d tx ty g h i.
  final List<CanvasScene> _scenes = [];
  Float64List _ctms = Float64List(9 * 64);
  Float64List _opacities = Float64List(64);
  final List<ui.ColorFilter?> _colorFilters = [];
  int _count = 0;
  bool _placed = false;

  // The pixels its clip leaves it.
  PixelRect _clip = (left: 0, top: 0, right: 0, bottom: 0);

  // A matrix for Canvas.transform, whose 2D projective part each entry
  // rewrites.
  static final _matrix = Float64List(16)..[10] = 1;

  @override
  List<RasterizerRunPart> get parts => const [];

  @override
  bool get isEmpty => _count == 0;

  void _reset(PixelRect clip) {
    _clip = clip;
    _scenes.clear();
    _colorFilters.clear();
    _count = 0;
    _placed = false;
  }

  @override
  void place() {
    _frame._checkOpen();
    _placed = true;
  }

  @override
  void add(
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) => addProjective(
    scene,
    a,
    b,
    c,
    d,
    tx,
    ty,
    0,
    0,
    1,
    opacity: opacity,
    colorTransform: colorTransform,
  );

  @override
  void addProjective(
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
    double g,
    double h,
    double i, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) {
    _frame._checkOpen();
    if (_placed) {
      throw StateError('RasterizerRun already placed');
    }
    if (scene is! CanvasScene) {
      throw ArgumentError.value(
        scene,
        'scene',
        'Not a scene for the canvas renderer',
      );
    }
    if (!(opacity > 0)) {
      return;
    }
    if (_count == _opacities.length) {
      _ctms = Float64List(_ctms.length * 2)..setAll(0, _ctms);
      _opacities = Float64List(_opacities.length * 2)..setAll(0, _opacities);
    }
    _opacities[_count] = opacity < 1 ? opacity : 1;
    _scenes.add(scene);
    _colorFilters.add(colorTransform?.filter);
    _ctms
      ..[9 * _count] = a
      ..[9 * _count + 1] = b
      ..[9 * _count + 2] = c
      ..[9 * _count + 3] = d
      ..[9 * _count + 4] = tx
      ..[9 * _count + 5] = ty
      ..[9 * _count + 6] = g
      ..[9 * _count + 7] = h
      ..[9 * _count + 8] = i;
    _count++;
  }

  @override
  void draw(
    ui.Canvas canvas, {
    double scale = 1,
    ui.Paint? paint,
    ui.FilterQuality filterQuality = ui.FilterQuality.none,
  }) {
    if (_count == 0) {
      return;
    }
    // Make the layer in the canvas's units, as the GPU renderer draws its
    // image, so the paint's filters, such as a blur's sigma, are in those
    // units. Impeller applies them with the transform at the layer's restore,
    // while Skia does at its save. So the scale is saved and restored inside
    // the layer.
    if (paint != null) {
      canvas.saveLayer(_layerBounds(paint, scale), paint);
    }
    canvas.save();
    if (scale != 1) {
      canvas.scale(1 / scale);
    }
    // CanvasKit drops some pictures drawn near this clip's edge, though they
    // lie inside it, so it draws without it, as Flame's components do. A
    // WebAssembly build draws with skwasm, which draws them.
    final clipped = !kIsWeb || kIsWasm;
    if (clipped) {
      canvas.clipRect(
        ui.Rect.fromLTWH(
          0,
          0,
          _frame.width.toDouble(),
          _frame.height.toDouble(),
        ),
      );
    }
    // Entries that paint nothing in the viewport, or in the run's clip, are
    // skipped, as the clips would hide them. Without the viewport's clip,
    // they're skipped unless the paint can spread them into the viewport.
    final skips =
        clipped ||
        paint == null ||
        (paint.imageFilter == null && paint.maskFilter == null);
    final m = _matrix;
    for (var i = 0; i < _count; i++) {
      if (skips && _missesClip(i)) {
        continue;
      }
      final k = 9 * i;
      m
        ..[0] = _ctms[k]
        ..[1] = _ctms[k + 1]
        ..[3] = _ctms[k + 6]
        ..[4] = _ctms[k + 2]
        ..[5] = _ctms[k + 3]
        ..[7] = _ctms[k + 7]
        ..[12] = _ctms[k + 4]
        ..[13] = _ctms[k + 5]
        ..[15] = _ctms[k + 8];
      canvas.save();
      canvas.transform(m);
      _scenes[i].draw(
        canvas,
        opacity: _opacities[i],
        colorFilter: _colorFilters[i],
      );
      canvas.restore();
    }
    canvas.restore();
    if (paint != null) {
      canvas.restore();
    }
  }

  /// Returns the bounds of a layer drawn with [paint] around the entries, in
  /// units of [scale] device pixels, or null for no bounds.
  ///
  /// A layer costs its area, so the bounds are what the entries can paint, a
  /// device pixel wider for antialiasing. An entry with a corner behind the
  /// eye takes in the viewport, which the entries are clipped to. The bounds
  /// are null if [paint] has an image or a mask filter, which can draw outside
  /// its content.
  ui.Rect? _layerBounds(ui.Paint paint, double scale) {
    if (paint.imageFilter != null || paint.maskFilter != null) {
      return null;
    }
    double left = double.infinity, top = left, right = -left, bottom = -left;
    for (var i = 0; i < _count; i++) {
      if (_scenes[i].paintedBounds.isEmpty) {
        continue;
      }
      final painted = _paintedInViewport(i);
      left = min(left, painted.left);
      top = min(top, painted.top);
      right = max(right, painted.right);
      bottom = max(bottom, painted.bottom);
    }
    if (left > right) {
      return ui.Rect.zero;
    }
    return ui.Rect.fromLTRB(
      (left - 1) / scale,
      (top - 1) / scale,
      (right + 1) / scale,
      (bottom + 1) / scale,
    );
  }

  /// Returns whether entry [i] paints nothing within a device pixel of the
  /// viewport and the run's clip, or its bounds are NaN.
  bool _missesClip(int i) {
    final (:left, :top, :right, :bottom) = _paintedInViewport(i);
    return !(right > _clip.left - 1 &&
        bottom > _clip.top - 1 &&
        left < _clip.right + 1 &&
        top < _clip.bottom + 1);
  }

  /// Returns the bounds of what entry [i] can paint, in the viewport.
  ///
  /// With a corner behind the eye, they take in the viewport too.
  ({double left, double top, double right, double bottom}) _paintedInViewport(
    int i,
  ) {
    final s = _scenes[i].paintedBounds;
    final k = 9 * i;
    final a = _ctms[k], b = _ctms[k + 1], c = _ctms[k + 2], d = _ctms[k + 3];
    final tx = _ctms[k + 4], ty = _ctms[k + 5];
    final g = _ctms[k + 6], h = _ctms[k + 7], w = _ctms[k + 8];
    if (g != 0 || h != 0 || w != 1) {
      double left = double.infinity, top = left, right = -left, bottom = -left;
      for (final (x, y) in [
        (s.left, s.top),
        (s.right, s.top),
        (s.left, s.bottom),
        (s.right, s.bottom),
      ]) {
        final q = g * x + h * y + w;
        if (!(q > 0)) {
          left = min(left, 0);
          top = min(top, 0);
          right = max(right, _frame.width.toDouble());
          bottom = max(bottom, _frame.height.toDouble());
          continue;
        }
        final px = (a * x + c * y + tx) / q, py = (b * x + d * y + ty) / q;
        left = min(left, px);
        right = max(right, px);
        top = min(top, py);
        bottom = max(bottom, py);
      }
      return (left: left, top: top, right: right, bottom: bottom);
    }
    // Each corner's x' and y' are sums of a term in x and a term in y, so
    // their extremes are the sums of each term's extremes.
    final ax0 = a * s.left, ax1 = a * s.right;
    final cy0 = c * s.top, cy1 = c * s.bottom;
    final bx0 = b * s.left, bx1 = b * s.right;
    final dy0 = d * s.top, dy1 = d * s.bottom;
    return (
      left: min(ax0, ax1) + min(cy0, cy1) + tx,
      top: min(bx0, bx1) + min(dy0, dy1) + ty,
      right: max(ax0, ax1) + max(cy0, cy1) + tx,
      bottom: max(bx0, bx1) + max(dy0, dy1) + ty,
    );
  }
}
