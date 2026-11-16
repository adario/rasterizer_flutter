// Tests the GPU renderers before the app's first frame, in the app:
//   flutter test integration_test/defer_test.dart -d <device>
//
// With the first frame deferred past 10 s, as a splash screen can, each GPU
// renderer is created and renders before it, then its frames are read back
// once the first frame is allowed. On OpenGL ES, as on the Android emulator
// with the app built with IMPELLER_BACKEND=opengles, the renderers draw from
// their first frame, with no frame of the app's to wait for. The test has a
// file of its own, as a process rasterizes its first frame once.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'probe_scene.dart';

void main() {
  // Fully live, so that runApp's frame is drawn once it's allowed.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  test(
    'with the first frame deferred past 10 s, the GPU renderers draw right '
    'before it',
    () async {
      expect(
        binding.firstFrameRasterized,
        isFalse,
        reason: 'a frame was rasterized before the test',
      );
      binding.deferFirstFrame();
      runApp(const SizedBox());
      await Future<void>.delayed(const Duration(seconds: 15));
      final runs = <RasterizerBackend, RasterizerRun>{};
      final disposers = <void Function()>[];
      for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh]) {
        final renderer = await RasterizerRenderer.create(slots: 1, gpu: gpu);
        expect(renderer.backend, gpu);
        final scene = probeScene(gpu: gpu);
        disposers.addAll([renderer.dispose, scene.dispose]);
        runs[gpu] = renderProbe(renderer, scene);
      }
      expect(binding.firstFrameRasterized, isFalse);

      binding.allowFirstFrame();
      await binding.waitUntilFirstFrameRasterized;
      for (final MapEntry(key: gpu, value: run) in runs.entries) {
        expect(await checkProbe(run), isNull, reason: gpu.name);
      }
      for (final dispose in disposers) {
        dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: RasterizerGpu.support == RasterizerSupport.supported
        ? false
        : 'support ${RasterizerGpu.support.name}',
  );
}
