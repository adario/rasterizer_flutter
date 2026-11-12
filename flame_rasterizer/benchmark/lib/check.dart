import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart' show RasterizerSvg;
import 'package:flame_rasterizer_benchmark/game.dart';
import 'package:flame_rasterizer_benchmark/layout.dart';
import 'package:flame_rasterizer_benchmark/save_png.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// The correctness check: draws the game with Flame and flame_rasterizer, and
/// the same frame directly with rasterizer_gpu's API, then compares the two.
///
/// The reference computes its transforms here, from the layout, rather than
/// through Flame or a canvas. Both frames are read back, compared, and saved
/// to the temporary directory as flame_check_game.png and
/// flame_check_reference.png, except on the web.
///
/// [time] sets the game's time, and so the camera's zoom. [onResult] gets
/// whether the check passed, and its log line.
class const CheckPage({
  super.key,
  final double time = 3.7,
  final void Function({required bool pass, required String line})? onResult,
}) extends StatefulWidget {
  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState() extends State<CheckPage> {
  /// The size of each of the two frames, in logical pixels.
  static const size = Size(400, 300);
  late final double time = widget.time;

  /// What both frames draw: 120 items in 4 groups, 8 clipped items and the
  /// painted items.
  final DemoLayout layout = DemoLayout(
    count: 120,
    separators: 3,
    clipped: 8,
    painted: true,
  );
  late final RasterizerDemoGame game = RasterizerDemoGame(
    layout: layout,
    separatorKind: Separators.rectangles,
    fixedTime: time,
    hud: false,
  );
  final GlobalKey _gameKey = GlobalKey();
  final GlobalKey _referenceKey = GlobalKey();

  /// The renderer that draws the reference, once it's made.
  RasterizerRenderer? _renderer;

  /// The reference's scenes, one for each of the layout's SVGs.
  List<RasterizerScene>? _scenes;

  /// The text shown over the frames: the result, once it's known.
  String _status = 'Loading';

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// Runs the check, and reports and logs its result.
  ///
  /// It makes the reference's renderer and scenes, lets the game draw 10
  /// frames, and pauses it. Then it reads back both frames, compares them and
  /// saves them.
  Future<void> _run() async {
    try {
      // Wait for demoGpu's self-test, so that both frames draw with it where
      // it's supported. On OpenGL ES, the game's scenes and renderer, made
      // while the self-test ran, switch to it once it completes. The
      // reference's mesh scenes flatten their curves for the same size as
      // the game's.
      await RasterizerGpu.of(demoGpu).initialize();
      final renderer = await RasterizerRenderer.create(gpu: demoGpu);
      final scenes = [
        for (final s in layout.svgs)
          RasterizerScene.fromSvg(
            utf8.encode(s),
            gpu: demoGpu,
            maxSize: RasterizerSvg.defaultMaxSize,
          ),
      ];
      setState(() {
        _renderer = renderer;
        _scenes = scenes;
      });
      await game.loaded;
      await _frames(10);
      game.pauseEngine();
      await _frames(3);
      if (!mounted) {
        throw StateError('the check was removed before its frames were read');
      }
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final gameImage = await _capture(_gameKey, pixelRatio);
      final referenceImage = await _capture(_referenceKey, pixelRatio);
      final w = gameImage.width;
      final h = gameImage.height;
      final a = (await gameImage.toByteData())!.buffer.asUint8List();
      final b = (await referenceImage.toByteData())!.buffer.asUint8List();
      var maxDiff = 0;
      var over1 = 0;
      var over8 = 0;
      for (var i = 0; i < w * h; i++) {
        var d = 0;
        for (var c = 0; c < 4; c++) {
          d = math.max(d, (a[4 * i + c] - b[4 * i + c]).abs());
        }
        if (d > maxDiff) {
          maxDiff = d;
        }
        if (d > 1) {
          over1++;
        }
        if (d > 8) {
          over8++;
        }
      }
      final runs = game.rasterizerFrame?.runs.length ?? 0;
      final expectedRuns =
          layout.groups +
          (layout.clippedItems.isEmpty ? 0 : 1) +
          layout.paintedRuns;
      final pass =
          gameImage.width == referenceImage.width &&
          gameImage.height == referenceImage.height &&
          runs == expectedRuns &&
          over8 <= w * h ~/ _over8Ratio;
      await _save(gameImage, 'flame_check_game');
      await _save(referenceImage, 'flame_check_reference');
      gameImage.dispose();
      referenceImage.dispose();
      final result =
          'FLAME_RASTERIZER check ${pass ? 'PASS' : 'FAIL'}: ${w}x$h, runs '
          '$runs (expected $expectedRuns), '
          'max diff $maxDiff/255, $over1 pixels over 1/255, $over8 over '
          '8/255 (at most ${w * h ~/ _over8Ratio}), '
          '${pngDirectory == null ? 'not saved' : 'saved to $pngDirectory'}';
      debugPrint(result);
      if (mounted) {
        setState(() => _status = result);
      }
      widget.onResult?.call(pass: pass, line: result);
    } on Object catch (e, stack) {
      debugPrint('FLAME_RASTERIZER check FAILED: $e\n$stack');
      if (mounted) {
        setState(() => _status = 'FAILED: $e');
      }
      widget.onResult?.call(pass: false, line: 'FAILED: $e');
    }
  }

  /// At most 1 pixel in this many may differ by over 8/255: 1 in 10,000 with
  /// Impeller, 1 in 800 with Skia.
  ///
  /// On the web, Skia antialiases edges analytically, rather than with
  /// Impeller's MSAA. The game and the reference compose their transforms in
  /// different orders, rounded to floats, so edges move by fractions of a
  /// pixel. At the 4 times that check_test.dart uses, 21 to 106 of 120,000
  /// pixels differed by over 8/255, all scattered edge pixels, by at most
  /// 36/255. The painted items, each with its own opacity, show more edges
  /// through the translucent ones: 41 to 120 pixels at those times, at a
  /// pixel ratio of 1.
  ///
  /// Skia does the same without Impeller (`--no-enable-impeller`). On macOS,
  /// 130 to 207 of 480,000 pixels differed, all on edges, by at most 31/255.
  /// On the Android emulator, 126 to 317 of 827,400 did, by at most 22/255.
  static final _over8Ratio =
      kIsWeb || RasterizerGpu.support == RasterizerSupport.noImpeller
      ? 800
      : 10000;

  /// Waits for [n] frames, scheduling each one.
  static Future<void> _frames(int n) async {
    for (var i = 0; i < n; i++) {
      final done = Completer<void>();
      SchedulerBinding.instance.addPostFrameCallback((_) => done.complete());
      SchedulerBinding.instance.scheduleFrame();
      await done.future;
    }
  }

  /// Reads back what the repaint boundary at [key] drew, at [pixelRatio].
  Future<ui.Image> _capture(GlobalKey key, double pixelRatio) =>
      (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
          .toImage(pixelRatio: pixelRatio);

  /// Saves [image] as a PNG named [name], where the platform can: see
  /// [savePng].
  static Future<void> _save(ui.Image image, String name) async {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    savePng(name, png!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _renderer?.dispose();
    for (final scene in _scenes ?? const <RasterizerScene>[]) {
      scene.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    final scenes = _scenes;
    return Directionality(
      textDirection: TextDirection.ltr,
      // The two frames, one above the other, fit the 800 x 600 window that
      // integration tests get on macOS. The status shows over them.
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  key: _gameKey,
                  child: SizedBox.fromSize(
                    size: size,
                    child: GameWidget(game: game),
                  ),
                ),
                RepaintBoundary(
                  key: _referenceKey,
                  child: SizedBox.fromSize(
                    size: size,
                    child: renderer == null || scenes == null
                        ? null
                        : CustomPaint(
                            painter: _ReferencePainter(
                              renderer,
                              scenes,
                              layout,
                              time,
                              MediaQuery.devicePixelRatioOf(context),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _status,
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Draws the game's frame with rasterizer_gpu's API, from the layout.
///
/// It computes here what Flame computes in the game: the camera, with the
/// viewfinder at the viewport's centre, and each component's transform from
/// its position, angle and centre anchor.
///
/// It applies the painted items' paints differently from the game. It fades
/// each entry by its paint's alpha, with [RasterizerRun.add]'s opacity, so
/// per path. It then draws the run plainly, in a layer with the rest of the
/// paint, rather than with [RasterizerRun.draw]'s paint as the game does.
/// The faded, tinted and hued items share a run, with their tint and hue
/// folded in as [RasterizerRun.add]'s color transform. The core clamps those
/// matrices per path, so a hue differs from a layer's along the edges
/// between paths, by up to 40/255 here.
class _ReferencePainter(
  final RasterizerRenderer renderer,
  final List<RasterizerScene> scenes,
  final DemoLayout layout,
  final double time,
  final double pixelRatio,
) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final (cx, cy, zoom) = DemoLayout.camera(time, size.width, size.height);
    final camera =
        _Affine.translate(size.width / 2, size.height / 2) *
        _Affine.scale(zoom, zoom) *
        _Affine.translate(-cx, -cy);
    final device = _Affine.scale(pixelRatio, pixelRatio);
    const clip = DemoLayout.clipRect;
    final clipped = camera * _Affine.translate(clip.left, clip.top);

    _Affine svgTransform(_Affine parent, VectorItem item) {
      final (x, y, angle) = item.at(time);
      final viewBox = scenes[item.svg].viewBox;
      return parent *
          _Affine.translate(x, y) *
          _Affine.rotate(angle) *
          _Affine.translate(-item.size / 2, -item.size / 2) *
          _Affine.scale(item.size / viewBox.width, item.size / viewBox.height) *
          _Affine.translate(-viewBox.left, -viewBox.top);
    }

    final frame = renderer.beginFrame(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    final runs = [for (var g = 0; g < layout.groups; g++) frame.addRun()];
    for (final item in layout.items) {
      final m = device * svgTransform(camera, item);
      runs[item.group].add(scenes[item.svg], m.a, m.b, m.c, m.d, m.tx, m.ty);
    }
    final clippedRun = frame.addRun();
    for (final item in layout.clippedItems) {
      final m = device * svgTransform(clipped, item);
      clippedRun.add(scenes[item.svg], m.a, m.b, m.c, m.d, m.tx, m.ty);
    }
    // One run per paint, except that neighbours sharing a paint share a run,
    // and so do the items whose paints fold.
    final paintedRuns = <(RasterizerRun, PaintKind)>[];
    for (final (item, kind) in layout.paintedItems) {
      final last = paintedRuns.isEmpty ? null : paintedRuns.last.$2;
      if (last == null ||
          (DemoLayout.folds(kind)
              ? !DemoLayout.folds(last)
              : kind != PaintKind.shared || last != kind)) {
        paintedRuns.add((frame.addRun(), kind));
      }
      final m = device * svgTransform(camera, item);
      paintedRuns.last.$1.add(
        scenes[item.svg],
        m.a,
        m.b,
        m.c,
        m.d,
        m.tx,
        m.ty,
        opacity: DemoLayout.paintOf(kind).color.a,
        colorTransform: DemoLayout.transformOf(kind),
      );
    }
    frame.render();

    // Black, as GameWidget's background.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    for (var g = 0; g < layout.groups; g++) {
      runs[g].draw(canvas, scale: pixelRatio);
      if (g < layout.separators.length) {
        final s = layout.separators[g];
        canvas
          ..save()
          ..transform(
            (camera *
                    _Affine.translate(s.x, s.y) *
                    _Affine.rotate(s.angle) *
                    _Affine.translate(-s.width / 2, -s.height / 2))
                .matrix4,
          )
          ..drawPath(
            Path()..addRect(Rect.fromLTWH(0, 0, s.width, s.height)),
            Paint()..color = s.color,
          )
          ..restore();
      }
    }
    canvas
      ..save()
      ..transform(clipped.matrix4)
      ..clipPath(Path()..addRect(Rect.fromLTWH(0, 0, clip.width, clip.height)))
      ..transform(clipped.inverse.matrix4);
    clippedRun.draw(canvas, scale: pixelRatio);
    canvas.restore();
    for (final (run, kind) in paintedRuns) {
      if (DemoLayout.folds(kind)) {
        run.draw(canvas, scale: pixelRatio);
        continue;
      }
      // Opaque, as the paint's alpha already faded the entries.
      canvas.saveLayer(
        null,
        DemoLayout.paintOf(kind)..color = const Color(0xFF000000),
      );
      run.draw(canvas, scale: pixelRatio);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ReferencePainter old) => true;
}

/// A 2D affine transform: x' = a * x + c * y + tx, y' = b * x + d * y + ty.
///
/// The reference composes its transforms with it, rather than on a canvas.
class const _Affine(
  final double a,
  final double b,
  final double c,
  final double d,
  final double tx,
  final double ty,
) {
  factory _Affine.translate(double x, double y) => _Affine(1, 0, 0, 1, x, y);
  factory _Affine.scale(double x, double y) => _Affine(x, 0, 0, y, 0, 0);
  factory _Affine.rotate(double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return _Affine(c, s, -s, c, 0, 0);
  }

  /// Returns the transform that applies [o], then this one.
  _Affine operator *(_Affine o) => _Affine(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.tx + c * o.ty + tx,
    b * o.tx + d * o.ty + ty,
  );

  /// The transform that undoes this one.
  _Affine get inverse {
    final det = a * d - b * c;
    return _Affine(
      d / det,
      -b / det,
      -c / det,
      a / det,
      (c * ty - d * tx) / det,
      (b * tx - a * ty) / det,
    );
  }

  /// This transform as a column-major 4x4 matrix, for [Canvas.transform].
  Float64List get matrix4 =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
}
