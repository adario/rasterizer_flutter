// Checks projective entries, which RasterizerRun.addProjective adds, in the
// app:
//   flutter test integration_test/projective_test.dart -d <device>
//
// The mesh renderer draws them in perspective, gradients included, through
// the third row of its instances' transforms. A run's part then covers the
// bounds of the projected corners. The canvas renderer agrees, and the GPU
// renderer only draws affine entries. On OpenGL ES, each GPU renderer's tests
// run once its self-test passes.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

const size = 64;

/// A 64 x 64 red square.
const squareSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<rect width="64" height="64" fill="#ff0000"/></svg>';

/// A 64 x 64 square with a linear gradient from red, on the left, to blue.
const gradientSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" '
    'y1="0" x2="64" y2="0"><stop offset="0" stop-color="#ff0000"/>'
    '<stop offset="1" stop-color="#0000ff"/></linearGradient></defs>'
    '<rect width="64" height="64" fill="url(#g)"/></svg>';

const red = [255, 0, 0, 255], clear = [0, 0, 0, 0];

/// Returns what [draw] draws, read back as premultiplied RGBA.
Future<Uint8List> readBack(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording(),
      image = await picture.toImage(size, size);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return Uint8List.sublistView(data!);
}

/// Fails, naming [what], unless the pixel at ([x], [y]) in [pixels] is
/// [rgba], within [within] per channel.
void expectAt(
  Uint8List pixels,
  int x,
  int y,
  List<int> rgba,
  String what, {
  int within = 2,
}) {
  final i = 4 * (y * size + x), p = pixels.sublist(i, i + 4);
  for (var k = 0; k < 4; k++) {
    if ((p[k] - rgba[k]).abs() > within) {
      fail('$what: pixel ($x, $y) is $p, not $rgba');
    }
  }
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;
  runApp(const SizedBox());
  await binding.waitUntilFirstFrameRasterized;
  for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
    await RasterizerGpu.of(gpu).initialize();
  }

  /// Adds a test of [backend], which skips where the backend isn't supported.
  void backendTest(
    RasterizerBackend backend,
    String description,
    Future<void> Function(RasterizerRenderer renderer) body,
  ) => test('${backend.name}: $description', () async {
    if (backend != RasterizerBackend.canvas) {
      final support = RasterizerGpu.of(backend).support;
      if (support != RasterizerSupport.supported) {
        markTestSkipped('support ${support.name}');
        return;
      }
    }
    final renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: backend,
    );
    try {
      await body(renderer);
    } finally {
      renderer.dispose();
    }
  });

  RasterizerScene scene(String svg, RasterizerBackend backend) =>
      RasterizerScene.fromSvg(
        utf8.encode(svg),
        backend: backend,
        maxSize: size.toDouble(),
      );

  /// Renders a frame of one run, which [add] fills, and returns the run.
  RasterizerRun render(
    RasterizerRenderer renderer,
    void Function(RasterizerRun run) add,
  ) {
    final frame = renderer.beginFrame(size, size);
    final run = frame.addRun();
    add(run);
    frame.render();
    return run;
  }

  // w is the smallest double above 0, so every corner but the origin
  // projects to infinity.
  backendTest(
    RasterizerBackend.mesh,
    'a square projected to infinity covers the viewport',
    (renderer) async {
      final square = scene(squareSvg, RasterizerBackend.mesh);
      final run = render(
        renderer,
        (run) => run.addProjective(square, 1, 0, 0, 1, 0, 0, 0, 0, 5e-324),
      );
      expect(
        run.parts.single.destination,
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      );
      square.dispose();
    },
  );

  // w = 0.01 x + 1. The square's right side, at x = 64, is 1.64 times as far
  // away as its left side, so it projects to x = 39, and spans y from 0 to
  // 39.
  for (final backend in [RasterizerBackend.mesh, RasterizerBackend.canvas]) {
    backendTest(backend, 'a square in perspective', (renderer) async {
      final square = scene(squareSvg, backend);
      final run = render(
        renderer,
        (run) => run.addProjective(square, 1, 0, 0, 1, 0, 0, 0.01, 0, 1),
      );
      if (backend == RasterizerBackend.mesh) {
        // The projected corners' bounds, with the renderer's margin, clipped
        // to the viewport.
        expect(
          run.parts.single.destination,
          const ui.Rect.fromLTWH(0, 0, 41, 64),
        );
      }
      final pixels = await readBack(run.draw);
      expectAt(pixels, 5, 32, red, 'by its near side');
      expectAt(pixels, 35, 20, red, 'by its far side');
      expectAt(pixels, 35, 50, clear, 'under its far side');
      expectAt(pixels, 45, 10, clear, 'past its far side');
      square.dispose();
    });
  }

  backendTest(RasterizerBackend.mesh, 'gradients interpolate in perspective', (
    renderer,
  ) async {
    final gradient = scene(gradientSvg, RasterizerBackend.mesh);
    final run = render(
      renderer,
      (run) => run.addProjective(gradient, 1, 0, 0, 1, 0, 0, 0.01, 0, 1),
    );
    // Pixel (30, 10)'s center, at x = 30.5, maps back to x = 30.5 / (1 -
    // 0.305) = 43.9 in the SVG, where the gradient is at t = 0.686.
    // Interpolated linearly on screen, it would be at x = 50 and t = 0.78.
    expectAt(await readBack(run.draw), 30, 10, [
      80,
      0,
      175,
      255,
    ], 'at t = 0.686');
    gradient.dispose();
  });

  backendTest(
    RasterizerBackend.mesh,
    "a target is the viewport where a corner is behind the eye; nothing's "
    'drawn where all are',
    (renderer) async {
      final square = scene(squareSvg, RasterizerBackend.mesh);
      // w = 1 - 0.02 x is 0 at x = 50.
      var run = render(
        renderer,
        (run) => run.addProjective(square, 1, 0, 0, 1, 0, 0, -0.02, 0, 1),
      );
      expect(
        run.parts.single.destination,
        const ui.Rect.fromLTWH(0, 0, 64, 64),
      );
      expectAt(await readBack(run.draw), 5, 5, red, 'in front');
      run = render(
        renderer,
        (run) => run.addProjective(square, 1, 0, 0, 1, 0, 0, 0, 0, -1),
      );
      expect(run.isEmpty, isTrue);
      expect(run.parts, isEmpty);
      square.dispose();
    },
  );

  for (final backend in RasterizerBackend.values) {
    backendTest(backend, 'a constant w divides the affine part', (
      renderer,
    ) async {
      final square = scene(squareSvg, backend);
      final divided = await readBack(
        render(
          renderer,
          (run) => run.addProjective(square, 1, 0, 0, 1, 16, 8, 0, 0, 2),
        ).draw,
      );
      final affine = await readBack(
        render(renderer, (run) => run.add(square, 0.5, 0, 0, 0.5, 8, 4)).draw,
      );
      // The canvas renderer may antialias a perspective transform otherwise
      // than an affine one, so only the pixels below are checked with it.
      if (backend != RasterizerBackend.canvas) {
        expect(divided, affine);
      }
      expectAt(divided, 20, 10, red, 'inside');
      expectAt(divided, 44, 10, clear, 'outside');
      square.dispose();
    });
  }

  backendTest(
    RasterizerBackend.gpu,
    'perspective throws, as the GPU renderer only draws affine transforms',
    (renderer) async {
      final square = scene(squareSvg, RasterizerBackend.gpu);
      final frame = renderer.beginFrame(size, size);
      expect(
        () =>
            frame.addRun().addProjective(square, 1, 0, 0, 1, 0, 0, 0.01, 0, 1),
        throwsArgumentError,
      );
      frame.render();
      square.dispose();
    },
  );
}
