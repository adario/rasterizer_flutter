// Checks canvas-first startup on OpenGL ES, in the app:
//   flutter test integration_test/switch_test.dart -d <device>
//
// On OpenGL ES, as on an Android emulator built with
// IMPELLER_BACKEND=opengles, scenes and renderers made without a backend
// draw with the canvas renderer at first. They switch to the GPU renderer
// once its self-test passes, or stay if it fails. Made with
// `gpu: RasterizerBackend.mesh`, they switch to the mesh renderer once its
// own self-test passes. Scenes of plain paths switch too. In the
// background, the self-test waits.
//
// Elsewhere, they're plain, non-switching ones from the start: the GPU
// renderer's where it's supported, else the canvas renderer's, as on Skia
// (--no-enable-impeller). defer_test.dart checks a deferred first frame.
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/switching.dart';
import 'package:rasterizer_gpu_example/goldens.dart';
import 'package:rasterizer_gpu_example/scenes.dart';

const size = 256;

/// Creates a scene of the golden tests' paths for [backend], or, without
/// one, a scene that switches to [gpu].
RasterizerScene pathScene({
  RasterizerBackend? backend,
  RasterizerBackend gpu = RasterizerBackend.gpu,
}) => RasterizerScene.fromPaths(
  goldenPaths(),
  backend: backend,
  gpu: gpu,
  maxSize: size.toDouble(),
);

void main() {
  // Fully live, so that runApp's frame is drawn, and the frames that the
  // tests wait for.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Count attempts, as profile and release builds do, so that the probation
  // runs after each switch: the first GPU frames, during which a crash still
  // counts as a failed attempt.
  RasterizerGpu.debugCountAttempts = true;

  late Uint8List tiger;
  setUpAll(() async {
    runApp(const SizedBox());
    final bytes = await rootBundle.load('assets/tiger/tiger.svg');
    tiger = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  });

  /// Renders a frame of [scenes], each fitted to [size] px, with [renderer],
  /// and returns its only run.
  RasterizerRun render(
    RasterizerRenderer renderer,
    List<RasterizerScene> scenes,
  ) {
    final frame = renderer.beginFrame(size, size);
    final run = frame.addRun();
    for (final scene in scenes) {
      final b = scene.viewBox,
          s = size / (b.width > b.height ? b.width : b.height);
      run.add(scene, s, 0, 0, s, -b.left * s, -b.top * s);
    }
    frame.render();
    return run;
  }

  /// Renders [scenes] with [renderer] each frame, until [gpu]'s backend has
  /// settled.
  ///
  /// Returns the backends that it drew with, and the times between frames
  /// over 50 ms, by frame. [during] makes another scene a few frames in,
  /// while the self-test runs.
  Future<(List<RasterizerBackend>, Map<int, int>)> renderUntilSettled(
    RasterizerRenderer renderer,
    List<RasterizerScene> scenes, {
    RasterizerScene Function()? during,
    RasterizerBackend gpu = RasterizerBackend.gpu,
  }) async {
    var settled = false;
    RasterizerGpu.of(gpu).settledBackend.then((_) => settled = true);
    final backends = <RasterizerBackend>[];
    final watch = Stopwatch()..start();
    final long = <int, int>{};
    while (!settled) {
      if (backends.length == 3 && during != null) {
        scenes = [...scenes, during()];
      }
      render(renderer, scenes);
      backends.add(renderer.backend);
      await SchedulerBinding.instance.endOfFrame;
      if (watch.elapsedMilliseconds > 50) {
        long[backends.length] = watch.elapsedMilliseconds;
      }
      watch.reset();
      if (backends.length > 3000) {
        fail('not settled after 3000 frames');
      }
    }
    return (backends, long);
  }

  if (!RasterizerGpu.openGles) {
    test(
      'scenes and renderers made without a backend are plain ones',
      () async {
        RasterizerGpu.allowOpenGles = true;
        expect(await RasterizerGpu.settledBackend, RasterizerGpu.backend);
        final scene = RasterizerScene.fromSvg(tiger),
            paths = pathScene(),
            renderer = await RasterizerRenderer.create(slots: 1);
        expect(scene, isNot(isA<SwitchingScene>()));
        expect(paths, isNot(isA<SwitchingScene>()));
        expect(paths.backend, RasterizerGpu.backend);
        expect(renderer, isNot(isA<SwitchingRenderer>()));
        expect(render(renderer, [scene, paths]).isEmpty, isFalse);
        renderer.dispose();
        scene.dispose();
        paths.dispose();
      },
    );
    return;
  }

  tearDownAll(() {
    RasterizerGpu.debugFailSelfTest = {};
    RasterizerGpu.debugResetSupport();
    RasterizerGpu.forgetSelfTest();
    RasterizerGpu.of(RasterizerBackend.mesh).forgetSelfTest();
  });

  test('scenes and renderers switch to the GPU renderer once the self-test '
      'passes', () async {
    RasterizerGpu.debugResetSupport();
    RasterizerGpu.forgetSelfTest();
    RasterizerGpu.allowOpenGles = true;
    final scene = RasterizerScene.fromSvg(tiger),
        paths = pathScene(),
        renderer = await RasterizerRenderer.create(slots: 3);
    expect(scene.backend, RasterizerBackend.canvas);
    expect(paths, isA<SwitchingScene>());
    expect(renderer.backend, RasterizerBackend.canvas);
    late RasterizerScene madeDuring;
    final (backends, long) = await renderUntilSettled(renderer, [
      scene,
      paths,
    ], during: () => madeDuring = RasterizerScene.fromSvg(tiger));
    // ignore: avoid_print
    print(
      '  ${backends.length} frames with the canvas renderer until it settled; '
      'times between frames over 50 ms, by frame: $long; '
      '${RasterizerGpu.supportDetail}',
    );
    expect(await RasterizerGpu.settledBackend, RasterizerBackend.gpu);
    expect(backends, everyElement(RasterizerBackend.canvas));
    expect(scene.backend, RasterizerBackend.gpu);
    expect(madeDuring.backend, RasterizerBackend.gpu);
    expect(paths.backend, RasterizerBackend.gpu);

    // The renderer switches at its next frame, which must match a plain GPU
    // renderer's frame of plain GPU scenes.
    final run = render(renderer, [scene, madeDuring, paths]);
    expect(renderer.backend, RasterizerBackend.gpu);
    final plainScene = RasterizerScene.fromSvg(
      tiger,
      backend: RasterizerBackend.gpu,
    );
    final plainPaths = pathScene(backend: RasterizerBackend.gpu);
    final plain = await RasterizerRenderer.create(
      slots: 3,
      backend: RasterizerBackend.gpu,
    );
    final plainRun = render(plain, [plainScene, plainScene, plainPaths]);
    final part = run.parts.single, plainPart = plainRun.parts.single;
    final a = await readRgba(part.image), b = await readRgba(plainPart.image);
    expect(part.source, plainPart.source);
    final s = part.source, w = part.image.width;
    var differing = 0;
    for (var y = s.top.toInt(); y < s.bottom.toInt(); y++) {
      for (
        var x = 4 * (y * w + s.left.toInt());
        x < 4 * (y * w + s.right.toInt());
        x++
      ) {
        if (a!.getUint8(x) != b!.getUint8(x)) {
          differing++;
        }
      }
    }
    expect(
      differing,
      0,
      reason:
          'the switched renderer\'s frame differs from a plain GPU renderer\'s',
    );

    // Scenes made now are plain GPU ones.
    expect(RasterizerScene.fromSvg(tiger), isNot(isA<SwitchingScene>()));
    expect(pathScene(), isNot(isA<SwitchingScene>()));
    for (final r in [renderer, plain]) {
      r.dispose();
    }
    for (final s in [scene, madeDuring, paths, plainScene, plainPaths]) {
      s.dispose();
    }
  });

  test('made for the mesh renderer, they switch to it once its self-test '
      'passes, and match a plain one', () async {
    const mesh = RasterizerBackend.mesh;
    final state = RasterizerGpu.of(mesh);
    RasterizerGpu.debugResetSupport();
    state.forgetSelfTest();
    RasterizerGpu.allowOpenGles = true;
    RasterizerScene make() =>
        RasterizerScene.fromSvg(tiger, gpu: mesh, maxSize: size.toDouble());
    final scene = make(),
        paths = pathScene(gpu: mesh),
        renderer = await RasterizerRenderer.create(slots: 3, gpu: mesh);
    expect(scene, isA<SwitchingScene>());
    expect(paths, isA<SwitchingScene>());
    expect(renderer, isA<SwitchingRenderer>());
    late RasterizerScene madeDuring;
    final (backends, _) = await renderUntilSettled(
      renderer,
      [scene, paths],
      during: () => madeDuring = make(),
      gpu: mesh,
    );
    // ignore: avoid_print
    print(
      '  ${backends.length} frames with the canvas renderer until the mesh '
      'renderer settled; ${state.supportDetail}',
    );
    expect(await state.settledBackend, mesh);
    expect(backends, everyElement(RasterizerBackend.canvas));
    expect(scene.backend, mesh);
    expect(madeDuring.backend, mesh);
    expect(paths.backend, mesh);
    // The GPU renderer's own self-test hasn't run.
    expect(RasterizerGpu.initialized, isFalse);
    expect(RasterizerGpu.support, RasterizerSupport.openGles);

    final run = render(renderer, [scene, madeDuring, paths]);
    expect(renderer.backend, mesh);
    final plainScene = RasterizerScene.fromSvg(
      tiger,
      backend: mesh,
      maxSize: size.toDouble(),
    );
    final plainPaths = pathScene(backend: mesh);
    final plain = await RasterizerRenderer.create(slots: 3, backend: mesh);
    final plainRun = render(plain, [plainScene, plainScene, plainPaths]);
    final part = run.parts.single, plainPart = plainRun.parts.single;
    expect(part.destination, plainPart.destination);
    final a = await readRgba(part.image), b = await readRgba(plainPart.image);
    final s = part.source, w = part.image.width;
    var differing = 0;
    for (var y = s.top.toInt(); y < s.bottom.toInt(); y++) {
      for (
        var x = 4 * (y * w + s.left.toInt());
        x < 4 * (y * w + s.right.toInt());
        x++
      ) {
        if (a!.getUint8(x) != b!.getUint8(x)) {
          differing++;
        }
      }
    }
    expect(differing, 0, reason: "the switched renderer's frame differs");
    expect(make(), isNot(isA<SwitchingScene>()));
    expect(pathScene(gpu: mesh), isNot(isA<SwitchingScene>()));
    for (final r in [renderer, plain]) {
      r.dispose();
    }
    for (final s in [scene, madeDuring, paths, plainScene, plainPaths]) {
      s.dispose();
    }
  });

  // Frames stop, as in the background, for longer than the self-test's
  // timeout of 20 s per format.
  test(
    'in the background, the self-test waits, and passes once back',
    () async {
      RasterizerGpu.debugResetSupport();
      RasterizerGpu.forgetSelfTest();
      RasterizerGpu.allowOpenGles = true;
      final scene = RasterizerScene.fromSvg(tiger),
          renderer = await RasterizerRenderer.create(slots: 3);
      for (var i = 0; i < 3; i++) {
        render(renderer, [scene]);
        await SchedulerBinding.instance.endOfFrame;
      }
      // Go through the states one at a time, as Android does when the app
      // goes to the background and back.
      void go(List<AppLifecycleState> states) {
        for (final state in states) {
          // ignore: invalid_use_of_protected_member
          SchedulerBinding.instance.handleAppLifecycleStateChanged(state);
        }
      }

      go([
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      await Future<void>.delayed(const Duration(seconds: 25));
      expect(RasterizerGpu.initialized, isFalse);
      go([
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await renderUntilSettled(renderer, [scene]);
      expect(await RasterizerGpu.settledBackend, RasterizerBackend.gpu);
      expect(
        RasterizerGpu.supportDetail,
        'OpenGL ES, self-tested, accumulating in r32Float',
      );
      render(renderer, [scene]);
      expect(renderer.backend, RasterizerBackend.gpu);
      renderer.dispose();
      scene.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'without a passing self-test, they stay with the canvas renderer',
    () async {
      RasterizerGpu.debugResetSupport();
      RasterizerGpu.forgetSelfTest();
      RasterizerGpu.allowOpenGles = true;
      RasterizerGpu.debugFailSelfTest = {'r32Float', 'r16g16b16a16Float'};
      final scene = RasterizerScene.fromSvg(tiger),
          renderer = await RasterizerRenderer.create(slots: 3);
      final (backends, _) = await renderUntilSettled(renderer, [scene]);
      expect(await RasterizerGpu.settledBackend, RasterizerBackend.canvas);
      expect(backends, everyElement(RasterizerBackend.canvas));
      expect(render(renderer, [scene]).isEmpty, isFalse);
      expect(renderer.backend, RasterizerBackend.canvas);
      expect(scene.backend, RasterizerBackend.canvas);
      expect(RasterizerScene.fromSvg(tiger).backend, RasterizerBackend.canvas);
      renderer.dispose();
      scene.dispose();
    },
  );

  test('after a remembered failure, they are plain canvas ones from the '
      'start', () async {
    // The last test's failure is remembered. This is a new launch with
    // nothing forced to fail, where the self-test would pass.
    RasterizerGpu.debugResetSupport();
    RasterizerGpu.debugFailSelfTest = {};
    RasterizerGpu.allowOpenGles = true;
    final scene = RasterizerScene.fromSvg(tiger),
        renderer = await RasterizerRenderer.create(slots: 3);
    expect(scene, isNot(isA<SwitchingScene>()));
    expect(renderer, isNot(isA<SwitchingRenderer>()));
    expect(scene.backend, RasterizerBackend.canvas);
    expect(renderer.backend, RasterizerBackend.canvas);
    expect(await RasterizerGpu.settledBackend, RasterizerBackend.canvas);
    expect(
      RasterizerGpu.supportDetail,
      contains('failed at an earlier launch'),
    );
    expect(render(renderer, [scene]).isEmpty, isFalse);
    renderer.dispose();
    scene.dispose();
  });
}
