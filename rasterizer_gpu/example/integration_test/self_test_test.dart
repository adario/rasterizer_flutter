// Checks the OpenGL ES self-test, which RasterizerGpu.initialize runs, in the
// app, wherever the GPU renderer can render:
//   flutter test integration_test/self_test_test.dart -d <device>
//
// On OpenGL ES, as on an Android emulator built with
// IMPELLER_BACKEND=opengles, it checks initialize and its fallbacks. On
// Metal and Vulkan, initialize does nothing, so it checks the self-test
// itself, which must pass there too.
//
// On OpenGL ES, it also checks:
// - what the self-test remembers across launches, each simulated by
//   debugResetSupport;
// - the probation after the switch to the GPU renderer;
// - the mesh renderer's own self-test, file and probation.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The self-test's SVG and the GPU renderer's entry types are internal.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

void main() {
  // Fully live, so that runApp's frame is drawn: see setUpAll.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Tests run debug builds, which don't count attempts unless asked.
  RasterizerGpu.debugCountAttempts = true;

  final openGles = RasterizerGpu.openGles;
  if (!openGles && RasterizerGpu.support != RasterizerSupport.supported) {
    test(
      'no GPU renderer here',
      () {},
      skip: 'support ${RasterizerGpu.support.name}',
    );
    return;
  }

  final mesh = RasterizerGpu.of(RasterizerBackend.mesh);

  /// Runs [gpu]'s initialize again, as a new launch would.
  ///
  /// [allow] sets allowOpenGles, and [fail] names the self-tests forced to
  /// fail. [probation] is the probation's length in frames: with 0, the
  /// default, the attempt finishes at the switch. Unless [remembered], it
  /// first forgets what earlier launches remembered.
  Future<void> initialize({
    RasterizerBackend gpu = RasterizerBackend.gpu,
    bool allow = true,
    Set<String> fail = const {},
    bool remembered = false,
    int probation = 0,
  }) async {
    final state = RasterizerGpu.of(gpu);
    RasterizerGpu.debugResetSupport();
    if (!remembered) {
      state.forgetSelfTest();
    }
    RasterizerGpu.allowOpenGles = allow;
    RasterizerGpu.debugFailSelfTest = fail;
    RasterizerGpu.probationFrames = probation;
    await state.initialize();
    // ignore: avoid_print
    print('  ${gpu.name} ${state.support.name}: ${state.supportDetail}');
  }

  // As in apps, initialize runs after runApp. On OpenGL ES, it waits for a
  // rasterized frame.
  setUpAll(() => runApp(const SizedBox()));
  tearDownAll(() async {
    await initialize();
    mesh.forgetSelfTest();
  });

  test('the self-test scene makes every kind of entry SVGs make', () async {
    await initialize();
    final renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.gpu,
    ) as ra.AtlasRenderer;
    final scene = RasterizerScene.fromSvg(
      utf8.encode(ra.selfTestSvg),
      backend: RasterizerBackend.gpu,
    );
    final types = <ra.EntryType>{};
    renderer.debugFrameWritten = (_, frame) => types.addAll([
      for (final e in frame.entries)
        if (e.count > 0) e.type,
    ]);
    for (final curves in [true, false]) {
      final frame = renderer.beginFrame(
        ra.selfTestSize,
        ra.selfTestSize,
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

  if (openGles) {
    test('initialize passes the self-test, accumulating in r32Float', () async {
      await initialize();
      expect(RasterizerGpu.support, RasterizerSupport.supported);
      expect(RasterizerGpu.backend, RasterizerBackend.gpu);
      expect(RasterizerGpu.supportDetail, contains('accumulating in r32Float'));
    });

    test('initialize falls back to r16g16b16a16Float', () async {
      await initialize(fail: {'r32Float'});
      expect(RasterizerGpu.support, RasterizerSupport.supported);
      expect(
        RasterizerGpu.supportDetail,
        contains('accumulating in r16g16b16a16Float'),
      );
      final renderer = await RasterizerRenderer.create(slots: 1);
      expect(renderer.backend, RasterizerBackend.gpu);
      renderer.dispose();
    });

    test('initialize falls back to the canvas renderer', () async {
      await initialize(fail: {'r32Float', 'r16g16b16a16Float'});
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(RasterizerGpu.backend, RasterizerBackend.canvas);
      expect(RasterizerGpu.supportDetail, startsWith('self-test failed'));
    });

    test('without allowOpenGles, initialize does nothing', () async {
      await initialize(allow: false);
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(RasterizerGpu.supportDetail, startsWith('not self-tested'));
      expect(RasterizerGpu.initialized, isTrue);
    });

    // What the self-test remembers across launches.
    final file = File(ra.SelfTestCache.gpu.path);

    test("the self-test's file is in the code cache, which Android clears on "
        "upgrades; on Linux, in the user's cache", () {
      if (Platform.isLinux) {
        final name = Platform.resolvedExecutable.split('/').last;
        expect(file.path, endsWith('/$name/rasterizer_gpu_gles.json'));
        expect(
          file.path,
          startsWith(
            Platform.environment['XDG_CACHE_HOME'] ??
                '${Platform.environment['HOME']}/.cache/',
          ),
        );
      } else {
        expect(file.path, endsWith('/code_cache/rasterizer_gpu_gles.json'));
      }
    });

    test(
      "a pass isn't remembered, and with no probation, leaves no file",
      () async {
        await initialize();
        expect(RasterizerGpu.support, RasterizerSupport.supported);
        expect(file.existsSync(), isFalse);
      },
    );

    test("a failure is remembered: the next launch doesn't run the self-test, "
        "until it's forgotten", () async {
      await initialize(fail: {'r32Float', 'r16g16b16a16Float'});
      expect(file.existsSync(), isTrue);
      // Nothing forced now: if the self-test ran, it would pass.
      final watch = Stopwatch()..start();
      await initialize(remembered: true);
      expect(
        watch.elapsedMilliseconds,
        lessThan(50),
        reason: 'the self-test ran',
      );
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(RasterizerGpu.backend, RasterizerBackend.canvas);
      expect(
        RasterizerGpu.supportDetail,
        contains('failed at an earlier launch'),
      );
      expect(RasterizerGpu.supportDetail, contains('forced to fail'));
      expect(await RasterizerGpu.settledBackend, RasterizerBackend.canvas);
      RasterizerGpu.forgetSelfTest();
      expect(file.existsSync(), isFalse);
      await initialize(remembered: true);
      expect(RasterizerGpu.support, RasterizerSupport.supported);
    });

    test('two launches in a row that died during the self-test are remembered '
        'as a failure', () async {
      await initialize(fail: {'r32Float', 'r16g16b16a16Float'});
      // Write what two attempts that didn't finish in the foreground leave.
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      file.writeAsStringSync(
        jsonEncode({
          ...json,
          'failure': null,
          'unfinished': [null, null],
        }),
      );
      await initialize(remembered: true);
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(
        RasterizerGpu.supportDetail,
        contains('crashed or hung during the self-test, 2 launches in a row'),
      );
      // With only one, the self-test runs, and its pass deletes the file.
      file.writeAsStringSync(
        jsonEncode({
          ...json,
          'failure': null,
          'unfinished': [null],
        }),
      );
      await initialize(remembered: true);
      expect(RasterizerGpu.support, RasterizerSupport.supported);
      expect(file.existsSync(), isFalse);
    });

    // The probation after the switch.
    Map<String, dynamic> json([File? of]) =>
        jsonDecode((of ?? file).readAsStringSync()) as Map<String, dynamic>;

    test("after the switch, the attempt stays open until the probation's GPU "
        "frames are rendered", () async {
      await initialize(probation: 1800);
      expect(RasterizerGpu.support, RasterizerSupport.supported);
      expect(RasterizerGpu.onProbation, isTrue);
      expect(json()['unfinished'], [0]);
      final renderer = await RasterizerRenderer.create(slots: 1);
      final scene = RasterizerScene.fromSvg(utf8.encode(ra.selfTestSvg));
      expect(renderer.backend, RasterizerBackend.gpu);
      // Render 30 frames for each Flutter frame, to go faster.
      for (var i = 0; i < 1799; i++) {
        final frame = renderer.beginFrame(ra.selfTestSize, ra.selfTestSize);
        frame.addRun().add(scene, 1, 0, 0, 1, 0, 0);
        frame.render();
        if (i % 30 == 29) {
          await SchedulerBinding.instance.endOfFrame;
        }
      }
      expect(RasterizerGpu.onProbation, isTrue);
      expect(json()['unfinished'], [1000]);
      final frame = renderer.beginFrame(ra.selfTestSize, ra.selfTestSize);
      frame.addRun().add(scene, 1, 0, 0, 1, 0, 0);
      frame.render();
      expect(RasterizerGpu.onProbation, isFalse);
      expect(file.existsSync(), isFalse);
      renderer.dispose();
      scene.dispose();
    });

    test('two launches in a row that died after the switch are remembered as a '
        'failure that says so', () async {
      await initialize(fail: {'r32Float', 'r16g16b16a16Float'});
      // Write what two attempts that didn't finish in the foreground, after
      // the switch, leave.
      file.writeAsStringSync(
        jsonEncode({
          ...json(),
          'failure': null,
          'unfinished': [10, 100],
          'probation': 1800,
        }),
      );
      await initialize(remembered: true);
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(
        RasterizerGpu.supportDetail,
        contains(
          'crashed or hung after the switch to the GPU renderer, within its '
          'first 1800 frames, 2 launches in a row '
          '(after 10 frames, then after 100 frames)',
        ),
      );
    });

    test("in debug builds, attempts aren't counted unless asked", () async {
      RasterizerGpu.debugCountAttempts = false;
      try {
        await initialize(probation: 1800);
        expect(RasterizerGpu.support, RasterizerSupport.supported);
        expect(RasterizerGpu.onProbation, isFalse);
        expect(file.existsSync(), isFalse);
      } finally {
        RasterizerGpu.debugCountAttempts = true;
      }
    });

    // The mesh renderer's own self-test, file and probation.
    final meshFile = File(ra.SelfTestCache.mesh.path);

    test("the mesh renderer's self-test passes on its own, leaving the GPU "
        "renderer's not run", () async {
      await initialize(gpu: RasterizerBackend.mesh);
      expect(mesh.support, RasterizerSupport.supported);
      expect(mesh.backend, RasterizerBackend.mesh);
      expect(mesh.supportDetail, startsWith('OpenGL ES, self-tested, '));
      expect(RasterizerGpu.support, RasterizerSupport.openGles);
      expect(RasterizerGpu.initialized, isFalse);
      expect(meshFile.existsSync(), isFalse);
    });

    test("its failure is remembered in its own file, which says how to forget "
        "it", () async {
      await initialize(gpu: RasterizerBackend.mesh, fail: {'mesh'});
      expect(mesh.support, RasterizerSupport.openGles);
      expect(mesh.backend, RasterizerBackend.canvas);
      expect(mesh.supportDetail, 'self-test failed: forced to fail');
      expect(meshFile.existsSync(), isTrue);
      expect(file.existsSync(), isFalse);
      await initialize(gpu: RasterizerBackend.mesh, remembered: true);
      expect(mesh.support, RasterizerSupport.openGles);
      expect(
        mesh.supportDetail,
        contains(
          '(RasterizerGpu.of(RasterizerBackend.mesh).forgetSelfTest() tries '
          'it again)',
        ),
      );
      // The GPU renderer's self-test isn't remembered as failed.
      await initialize(remembered: true);
      expect(RasterizerGpu.support, RasterizerSupport.supported);
      mesh.forgetSelfTest();
      expect(meshFile.existsSync(), isFalse);
    });

    test(
      "after its switch, its probation counts the mesh renderers' frames",
      () async {
        await initialize(gpu: RasterizerBackend.mesh, probation: 3);
        expect(mesh.onProbation, isTrue);
        expect(RasterizerGpu.onProbation, isFalse);
        expect(json(meshFile)['unfinished'], [0]);
        final renderer = await RasterizerRenderer.create(
          slots: 1,
          gpu: RasterizerBackend.mesh,
        );
        final scene = RasterizerScene.fromSvg(
          utf8.encode(ra.selfTestSvg),
          gpu: RasterizerBackend.mesh,
          maxSize: ra.selfTestSize.toDouble(),
        );
        expect(renderer.backend, RasterizerBackend.mesh);
        for (var i = 0; i < 3; i++) {
          expect(mesh.onProbation, isTrue);
          final frame = renderer.beginFrame(ra.selfTestSize, ra.selfTestSize);
          frame.addRun().add(scene, 1, 0, 0, 1, 0, 0);
          frame.render();
        }
        expect(mesh.onProbation, isFalse);
        expect(meshFile.existsSync(), isFalse);
        renderer.dispose();
        scene.dispose();
      },
    );

    test("without rememberSelfTest, a failure isn't remembered", () async {
      RasterizerGpu.rememberSelfTest = false;
      try {
        await initialize(fail: {'r32Float', 'r16g16b16a16Float'});
        expect(file.existsSync(), isFalse);
        await initialize(remembered: true);
        expect(RasterizerGpu.support, RasterizerSupport.supported);
      } finally {
        RasterizerGpu.rememberSelfTest = true;
      }
    });
  } else {
    test(
      'initialize does nothing on Metal and Vulkan, and writes no file',
      () async {
        await initialize();
        expect(RasterizerGpu.support, RasterizerSupport.supported);
        expect(RasterizerGpu.supportDetail, isNull);
        expect(File(ra.SelfTestCache.gpu.path).existsSync(), isFalse);
      },
    );

    test('the self-test passes here, with either accumulation format, and '
        'fails with neither', () async {
      expect(await RasterizerGpu.debugSelfTest(), isNull);
      RasterizerGpu.debugFailSelfTest = {'r32Float'};
      expect(await RasterizerGpu.debugSelfTest(), isNull);
      RasterizerGpu.debugFailSelfTest = {'r32Float', 'r16g16b16a16Float'};
      expect(
        await RasterizerGpu.debugSelfTest(),
        startsWith('self-test failed'),
      );
      RasterizerGpu.debugFailSelfTest = {};
    });

    test("the mesh renderer's self-test passes here too, and fails when "
        "forced", () async {
      expect(await mesh.debugSelfTest(), isNull);
      RasterizerGpu.debugFailSelfTest = {'mesh'};
      expect(await mesh.debugSelfTest(), 'self-test failed: forced to fail');
      RasterizerGpu.debugFailSelfTest = {};
      expect(mesh.support, RasterizerSupport.supported);
      expect(mesh.supportDetail, isNull);
    });
  }
}
