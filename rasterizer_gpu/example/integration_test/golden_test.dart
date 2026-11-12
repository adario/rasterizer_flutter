// Runs the golden tests in the app, where rasterizer_gpu renders as in apps:
// on macOS, an iOS Simulator or device, or the Android emulator.
//   flutter test integration_test/golden_test.dart -d <device> \
//     [--dart-define=UPDATE_GOLDENS=true]
// They don't run in flutter_tester. On macOS, its Impeller renders through
// Metal too, but its antialiasing differs slightly from the app's, and the
// app's is what matched the original renderer. On iOS, from a clean checkout,
// build the app once first (flutter build ios): flutter test checks the
// assets before the build hook has written the shader bundle.
//
// The goldens are the app's goldens/<platform>/ assets (see goldenSet). The
// tests write failing renders and their diffs, or every render with
// UPDATE_GOLDENS, to the app's temporary folder, and tool/pull_goldens.py
// copies them out. On iOS and Android, run with --no-uninstall so that they
// survive the run. GOLDEN_RECORD=true also writes each frame's atlas pages,
// core frames and lists there. In tool/linux's container, whose runs don't
// keep /tmp, create a folder in build/ and set TMPDIR to it, e.g.
//   python3 -I tool/linux/linux.py run -C rasterizer_gpu/example \
//     env TMPDIR=/work/rasterizer_gpu/example/build/tmp \
//     flutter test integration_test/golden_test.dart -d linux \
//     --dart-define=UPDATE_GOLDENS=true
// and copy the images out with `linux.py pull
// rasterizer_gpu/example/build/tmp/goldens_rasterizer_gpu_example`.
//
// The tests cover every renderer, the GPU and mesh ones only where they're
// supported. BACKEND=gpu, BACKEND=mesh or BACKEND=canvas tests only that one.
// The canvas renderer's renders are checked against the GPU goldens, with
// their own tolerance, and never written as goldens. The mesh renderer has
// its own goldens, mesh_<name>.png, and its renders are checked against the
// GPU goldens too, with the canvas renderer's tolerance. On OpenGL ES, the
// GPU and mesh renderers are allowed, and tested if their self-tests pass:
// build the Android app with IMPELLER_BACKEND=opengles for that.
//
// On the web, with the chrome device of the repository's tool/device_tests.py,
// only the canvas renderer draws, checked against the macos goldens. The log
// lines and failing images go to flutter drive's response data, which the
// tool saves to the repository's build/test_logs/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart'
    show LiveTestWidgetsFlutterBindingFramePolicy, setUpAll;
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu_example/goldens.dart';

import 'golden_tests.dart';

Future<void> main() async {
  // As in apps, initialize runs after runApp. On OpenGL ES, it waits for a
  // rasterized frame, and the binding draws frames unasked only when fully
  // live.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;
  runApp(const SizedBox());
  // On the web, only the canvas renderer draws, so the tests are known
  // without initialize, which then runs before them.
  if (kIsWeb) {
    setUpAll(RasterizerGpu.initialize);
  } else {
    await RasterizerGpu.initialize();
    await RasterizerGpu.of(RasterizerBackend.mesh).initialize();
  }
  // Looks the report up as the tests run, in case the binding's data is
  // replaced.
  Map<String, dynamic> report(String key, Object Function() empty) =>
      ((binding.reportData ??= {})[key] ??= empty()) as Map<String, dynamic>;
  final out = kIsWeb ? '' : deviceOutputDir();
  // Deletes the last run's images, so that tool/pull_goldens.py copies only
  // this run's.
  if (!kIsWeb && Directory(out).existsSync()) {
    Directory(out).deleteSync(recursive: true);
  }
  defineGoldenTests(
    golden: (name) async {
      try {
        final data = await rootBundle.load('goldens/$goldenSet/$name.png');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        // No golden of that name.
        return null;
      }
    },
    write: (image, {required asGolden}) {
      final dir = asGolden ? goldenSet : 'failures';
      if (kIsWeb) {
        report('images', () => <String, dynamic>{})['$dir/${image.name}.png'] =
            base64.encode(image.toPng());
        return;
      }
      Directory('$out/$dir').createSync(recursive: true);
      File('$out/$dir/${image.name}.png').writeAsBytesSync(image.toPng());
    },
    update: const bool.fromEnvironment('UPDATE_GOLDENS'),
    recordDir: const bool.fromEnvironment('GOLDEN_RECORD')
        ? '$out/record'
        : null,
    backends: switch (const String.fromEnvironment('BACKEND')) {
      '' => null,
      final name => [RasterizerBackend.values.byName(name)],
    },
    log: (line) {
      // ignore: avoid_print
      print('  $line');
      final lines = report('lines', () => <String, dynamic>{});
      lines['${lines.length}'.padLeft(3, '0')] = line;
    },
  );
}
