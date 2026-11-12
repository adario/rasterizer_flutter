// Checks the GPU renderer that scenes and renderers pick, their `gpu`, when
// they're made without a backend. Runs without a GPU. From this package's
// folder:
//   flutter test test/gpu_choice_test.dart
//
// Each GPU renderer has its own support and state. Without a GPU, scenes and
// renderers made for either one draw with the canvas renderer. The mesh
// renderer needs a maximum size, and 1 or 4 samples, even when it isn't
// picked. Mesh scenes are made without a GPU, which they need only once drawn.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

final _bytes = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">'
    '<rect x="4" y="4" width="20" height="20" fill="red"/>'
    '<circle cx="24" cy="24" r="12" fill="none" stroke="blue" '
    'stroke-width="4"/></svg>',
  ),
);

void main() {
  test('each GPU renderer has its own state; the canvas renderer has none', () {
    final gpu = RasterizerGpu.of(RasterizerBackend.gpu),
        mesh = RasterizerGpu.of(RasterizerBackend.mesh);
    expect(gpu.gpu, RasterizerBackend.gpu);
    expect(mesh.gpu, RasterizerBackend.mesh);
    expect(RasterizerGpu.support, gpu.support);
    expect(RasterizerGpu.backend, gpu.backend);
    expect(
      () => RasterizerGpu.of(RasterizerBackend.canvas),
      throwsArgumentError,
    );
  });

  test('without a GPU, scenes and renderers made for either GPU renderer are '
      'canvas ones', () async {
    final mesh = RasterizerGpu.of(RasterizerBackend.mesh);
    expect(mesh.support, isNot(RasterizerSupport.supported));
    expect(mesh.backend, RasterizerBackend.canvas);
    final scene = RasterizerScene.fromSvg(
      _bytes,
      gpu: RasterizerBackend.mesh,
      maxSize: 100,
    );
    expect(scene.backend, RasterizerBackend.canvas);
    final renderer = await RasterizerRenderer.create(
      gpu: RasterizerBackend.mesh,
    );
    expect(renderer.backend, RasterizerBackend.canvas);
    await expectLater(
      RasterizerRenderer.create(backend: RasterizerBackend.mesh),
      throwsUnsupportedError,
    );
    renderer.dispose();
    scene.dispose();
  });

  test("the mesh renderer's samples are 1 or 4, even where it isn't the one "
      'chosen', () async {
    for (final samples in [0, 2, 8]) {
      await expectLater(
        RasterizerRenderer.create(
          gpu: RasterizerBackend.mesh,
          meshSamples: samples,
        ),
        throwsArgumentError,
      );
    }
    for (final samples in [1, 4]) {
      (await RasterizerRenderer.create(
        gpu: RasterizerBackend.mesh,
        meshSamples: samples,
      )).dispose();
    }
  });

  test("the mesh renderer needs a maximum size, even where it isn't the one "
      'chosen', () {
    expect(
      () => RasterizerScene.fromSvg(_bytes, gpu: RasterizerBackend.mesh),
      throwsArgumentError,
    );
    expect(
      () => RasterizerScene.fromSvg(_bytes, backend: RasterizerBackend.mesh),
      throwsArgumentError,
    );
    RasterizerScene.fromSvg(_bytes).dispose();
  });

  test('a mesh scene is made without a GPU, with its bounds and counts', () {
    final scene = RasterizerScene.fromSvg(
      _bytes,
      backend: RasterizerBackend.mesh,
      maxSize: 100,
    );
    expect(scene.backend, RasterizerBackend.mesh);
    expect(scene.viewBox, const Rect.fromLTWH(0, 0, 40, 40));
    for (final (actual, expected) in [
      (scene.bounds.left, 4),
      (scene.bounds.top, 4),
      (scene.bounds.right, 38),
      (scene.bounds.bottom, 38),
    ]) {
      expect(actual, closeTo(expected, 0.1));
    }
    expect(scene.pathCount, 2);
    scene.dispose();
  });
}
