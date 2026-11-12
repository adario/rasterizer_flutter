// Tests a deferred first frame on OpenGL ES, in the app:
//   flutter test integration_test/defer_test.dart -d <device>
//
// On OpenGL ES, as on the Android emulator with the app built with
// IMPELLER_BACKEND=opengles, RasterizerGpu.initialize waits for the app's
// first rasterized frame. It waits for as long as the app defers that frame,
// as a splash screen does, even past its 10 s timeout. Scenes and renderers
// draw with the canvas renderer meanwhile, then switch to the GPU renderer.
// The test has a file of its own, as a process rasterizes its first frame
// once. Elsewhere, nothing waits, and the test is skipped.
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

void main() {
  // Fully live, so that runApp's frame is drawn once it's allowed.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  test(
    'with the first frame deferred past 10 s, scenes switch to the GPU '
    'renderer once it comes',
    () async {
      expect(
        binding.firstFrameRasterized,
        isFalse,
        reason: 'a frame was rasterized before the test',
      );
      final bytes = await rootBundle.load('assets/tiger/tiger.svg');
      binding.deferFirstFrame();
      runApp(const SizedBox());
      RasterizerGpu.allowOpenGles = true;
      final scene = RasterizerScene.fromSvg(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final renderer = await RasterizerRenderer.create(slots: 3);
      expect(renderer.backend, RasterizerBackend.canvas);
      await Future<void>.delayed(const Duration(seconds: 15));
      expect(binding.firstFrameRasterized, isFalse);
      expect(RasterizerGpu.initialized, isFalse);
      expect(scene.backend, RasterizerBackend.canvas);

      binding.allowFirstFrame();
      var settled = false;
      RasterizerGpu.settledBackend.then((_) => settled = true);
      for (var frames = 0; !settled; frames++) {
        final frame = renderer.beginFrame(64, 64);
        frame.addRun().add(scene, 0.1, 0, 0, 0.1, 0, 0);
        frame.render();
        await SchedulerBinding.instance.endOfFrame;
        if (frames > 3000) {
          fail('not settled after 3000 frames');
        }
      }
      expect(
        await RasterizerGpu.settledBackend,
        RasterizerBackend.gpu,
        reason: RasterizerGpu.supportDetail,
      );
      expect(scene.backend, RasterizerBackend.gpu);
      renderer.dispose();
      scene.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: RasterizerGpu.openGles
        ? false
        : 'not on OpenGL ES: support ${RasterizerGpu.support.name}',
  );
}
