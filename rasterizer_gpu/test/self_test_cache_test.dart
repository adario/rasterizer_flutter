// Checks what the OpenGL ES self-test remembers across launches. From this
// package's folder:
//   flutter test test/self_test_cache_test.dart
//
// SelfTestCache.reload stands in for each new launch. A failure is
// remembered, and so is each attempt that never finished, as when the app
// crashed or hung. Two unfinished launches in a row become a failure.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/self_test_cache.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final cache = SelfTestCache('rasterizer_gpu_gles.json', 'GPU renderer');
  late Directory dir;
  // Each test's attempts. They're abandoned at the test's end, or their
  // lifecycle observers would write to the next tests' files.
  final attempts = <void Function()>[];

  /// Starts an attempt, as a launch's self-test does, with a probation of 1800
  /// frames.
  SelfTestAttempt startSelfTestAttempt() {
    final attempt = cache.startAttempt(1800);
    attempts.add(attempt.abandon);
    return attempt;
  }

  /// Starts an attempt that gets through the switch, then renders [frames]
  /// GPU frames.
  void throughSwitch(int frames) {
    final attempt = startSelfTestAttempt()..switched();
    for (var i = 0; i < frames; i++) {
      attempt.frame();
    }
  }

  setUp(() {
    binding.resetInternalState();
    dir = Directory.systemTemp.createTempSync('self_test_cache_test');
    cache.debugFile = '${dir.path}/gles.json';
    cache.reload();
  });
  tearDown(() {
    for (final abandon in attempts) {
      abandon();
    }
    attempts.clear();
    cache.debugFile = null;
    cache.reload();
    dir.deleteSync(recursive: true);
  });

  File file() => File(cache.debugFile!);
  Map<String, dynamic> json() =>
      jsonDecode(file().readAsStringSync()) as Map<String, dynamic>;

  /// The failure that the next launch reads.
  String? nextLaunch() {
    cache.reload();
    return cache.rememberedFailure();
  }

  test('nothing is remembered at first, and no file is written by reading', () {
    expect(cache.rememberedFailure(), isNull);
    expect(file().existsSync(), isFalse);
  });

  test("a failure is remembered; a pass, or a result not to remember, isn't, "
      "and leaves no file", () {
    startSelfTestAttempt().finish('self-test failed: forced');
    expect(nextLaunch(), 'self-test failed: forced');
    cache.forget();
    expect(file().existsSync(), isFalse);
    expect(nextLaunch(), isNull);
    startSelfTestAttempt().finish(null);
    expect(file().existsSync(), isFalse);
    expect(nextLaunch(), isNull);
  });

  test('an attempt is counted in the file while it runs, and two unfinished '
      'ones in a row become a failure', () {
    startSelfTestAttempt();
    expect(json()['unfinished'], [null]);
    expect(nextLaunch(), isNull);
    startSelfTestAttempt();
    expect(json()['unfinished'], [null, null]);
    expect(
      nextLaunch(),
      contains('crashed or hung during the self-test, 2 launches in a row'),
    );
    // It's written to the file as a failure, which stays.
    expect(json()['failure'], contains('crashed or hung'));
    expect(json()['unfinished'], isEmpty);
    expect(nextLaunch(), contains('crashed or hung'));
  });

  test("the launch's own attempt, while it runs, isn't counted as an earlier "
      "launch's", () {
    startSelfTestAttempt();
    expect(nextLaunch(), isNull);
    // Still in the same launch, as when each scene made during the self-test
    // reads the remembered failure.
    startSelfTestAttempt();
    expect(cache.rememberedFailure(), isNull);
    expect(json()['failure'], isNull);
    expect(json()['unfinished'], [null, null]);
  });

  test('a finished attempt ends the run of unfinished ones', () {
    startSelfTestAttempt();
    expect(nextLaunch(), isNull);
    startSelfTestAttempt().finish(null);
    expect(nextLaunch(), isNull);
    startSelfTestAttempt();
    expect(nextLaunch(), isNull);
    expect(json()['unfinished'], [null]);
  });

  test("an attempt isn't counted while the app is out of the foreground, so a "
      "kill there doesn't count", () {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    startSelfTestAttempt();
    expect(json()['unfinished'], [null]);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(file().existsSync(), isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // The app is killed here, so the next launch finds no unfinished attempt.
    expect(nextLaunch(), isNull);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(json()['unfinished'], [null]);
  });

  test(
    'an attempt started in the background is counted once the app is back',
    () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final attempt = startSelfTestAttempt();
      expect(file().existsSync(), isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(json()['unfinished'], [null]);
      attempt.finish(null);
      // Once it's finished, lifecycle changes no longer write the file.
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(file().existsSync(), isFalse);
    },
  );

  test('an attempt stays open after the switch, with the GPU frames rendered '
      'at 0, 1, 10, 100 and 1000', () {
    final attempt = startSelfTestAttempt();
    expect(json()['unfinished'], [null]);
    expect(json()['probation'], 1800);
    attempt.switched();
    expect(json()['unfinished'], [0]);
    final written = <int>[];
    for (var i = 1; i <= 1800; i++) {
      final before = file().lastModifiedSync();
      expect(attempt.frame(), i);
      final frames = (json()['unfinished'] as List).single as int;
      if (frames == i) {
        written.add(i);
      }
      if (frames != i) {
        expect(file().lastModifiedSync(), before);
      }
    }
    expect(written, [1, 10, 100, 1000]);
    expect(json()['unfinished'], [1000]);
    attempt.finish(null);
    expect(file().existsSync(), isFalse);
    expect(nextLaunch(), isNull);
  });

  test(
    'two launches unfinished after the switch become a failure that says so',
    () {
      throughSwitch(12);
      throughSwitch(100);
      expect(
        nextLaunch(),
        'crashed or hung after the switch to the GPU renderer, within its '
        'first 1800 frames, 2 launches in a row '
        '(after 10 frames, then after 100 frames)',
      );
      cache.forget();
      throughSwitch(1);
      throughSwitch(0);
      expect(nextLaunch(), endsWith('(after 1 frame, then after 0 frames)'));
    },
  );

  test('one launch unfinished during the self-test and one after the switch '
      'become a failure that says both', () {
    startSelfTestAttempt();
    throughSwitch(10);
    expect(
      nextLaunch(),
      'crashed or hung during the self-test or after the switch to the GPU '
      'renderer, within its first 1800 frames, '
      '2 launches in a row (during the self-test, then after 10 frames)',
    );
  });

  test("a launch ending in the background during its probation neither counts "
      "nor clears the count", () {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The first launch ends unfinished, during the self-test.
    startSelfTestAttempt();
    expect(nextLaunch(), isNull);
    // The second gets through the switch, then goes to the background, where
    // it's killed.
    final attempt = startSelfTestAttempt()..switched();
    attempt.frame();
    expect(json()['unfinished'], [null, 1]);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(json()['unfinished'], [null]);
    // Frames rendered in the background aren't written either.
    for (var i = 0; i < 9; i++) {
      attempt.frame();
    }
    expect(json()['unfinished'], [null]);
    expect(nextLaunch(), isNull);
    expect(json()['unfinished'], [null]);
    // Back in the foreground, it's counted again, with its frames so far.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(json()['unfinished'], [null, 10]);
    attempt.finish(null);
    expect(file().existsSync(), isFalse);
  });

  test("files that don't parse, or from another version of the file or of "
      "Dart, count as none", () {
    for (final content in [
      'not json',
      '[]',
      jsonEncode({
        'version': 0,
        'dart': Platform.version,
        'failure': 'x',
        'attempts': 0,
      }),
      jsonEncode({
        'version': 1,
        'dart': Platform.version,
        'failure': 'x',
        'attempts': 0,
      }),
      jsonEncode({
        'version': 2,
        'dart': 'another',
        'app': appStamp,
        'failure': 'x',
        'unfinished': [],
      }),
      // Another build of the app on Linux. Elsewhere the stamp is null, so
      // any other value.
      jsonEncode({
        'version': 2,
        'dart': Platform.version,
        'app': '0 0',
        'failure': 'x',
        'unfinished': [],
      }),
    ]) {
      file().writeAsStringSync(content);
      expect(nextLaunch(), isNull, reason: content);
    }
    file().writeAsStringSync(
      jsonEncode({
        'version': 2,
        'dart': Platform.version,
        'app': appStamp,
        'failure': 'x',
        'unfinished': [],
      }),
    );
    expect(nextLaunch(), 'x');
  });

  test("on Linux, the file is in the user's XDG cache, for one build of the "
      "app; elsewhere, in the temporary directory", () {
    cache.debugFile = null;
    final name = Platform.resolvedExecutable.split('/').last;
    if (Platform.isLinux) {
      final xdg =
          Platform.environment['XDG_CACHE_HOME'] ??
          '${Platform.environment['HOME']}/.cache';
      expect(cache.path, '$xdg/$name/rasterizer_gpu_gles.json');
      expect(appStamp, isNotNull);
    } else {
      expect(
        cache.path,
        '${Directory.systemTemp.path}/rasterizer_gpu_gles.json',
      );
      expect(appStamp, isNull);
    }
  });

  test("the file's folder is made when needed", () {
    cache.debugFile = '${dir.path}/app/gles.json';
    startSelfTestAttempt().finish('self-test failed: forced');
    expect(nextLaunch(), 'self-test failed: forced');
  });

  test(
    'without a writable directory, nothing is remembered, and nothing throws',
    () {
      // A folder that can't be made, under a file.
      File('${dir.path}/file').writeAsStringSync('');
      cache.debugFile = '${dir.path}/file/gles.json';
      startSelfTestAttempt().finish('self-test failed: forced');
      // The failure is kept for this launch only.
      expect(cache.rememberedFailure(), 'self-test failed: forced');
      expect(nextLaunch(), isNull);
    },
  );

  test("each GPU renderer's self-test has its own file, whose failures name "
      "it", () {
    final mesh = SelfTestCache.mesh;
    expect(mesh.path, endsWith('/rasterizer_gpu_gles_mesh.json'));
    expect(SelfTestCache.gpu.path, endsWith('/rasterizer_gpu_gles.json'));
    mesh
      ..debugFile = '${dir.path}/mesh.json'
      ..reload();
    try {
      for (final frames in [10, 100]) {
        final attempt = mesh.startAttempt(1800)..switched();
        attempts.add(attempt.abandon);
        for (var i = 0; i < frames; i++) {
          attempt.frame();
        }
      }
      mesh.reload();
      expect(
        mesh.rememberedFailure(),
        startsWith('crashed or hung after the switch to the mesh renderer'),
      );
      expect(nextLaunch(), isNull);
    } finally {
      mesh
        ..debugFile = null
        ..reload();
    }
  });
}
