// Checks the timeouts of RasterizerGpu.initialize's waits on OpenGL ES. From
// this package's folder:
//   flutter test test/frame_clock_test.dart
//
// A timeout counts only the real time during which frames can come. No frame
// comes in the background, or while the first frame is deferred, as behind a
// splash screen. On desktop, an inactive app, whose window lost the focus, is
// still drawn, so it counts as in the foreground.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/frame_clock.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const limit = Duration(milliseconds: 300);
  setUp(binding.resetInternalState);

  /// Starts a timeout on a future that never completes, then calls [hold].
  ///
  /// Returns whether the timeout fired within [wait], and whether it fired
  /// by twice the limit after [release] was called.
  Future<(bool, bool)> timedOut(
    void Function() hold,
    void Function() release,
    Duration wait,
  ) async {
    var fired = false;
    timeoutWhileFramesCanCome(
      Completer<void>().future,
      limit,
    ).catchError((Object e) => fired = e is TimeoutException);
    hold();
    await Future<void>.delayed(wait);
    final whileHeld = fired;
    release();
    await Future<void>.delayed(limit * 2);
    return (whileHeld, fired);
  }

  test("a future's result and errors pass through", () async {
    expect(await timeoutWhileFramesCanCome(Future.value(1), limit), 1);
    await expectLater(
      timeoutWhileFramesCanCome(Future<void>.error(StateError('x')), limit),
      throwsStateError,
    );
  });

  test('it times out once the limit has passed while frames can come, as '
      'before runApp', () async {
    expect(binding.lifecycleState, isNull);
    expect(framesCanCome, isTrue);
    final watch = Stopwatch()..start();
    await expectLater(
      timeoutWhileFramesCanCome(Completer<void>().future, limit),
      throwsA(isA<TimeoutException>()),
    );
    expect(watch.elapsed, greaterThanOrEqualTo(limit));
  });

  test("time in the background doesn't count", () async {
    final (whileHeld, after) = await timedOut(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.paused),
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      limit * 3,
    );
    expect(whileHeld, isFalse);
    expect(after, isTrue);
  });

  test("time with the first frame deferred doesn't count", () async {
    final (whileHeld, after) = await timedOut(
      binding.deferFirstFrame,
      binding.allowFirstFrame,
      limit * 3,
    );
    expect(whileHeld, isFalse);
    expect(after, isTrue);
  });

  testWidgets(
    'untilForeground waits while inactive or in the background, then for a '
    'frame',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      expect(inForeground, isTrue);
      var back = false;
      untilForeground().then((_) => back = true);
      await tester.pump();
      expect(back, isTrue);

      back = false;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      untilForeground().then((_) => back = true);
      await tester.pump();
      expect(back, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(back, isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(back, isFalse);
      await tester.pump();
      await tester.pump();
      expect(back, isTrue);

      // Now straight from paused to resumed. An AppLifecycleListener would
      // assert against that skip.
      back = false;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
      untilForeground().then((_) => back = true);
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(back, isTrue);
    },
  );

  test('on desktop, inactive counts as in the foreground: a window without the '
      'focus, still drawn', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final desktop = {
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(platform);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(inForeground, desktop, reason: platform.name);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(inForeground, isFalse, reason: platform.name);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(inForeground, isTrue, reason: platform.name);
    }
  });
}
