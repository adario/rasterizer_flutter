// Checks the cases in the Limits section of flame_rasterizer's README, in the
// app:
//   flutter test integration_test/limits_test.dart \
//     -d <macos|iOS udid|emulator-5554> [--dart-define=BACKEND=atlas|canvas]
//
// Each case draws the same component tree twice. One game uses
// RasterizerSvgComponents of a square SVG, with HasRasterizer. A plain game
// uses RectangleComponents instead. At most 1 pixel in 2,000 may differ by
// over 64/255. Under perspective, the GPU renderer resamples its image, so
// there it's 1 pixel in 100. Each case also checks the game's runs: a run is
// a contiguous group of vector components that draws as one image.
//
// The game draws with demoGpu: the mesh renderer, or the GPU renderer with
// BACKEND=atlas. BACKEND=canvas forces the canvas renderer. On OpenGL ES,
// the GPU renderers draw once their self-test passes.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/post_process.dart';
import 'package:flame/rendering.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_benchmark/game.dart' show demoGpu;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _blue = Color(0xFF3080FF);
const _red = Color(0xFFFF3020);
const _square =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="#3080ff"/><rect x="10" y="10" width="30" height="30" fill="#ff3020"/></svg>';

/// Creates a square component of [size], centered at [position]: an SVG one
/// or a plain one, depending on the game.
typedef Square = PositionComponent Function(Vector2 position, double size);

/// A post process that draws its subtree's image unchanged.
class _PassThrough() extends PostProcess {
  @override
  void postProcess(Vector2 size, Canvas canvas) {
    final image = rasterizeSubtree();
    canvas
      ..save()
      ..scale(1 / pixelRatio)
      ..drawImage(image, Offset.zero, Paint())
      ..restore();
  }
}

/// A component that draws its children through a snapshot.
class _Snap() extends PositionComponent with Snapshot;

/// The cases, by name. Each one adds squares to the world, whose origin is
/// at the game's center.
final _cases = <String, void Function(FlameGame, Square)>{
  'control': (g, sq) => g.world.add(sq(Vector2.zero(), 80)),
  // As control, with the game 0.3 device pixels off the pixel grid. The GPU
  // renderers snap their image to the nearest device pixel, so the plain game
  // they're compared with isn't off. With the canvas renderer, both are.
  'offset': (g, sq) => g.world.add(sq(Vector2.zero(), 80)),
  'rotate3d': (g, sq) => g.world.add(
    sq(Vector2.zero(), 80)
      ..decorator.addLast(
        Rotate3DDecorator(
          center: Vector2.all(40),
          angleY: 0.7,
          perspective: 0.005,
        ),
      ),
  ),
  'rotate3d_child': (g, sq) => g.world.add(
    sq(Vector2.zero(), 80)
      ..decorator.addLast(
        Rotate3DDecorator(
          center: Vector2.all(40),
          angleY: 0.7,
          perspective: 0.005,
        ),
      )
      ..add(
        RectangleComponent(
          position: Vector2.all(10),
          size: Vector2.all(20),
          paint: Paint()..color = _red,
        ),
      ),
  ),
  // A mirrored square, as a character facing left, with a child. It shares
  // one run with an unmirrored square.
  'flip': (g, sq) => g.world.addAll([
    sq(Vector2(-50, 0), 60),
    sq(Vector2(45, 0), 60)
      ..flipHorizontally()
      ..add(
        RectangleComponent(
          position: Vector2.all(5),
          size: Vector2(25, 10),
          paint: Paint()..color = _red,
        ),
      ),
  ]),
  // A turned square in a parent scaled unevenly: a skewed transform.
  'skewed': (g, sq) => g.world.add(
    PositionComponent(scale: Vector2(1.6, 0.7))
      ..add(sq(Vector2.zero(), 60)..angle = 0.5),
  ),
  'clip': (g, sq) => g.world.add(
    ClipComponent.circle(position: Vector2.all(-50), size: Vector2.all(100))
      ..add(sq(Vector2.all(50), 80)),
  ),
  'fixed_resolution': (g, sq) {
    g.camera = CameraComponent.withFixedResolution(
      world: g.world,
      width: 150,
      height: 100,
    );
    g.world.add(sq(Vector2.zero(), 80)..angle = 0.3);
  },
  // A flat square, then one turned in perspective with a child, in one run.
  'rotate3d_mixed': (g, sq) => g.world.addAll([
    sq(Vector2(-50, 0), 60),
    sq(Vector2(45, 0), 60)
      ..decorator.addLast(
        Rotate3DDecorator(
          center: Vector2.all(30),
          angleY: 0.7,
          perspective: 0.005,
        ),
      )
      ..add(
        RectangleComponent(
          position: Vector2.all(10),
          size: Vector2.all(15),
          paint: Paint()..color = _red,
        ),
      ),
  ]),
  'scale0': (g, sq) => g.world.addAll([
    sq(Vector2(-45, 0), 60),
    PositionComponent(position: Vector2(45, 0), scale: Vector2.zero())..addAll([
      sq(Vector2.zero(), 60),
      RectangleComponent(size: Vector2.all(20), paint: Paint()..color = _red),
    ]),
    // After the parent scaled to 0, so that its run goes on past it.
    sq(Vector2(45, 0), 30),
  ]),
  'snapshot': (g, sq) => g.world.add(
    _Snap()
      ..renderSnapshot = true
      ..add(sq(Vector2.zero(), 80)),
  ),
  'post_process': (g, sq) {
    g.camera.postProcess = _PassThrough();
    g.world.add(sq(Vector2.zero(), 80));
  },
};

/// The runs that each case draws, where it isn't 1.
const _runs = {'scale0': 2, 'snapshot': 0, 'post_process': 0};

/// The cases with a perspective transform.
const _perspective = {'rotate3d', 'rotate3d_child', 'rotate3d_mixed'};

/// A case drawn with [svg] in RasterizerSvgComponents.
class _SvgGame(
  final void Function(FlameGame, Square) build,
  final RasterizerSvg svg,
) extends FlameGame with HasRasterizer {
  // Transparent, so that only the squares are compared, not the edges of a
  // game off the pixel grid.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  RasterizerBackend get rasterizerGpu => demoGpu;

  @override
  Future<void> onLoad() async {
    await rasterizerReady;
    build(
      this,
      (p, s) => RasterizerSvgComponent(
        svg: svg,
        position: p,
        size: Vector2.all(s),
        anchor: Anchor.center,
      ),
    );
  }
}

/// The same case drawn with Flame's RectangleComponents, to compare with.
class _PlainGame(final void Function(FlameGame, Square) build)
    extends FlameGame {
  // Transparent, so that only the squares are compared, not the edges of a
  // game off the pixel grid.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async => build(
    this,
    (p, s) => RectangleComponent(
      position: p,
      size: Vector2.all(s),
      anchor: Anchor.center,
      paint: Paint()..color = _blue,
      // The SVG's red mark, in its top left quarter.
      children: [
        RectangleComponent(
          position: Vector2.all(s * 0.1),
          size: Vector2.all(s * 0.3),
          paint: Paint()..color = _red,
        ),
      ],
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.forceCanvas =
      const String.fromEnvironment('BACKEND') == 'canvas';
  RasterizerGpu.allowOpenGles = true;

  for (final MapEntry(key: name, value: build) in _cases.entries) {
    testWidgets(name, (tester) async {
      final gpu = RasterizerGpu.of(demoGpu);
      // On OpenGL ES, the renderer's self-test waits for a rasterized frame,
      // so pump one first.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(gpu.initialize);
      // The canvas renderer draws when forced, where demoGpu isn't supported,
      // as on the web, and on OpenGL ES if demoGpu fails its self-test.
      final canvas = gpu.backend == RasterizerBackend.canvas;
      final atlas = gpu.backend == RasterizerBackend.gpu;
      final svg = RasterizerSvg.fromBytes(utf8.encode(_square), gpu: demoGpu);
      final a = _SvgGame(build, svg);
      final b = _PlainGame(build);
      final ka = GlobalKey();
      final kb = GlobalKey();
      final ratio = tester.view.devicePixelRatio;
      // The games go at the view's top left, one above the other, as a phone
      // is too narrow for both side by side. Their side is a whole number of
      // device pixels, so that both start on the pixel grid.
      final side = (200 * ratio).round() / ratio;
      final off = name == 'offset' ? 0.3 / ratio : 0.0;
      Widget box(GlobalKey k, FlameGame g, double off) => RepaintBoundary(
        key: k,
        child: SizedBox.square(
          dimension: side,
          child: Stack(
            children: [
              Positioned(
                left: off,
                top: off,
                width: side,
                height: side,
                child: GameWidget(game: g),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [box(ka, a, off), box(kb, b, canvas ? off : 0)],
            ),
          ),
        ),
      );
      final result = await tester.runAsync(() async {
        await a.loaded;
        await b.loaded;
        await Future<void>.delayed(const Duration(seconds: 1));
        Future<ui.Image> grab(GlobalKey k) =>
            (k.currentContext!.findRenderObject()! as RenderRepaintBoundary)
                .toImage(pixelRatio: ratio);
        final ia = await grab(ka);
        final ib = await grab(kb);
        final pa = (await ia.toByteData())!.buffer.asUint8List();
        final pb = (await ib.toByteData())!.buffer.asUint8List();
        final w = ia.width;
        final h = ia.height;
        var over64 = 0;
        var over16 = 0;
        var coverA = 0;
        var coverB = 0;
        for (var i = 0; i < w * h; i++) {
          var d = 0;
          for (var c = 0; c < 4; c++) {
            d = math.max(d, (pa[4 * i + c] - pb[4 * i + c]).abs());
          }
          if (d > 64) {
            over64++;
          }
          if (d > 16) {
            over16++;
          }
          if (pa[4 * i + 3] > 128) {
            coverA++;
          }
          if (pb[4 * i + 3] > 128) {
            coverB++;
          }
        }
        // Under perspective, the GPU renderer resamples its image, with errors
        // along the edges. They're a bigger share of the pixels at low pixel
        // ratios: 0.74% at 1, on Linux.
        final perspective = atlas && _perspective.contains(name);
        return (
          line:
              'LIMITS $name (${gpu.backend.name}): ${w}x$h, runs '
              '${a.rasterizerFrame?.runs.length}, covered $coverA vs $coverB, '
              '$over16 pixels over 16/255, $over64 over 64/255 '
              '(${(100 * over64 / (w * h)).toStringAsFixed(2)}%)',
          over64: over64,
          limit: w * h ~/ (perspective ? 100 : 2000),
          runs: a.rasterizerFrame?.runs.length,
          coverA: coverA,
          coverB: coverB,
        );
      });
      final (:line, :over64, :limit, :runs, :coverA, :coverB) = result!;
      // ignore: avoid_print
      print(line);
      // On the web, prints go to the browser's console, so the line also goes
      // to flutter drive's response data.
      (binding.reportData ??= {})[name] = line;
      // With the GPU renderer, a square under perspective is a run of its own,
      // so rotate3d_mixed draws two.
      expect(
        runs,
        atlas && name == 'rotate3d_mixed' ? 2 : _runs[name] ?? 1,
        reason: line,
      );
      expect(over64, lessThanOrEqualTo(limit), reason: line);
      // Both must draw something, as two empty frames differ in no pixel.
      // Their coverages aren't compared: edge pixels are about half covered,
      // so the counts differ by more than over64 does.
      expect(coverA, greaterThan(0), reason: line);
      expect(coverB, greaterThan(0), reason: line);
      await tester.pumpWidget(const SizedBox());
      svg.dispose();
    });
  }
}
