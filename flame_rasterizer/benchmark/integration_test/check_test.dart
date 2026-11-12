// Checks the benchmark's game against the same frame composed directly, in
// the app:
//   flutter test integration_test/check_test.dart \
//     -d <macos|iOS udid|emulator-5554> \
//     [--dart-define=BACKEND=atlas|canvas]
//
// This is the benchmark's correctness check as a test. At each of 4 times,
// Flame draws the game's frame with flame_rasterizer. The check composes the
// same frame with rasterizer_gpu's API. The two must match, and the game
// must draw the expected runs. A run is a contiguous group of vector
// components that draws as one image.
//
// Both draw with demoGpu: the mesh renderer, or the GPU renderer with
// BACKEND=atlas. BACKEND=canvas forces the canvas renderer, which also draws
// wherever the GPU renderers aren't supported. On the Android emulator, the
// test runs on Vulkan, or on OpenGL ES in an app built with
// IMPELLER_BACKEND=opengles.
import 'dart:async';

import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_benchmark/check.dart';
import 'package:flame_rasterizer_benchmark/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.forceCanvas =
      const String.fromEnvironment('BACKEND') == 'canvas';
  RasterizerGpu.allowOpenGles = true;

  // The game's time sets the camera's zoom: here 1.1, 1.64, 1.5 and 0.51
  // times the zoom that fits the whole world in the view.
  for (final time in [0.0, 3.7, 8.0, 15.0]) {
    testWidgets(
      'the Flame frame at time $time matches the one composed directly',
      (tester) async {
        final result = Completer<(bool, String)>();
        await tester.pumpWidget(
          CheckPage(
            time: time,
            onResult: ({required pass, required line}) =>
                result.complete((pass, line)),
          ),
        );
        final (pass, line) =
            await tester.runAsync(
              () => result.future.timeout(const Duration(seconds: 60)),
            ) ??
            (false, 'no result');
        final gpu = RasterizerGpu.of(demoGpu);
        // ignore: avoid_print
        print(
          '  $line; ${demoGpu.name} support ${gpu.support.name}: '
          '${gpu.supportDetail}, backend ${gpu.backend.name}',
        );
        // On the web, prints go to the browser's console, so the line also
        // goes to flutter drive's response data.
        (binding.reportData ??= {})['$time'] = line;
        expect(pass, isTrue, reason: line);
      },
    );
  }
}
