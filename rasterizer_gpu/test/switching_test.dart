// Checks the scenes that switch from the canvas renderer to a GPU renderer on
// OpenGL ES, without a GPU. From this package's folder:
//   flutter test test/switching_test.dart
//
// The canvas renderer draws them until the switch. The core parses each for
// the GPU renderer it switches to, the atlas or the mesh one. A scene the core
// can't parse stays with the canvas renderer. Once settled on the canvas
// renderer, scenes drop their bytes. Each GPU renderer's scenes switch or
// settle on their own. The switch itself, with renderers, is checked by
// example/integration_test/switch_test.dart.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/atlas.dart' show maxPageSize;
import 'package:rasterizer_gpu/src/canvas_renderer.dart';
import 'package:rasterizer_gpu/src/meshes.dart' show MeshScene;
import 'package:rasterizer_gpu/src/paths/scene_paths.dart';
import 'package:rasterizer_gpu/src/switching.dart';

void main() {
  final bytes = File('example/assets/tiger/tiger.svg').readAsBytesSync();

  test(
    'a switching scene draws with the canvas renderer, as its canvas parse',
    () {
      final scene = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null),
          canvas = CanvasScene(bytes);
      expect(scene.backend, RasterizerBackend.canvas);
      expect(scene.bounds, canvas.bounds);
      expect(scene.viewBox, canvas.viewBox);
      expect(scene.pathCount, canvas.pathCount);
      expect(resolveScene(scene, RasterizerBackend.canvas), isA<CanvasScene>());
      final frame = CanvasRenderer(1).beginFrame(100, 100);
      final run = frame.addRun()..add(scene, 1, 0, 0, 1, 0, 0);
      frame.render();
      expect(run.isEmpty, isFalse);
      scene.dispose();
    },
  );

  test('it parses for the GPU renderer once, whose rectangles match', () {
    final scene = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null);
    final gpu = resolveScene(scene, RasterizerBackend.gpu);
    expect(gpu.backend, RasterizerBackend.gpu);
    expect(identical(resolveScene(scene, RasterizerBackend.gpu), gpu), isTrue);
    expect(gpu.viewBox, scene.viewBox);
    for (final (a, b) in [
      (gpu.bounds.left, scene.bounds.left),
      (gpu.bounds.top, scene.bounds.top),
      (gpu.bounds.right, scene.bounds.right),
      (gpu.bounds.bottom, scene.bounds.bottom),
    ]) {
      expect(a, closeTo(b, 0.01));
    }
    scene.dispose();
  });

  test('settled on the canvas renderer, it drops its bytes, so a GPU renderer '
      'can\'t draw it', () {
    final scene = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null);
    settleOnCanvas(RasterizerBackend.gpu);
    expect(
      () => resolveScene(scene, RasterizerBackend.gpu),
      throwsArgumentError,
    );
    expect(resolveScene(scene, RasterizerBackend.canvas), isA<CanvasScene>());
    scene.dispose();
  });

  test('one switching to the mesh renderer parses a mesh scene for it, which '
      'the GPU renderer can\'t draw, nor the mesh renderer the other\'s', () {
    final scene = SwitchingScene.fromSvg(bytes, RasterizerBackend.mesh, 512);
    expect(scene.gpu, RasterizerBackend.mesh);
    final mesh = resolveScene(scene, RasterizerBackend.mesh);
    expect(mesh.backend, RasterizerBackend.mesh);
    expect(
      identical(resolveScene(scene, RasterizerBackend.mesh), mesh),
      isTrue,
    );
    expect(
      () => resolveScene(scene, RasterizerBackend.gpu),
      throwsArgumentError,
    );
    final gpu = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null);
    expect(
      () => resolveScene(gpu, RasterizerBackend.mesh),
      throwsArgumentError,
    );
    scene.dispose();
    gpu.dispose();
  });

  test('each GPU renderer\'s switching scenes settle on their own', () {
    final gpu = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null),
        mesh = SwitchingScene.fromSvg(bytes, RasterizerBackend.mesh, 512);
    settleOnCanvas(RasterizerBackend.gpu);
    expect(() => resolveScene(gpu, RasterizerBackend.gpu), throwsArgumentError);
    expect(resolveScene(mesh, RasterizerBackend.mesh), isA<MeshScene>());
    settleOnCanvas(RasterizerBackend.mesh);
    gpu.dispose();
    mesh.dispose();
  });

  test("one the core can't parse at the switch stays with the canvas renderer, "
      "alone, and a GPU renderer's run throws why", () async {
    final good = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null),
        bad = SwitchingScene(
          CanvasScene(bytes),
          RasterizerBackend.gpu,
          () => throw ArgumentError('Not parseable SVG data'),
        );
    var flipped = false;
    await switchToGpu(RasterizerBackend.gpu, () => flipped = true);
    expect(flipped, isTrue);
    expect(good.backend, RasterizerBackend.gpu);
    expect(bad.backend, RasterizerBackend.canvas);
    expect(resolveScene(bad, RasterizerBackend.canvas), isA<CanvasScene>());
    expect(
      () => resolveScene(bad, RasterizerBackend.gpu),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'Not parseable SVG data',
        ),
      ),
    );
    good.dispose();
    bad.dispose();
  });

  test(
    "its bounds are the canvas renderer's until the switch, then the GPU "
    "renderer's, such as a mesh scene's, which reach its glow's halos",
    () async {
      final line = ui.Path()
        ..moveTo(10, 10)
        ..lineTo(90, 10);
      final stroke = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 4;
      final scene = SwitchingScene.fromPaths(
        ScenePaths([(line, stroke)], glow: const RasterizerGlow(6)),
        RasterizerBackend.mesh,
        512,
      );
      final canvas = scene.bounds;
      await switchToGpu(RasterizerBackend.mesh, () {});
      expect(scene.backend, RasterizerBackend.mesh);
      final mesh = resolveScene(scene, RasterizerBackend.mesh).bounds;
      expect(scene.bounds, mesh);
      expect(mesh.height, greaterThan(canvas.height));
      scene.dispose();
    },
  );

  test('disposed, it can\'t be drawn', () {
    final scene = SwitchingScene.fromSvg(bytes, RasterizerBackend.gpu, null)
      ..dispose();
    expect(
      () => resolveScene(scene, RasterizerBackend.canvas),
      throwsStateError,
    );
  });

  test('a switching renderer takes viewports up to the GPU renderer\'s '
      'limit, on canvas too', () {
    final renderer = SwitchingRenderer(1, RasterizerBackend.gpu, 1);
    expect(renderer.backend, RasterizerBackend.canvas);
    expect(() => renderer.beginFrame(maxPageSize + 1, 10), throwsArgumentError);
    expect(() => renderer.beginFrame(10, maxPageSize + 1), throwsArgumentError);
    expect(renderer.beginFrame(maxPageSize, 10).width, maxPageSize);
    renderer.dispose();
  });
}
