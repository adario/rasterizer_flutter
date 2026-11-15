// Checks the GPU renderer's OpenGL ES format probe, in the app, wherever the
// GPU renderer can render:
//   flutter test integration_test/format_probe_test.dart -d <device>
//
// On OpenGL ES, as on an Android emulator built with
// IMPELLER_BACKEND=opengles, the first GPU renderer created runs the probe,
// and a failure switches the renderers to r16g16b16a16Float. Elsewhere, no
// renderer runs it, so the test runs it on its own, as it must pass there
// too. defer_test.dart checks that the renderers draw before the first frame.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The GPU renderer's entry types are internal.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'probe_scene.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  if (RasterizerGpu.support != RasterizerSupport.supported) {
    test(
      'no GPU renderer here',
      () {},
      skip: 'support ${RasterizerGpu.support.name}',
    );
    return;
  }

  final mesh = RasterizerGpu.of(RasterizerBackend.mesh);

  setUpAll(() => runApp(const SizedBox()));
  tearDownAll(() {
    RasterizerGpu.debugFailFormatProbe = {};
    RasterizerGpu.debugResetSupport();
  });

  test('the probe scene makes every kind of entry SVGs make', () async {
    final renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.gpu,
    ) as ra.AtlasRenderer;
    final scene = probeScene(backend: RasterizerBackend.gpu);
    final types = <ra.EntryType>{};
    renderer.debugFrameWritten = (_, frame) => types.addAll([
      for (final e in frame.entries)
        if (e.count > 0) e.type,
    ]);
    for (final curves in [true, false]) {
      final frame = renderer.beginFrame(
        selfTestSize,
        selfTestSize,
        curves: curves,
      );
      frame.addRun().add(scene, 1, 0, 0, 1, 0, 0);
      frame.render();
    }
    renderer.dispose();
    scene.dispose();
    expect(
      types,
      containsAll([
        ra.EntryType.opaques,
        ra.EntryType.instances,
        ra.EntryType.fastEdges,
        ra.EntryType.quadEdges,
        ra.EntryType.fastMolecules,
        ra.EntryType.quadMolecules,
      ]),
    );
  });

  test('the probe passes here, and fails when forced', () async {
    expect(await RasterizerGpu.debugProbeFormat(), isNull);
    RasterizerGpu.debugFailFormatProbe = {'r32Float'};
    try {
      expect(await RasterizerGpu.debugProbeFormat(), 'forced to fail');
    } finally {
      RasterizerGpu.debugFailFormatProbe = {};
    }
  });

  if (RasterizerGpu.openGles) {
    test('the first GPU renderer runs the probe, once, and it passes, '
        'accumulating in r32Float', () async {
      RasterizerGpu.debugResetSupport();
      expect(RasterizerGpu.debugFormatProbe, isNull);
      expect(RasterizerGpu.supportDetail, endsWith('not checked yet'));
      final renderer = await RasterizerRenderer.create(slots: 1);
      expect(renderer.backend, RasterizerBackend.gpu);
      final probe = RasterizerGpu.debugFormatProbe;
      expect(probe, isNotNull);
      expect(await probe, isNull);
      expect(
        RasterizerGpu.supportDetail,
        'OpenGL ES, accumulating in r32Float, checked',
      );
      final other = await RasterizerRenderer.create(slots: 1);
      expect(identical(RasterizerGpu.debugFormatProbe, probe), isTrue);
      final scene = probeScene();
      expect(await checkProbe(renderProbe(renderer, scene)), isNull);
      scene.dispose();
      other.dispose();
      renderer.dispose();
    });

    test('a failed probe makes the renderers accumulate in '
        'r16g16b16a16Float, and they draw right', () async {
      RasterizerGpu.debugResetSupport();
      RasterizerGpu.debugFailFormatProbe = {'r32Float'};
      try {
        final renderer = await RasterizerRenderer.create(slots: 1);
        expect(renderer.backend, RasterizerBackend.gpu);
        expect(await RasterizerGpu.debugFormatProbe, 'forced to fail');
        expect(
          RasterizerGpu.supportDetail,
          'OpenGL ES, accumulating in r16g16b16a16Float, as r32Float failed: '
          'forced to fail',
        );
        final scene = probeScene();
        expect(await checkProbe(renderProbe(renderer, scene)), isNull);
        scene.dispose();
        renderer.dispose();
      } finally {
        RasterizerGpu.debugFailFormatProbe = {};
        RasterizerGpu.debugResetSupport();
      }
    });

    test("the mesh renderer's detail says how its targets are sampled", () {
      expect(mesh.support, RasterizerSupport.supported);
      expect(
        mesh.supportDetail,
        anyOf('OpenGL ES, 4× multisampled', 'OpenGL ES, aliased'),
      );
    });

    test('without allowOpenGles, the GPU renderers are unsupported, and the '
        'canvas renderer draws', () async {
      RasterizerGpu.allowOpenGles = false;
      try {
        for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
          final state = RasterizerGpu.of(gpu);
          expect(state.support, RasterizerSupport.openGles);
          expect(state.backend, RasterizerBackend.canvas);
          expect(
            state.supportDetail,
            'OpenGL ES: set RasterizerGpu.allowOpenGles',
          );
          final renderer = await RasterizerRenderer.create(slots: 1, gpu: gpu);
          expect(renderer.backend, RasterizerBackend.canvas);
          renderer.dispose();
        }
      } finally {
        RasterizerGpu.allowOpenGles = true;
      }
    });
  } else {
    test('no renderer runs the probe on Metal and Vulkan', () async {
      RasterizerGpu.debugResetSupport();
      for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
        final renderer = await RasterizerRenderer.create(slots: 1, gpu: gpu);
        expect(renderer.backend, gpu);
        renderer.dispose();
        expect(RasterizerGpu.of(gpu).supportDetail, isNull);
      }
      expect(RasterizerGpu.debugFormatProbe, isNull);
    });
  }
}
