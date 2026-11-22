// Checks the GPU renderer's OpenGL ES format probe, in the app, wherever the
// GPU renderer can render:
//   flutter test integration_test/format_probe_test.dart -d <device>
//
// On OpenGL ES, as on an Android emulator built with
// IMPELLER_BACKEND=opengles, the first GPU renderer created runs the probe,
// and a failure switches the renderers to r16g16b16a16Float, which it then
// checks too. There, support also checks that textures can be 4096 pixels
// wide, and a renderer whose pipelines don't compile in time falls back to
// the canvas renderer. Elsewhere, no renderer runs the probe, so the test runs
// it on its own, as it must pass there too. defer_test.dart checks that the
// renderers draw before the first frame.
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
      final frame = renderer.beginFrame(probeSize, probeSize, curves: curves);
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
      expect(
        await RasterizerGpu.debugProbeFormat(),
        'r32Float: forced to fail',
      );
      RasterizerGpu.debugFailFormatProbe = {'r32Float', 'r16g16b16a16Float'};
      expect(
        await RasterizerGpu.debugProbeFormat(),
        'r32Float: forced to fail; r16g16b16a16Float: forced to fail',
      );
      RasterizerGpu.debugFailFormatProbe = {'r32Float pixels'};
      expect(
        await RasterizerGpu.debugProbeFormat(),
        'r32Float: forced to fail',
      );
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
        expect(
          await RasterizerGpu.debugFormatProbe,
          'r32Float: forced to fail',
        );
        expect(
          RasterizerGpu.supportDetail,
          'OpenGL ES, accumulating in r16g16b16a16Float, as r32Float failed: '
          'forced to fail, checked',
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

    test('a renderer made before the probe fails on its pixels switches to '
        'r16g16b16a16Float at its next frame, and draws right', () async {
      RasterizerGpu.debugResetSupport();
      RasterizerGpu.debugFailFormatProbe = {'r32Float pixels'};
      try {
        final renderer =
            await RasterizerRenderer.create(slots: 1) as ra.AtlasRenderer;
        final scene = probeScene();
        // The probe reads its pixels back after the app's next frame, so it
        // hasn't failed yet.
        expect(RasterizerGpu.supportDetail, endsWith('not checked yet'));
        expect(await checkProbe(renderProbe(renderer, scene)), isNull);
        expect(renderer.debugAccumulationFormat?.name, 'r32Float');
        expect(
          await RasterizerGpu.debugFormatProbe,
          'r32Float: forced to fail',
        );
        expect(
          RasterizerGpu.supportDetail,
          'OpenGL ES, accumulating in r16g16b16a16Float, as r32Float failed: '
          'forced to fail, checked',
        );
        expect(renderer.debugAccumulationFormat?.name, 'r32Float');
        expect(await checkProbe(renderProbe(renderer, scene)), isNull);
        expect(renderer.debugAccumulationFormat?.name, 'r16g16b16a16Float');
        scene.dispose();
        renderer.dispose();
      } finally {
        RasterizerGpu.debugFailFormatProbe = {};
        RasterizerGpu.debugResetSupport();
      }
    });

    test(
      'a probe forgotten before it fails leaves the format as it is',
      () async {
        RasterizerGpu.debugResetSupport();
        RasterizerGpu.debugFailFormatProbe = {'r32Float pixels'};
        try {
          final renderer = await RasterizerRenderer.create(slots: 1);
          final probe = RasterizerGpu.debugFormatProbe;
          RasterizerGpu.debugResetSupport();
          expect(await probe, 'r32Float: forced to fail');
          expect(
            RasterizerGpu.supportDetail,
            'OpenGL ES, accumulating in r32Float, not checked yet',
          );
          renderer.dispose();
        } finally {
          RasterizerGpu.debugFailFormatProbe = {};
          RasterizerGpu.debugResetSupport();
        }
      },
    );

    test('where both formats fail, the GPU renderer still draws, and its '
        'detail says so', () async {
      RasterizerGpu.debugResetSupport();
      RasterizerGpu.debugFailFormatProbe = {'r32Float', 'r16g16b16a16Float'};
      try {
        final renderer = await RasterizerRenderer.create(slots: 1);
        expect(renderer.backend, RasterizerBackend.gpu);
        expect(
          await RasterizerGpu.debugFormatProbe,
          'r32Float: forced to fail; r16g16b16a16Float: forced to fail',
        );
        expect(
          RasterizerGpu.supportDetail,
          'OpenGL ES, accumulating in r16g16b16a16Float, as r32Float failed: '
          'forced to fail, and r16g16b16a16Float failed too: forced to fail',
        );
        renderer.dispose();
      } finally {
        RasterizerGpu.debugFailFormatProbe = {};
        RasterizerGpu.debugResetSupport();
      }
    });

    test('where textures are too small, the GPU renderers are unsupported, '
        'and the canvas renderer draws', () async {
      // Wider than any device allows, so Flutter GPU refuses it.
      RasterizerGpu.debugCheckedTextureWidth = 1 << 20;
      RasterizerGpu.debugResetSupport();
      try {
        for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
          final state = RasterizerGpu.of(gpu);
          expect(state.support, RasterizerSupport.smallTextures);
          expect(state.backend, RasterizerBackend.canvas);
          expect(state.supportDetail, isNotNull);
          final renderer = await RasterizerRenderer.create(slots: 1, gpu: gpu);
          expect(renderer.backend, RasterizerBackend.canvas);
          renderer.dispose();
        }
        expect(RasterizerGpu.openGles, isTrue);
      } finally {
        RasterizerGpu.debugCheckedTextureWidth = 4096;
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

    test("where a renderer's pipelines don't compile in time, its support "
        'times out, and the canvas renderer draws', () async {
      // The GPU runs the warm-up's draws after the timer fires.
      RasterizerGpu.warmUpTimeout = Duration.zero;
      try {
        for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
          final renderer = await RasterizerRenderer.create(slots: 1, gpu: gpu);
          expect(renderer.backend, RasterizerBackend.canvas);
          renderer.dispose();
          final state = RasterizerGpu.of(gpu);
          expect(state.support, RasterizerSupport.warmUpTimeout);
          expect(state.backend, RasterizerBackend.canvas);
          expect(
            state.supportDetail,
            "OpenGL ES: the pipelines didn't compile within 0 ms",
          );
        }
      } finally {
        RasterizerGpu.warmUpTimeout = const Duration(seconds: 5);
        RasterizerGpu.debugResetSupport();
      }
      expect(mesh.support, RasterizerSupport.supported);
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
