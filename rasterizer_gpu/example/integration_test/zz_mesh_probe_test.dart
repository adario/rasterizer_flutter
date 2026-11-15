// A temporary probe for the mesh renderer's OpenGL ES self-test failing on
// Linux: it renders the self-test's scene as the self-test does, with 4x
// and 1x samples, through an affine and a projective transform, and prints
// each checked pixel, not only the first that fails, and each image as a
// base64 PNG. From rasterizer_gpu/example, run it on Wayland, then on X11:
//   flutter test integration_test/zz_mesh_probe_test.dart -d linux
//   GDK_BACKEND=x11 flutter test \
//     integration_test/zz_mesh_probe_test.dart -d linux
// and send both logs, with `flutter --version` and
// `eglinfo -B | grep -i "renderer\|version"`.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
// For the probe only: offscreen MSAA and the default color format.
// ignore: depend_on_referenced_packages
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The self-test's scene, checks and renderer are internal.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/atlas.dart' show parseMeshScene;
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/meshes.dart' show MeshRenderer;
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/self_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// The pixels the self-test checks, as in self_test.dart.
const _probes = [
  (x: 4, y: 4),
  (x: 20, y: 30),
  (x: 60, y: 30),
  (x: 80, y: 23),
  (x: 80, y: 70),
  (x: 80, y: 97),
  (x: 110, y: 50),
  (x: 130, y: 70),
  (x: 36, y: 100),
  (x: 36, y: 97),
  (x: 36, y: 112),
  (x: 36, y: 124),
  (x: 126, y: 128),
  (x: 126, y: 119),
  (x: 126, y: 108),
  (x: 150, y: 150),
  (x: 80, y: 120),
  (x: 80, y: 146),
  (x: 80, y: 139),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('mesh renderer probe', (tester) async {
    runApp(const SizedBox());
    await tester.pump();
    await SchedulerBinding.instance.endOfFrame;
    debugPrint(
      'PROBE support ${RasterizerGpu.support.name}, '
      'offscreen MSAA ${gpu.gpuContext.doesSupportOffscreenMSAA}, '
      'color format ${gpu.gpuContext.defaultColorFormat.name}',
    );
    final library = (await gpu.ShaderLibrary.fromAsset(
      RasterizerGpu.shaderBundle,
    ))!;
    final scene = parseMeshScene(
      Uint8List.fromList(selfTestSvg.codeUnits),
      selfTestSize.toDouble(),
    );
    for (final samples in [4, 1]) {
      final renderer = MeshRenderer(library, 1, samples);
      for (final projective in [false, true]) {
        await tester.runAsync(() => SchedulerBinding.instance.endOfFrame);
        final frame = renderer.beginFrame(selfTestSize, selfTestSize);
        final run = frame.addRun();
        if (projective) {
          run.addProjective(scene, 2, 0, 0, 2, 0, 0, 0, 0, 2);
        } else {
          run.add(scene, 1, 0, 0, 1, 0, 0);
        }
        frame.render();
        // Read back through a canvas, as the self-test does.
        final part = run.parts.first, image = part.image;
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImage(
          image,
          ui.Offset.zero,
          ui.Paint()..blendMode = ui.BlendMode.src,
        );
        final picture = recorder.endRecording();
        final readback = (await tester.runAsync(() async {
          final copy = await picture.toImage(image.width, image.height);
          final rgba = await copy.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final png = await copy.toByteData(format: ui.ImageByteFormat.png);
          copy.dispose();
          return (rgba: rgba!, png: png!);
        }))!;
        picture.dispose();
        final s = part.source, d = part.destination;
        final tag =
            '$samples× samples, ${projective ? 'projective' : 'affine'}';
        final bytes = Uint8List.sublistView(readback.rgba);
        final failure = checkSelfTest(
          bytes,
          4 * image.width,
          s.left.toInt(),
          s.top.toInt(),
          (
            left: d.left.toInt(),
            top: d.top.toInt(),
            width: d.width.toInt(),
            height: d.height.toInt(),
          ),
        );
        debugPrint(
          'PROBE $tag: ${failure ?? 'passed'}; image '
          '${image.width}x${image.height}, source $s, destination $d',
        );

        // The pixel at the scene's x, y, or 'outside' the part.
        String at(int x, int y) {
          if (x < d.left || x >= d.right || y < d.top || y >= d.bottom) {
            return 'outside';
          }
          final i =
              4 *
              ((y - d.top.toInt() + s.top.toInt()) * image.width +
                  x -
                  d.left.toInt() +
                  s.left.toInt());
          return '${bytes.sublist(i, i + 4)}';
        }

        final pixels = [for (final (:x, :y) in _probes) '$x,$y=${at(x, y)}'];
        debugPrint('PROBE $tag pixels: ${pixels.join(' ')}');
        debugPrint(
          'PROBE $tag PNG: ${base64Encode(readback.png.buffer.asUint8List())}',
        );
      }
      renderer.dispose();
    }
    scene.dispose();
  });
}
