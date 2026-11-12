import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

// Helpers for RasterizerGpu.initialize on OpenGL ES. Its self-test and the
// switch to the GPU renderer run their steps that block the UI thread only in
// the foreground. Their waits, for the first rasterized frame and for each
// self-test format, only count the time during which a frame could come. No
// frame comes while the app is in the background, or while its first frame is
// deferred, as behind a splash screen or asynchronous Localizations.

/// Whether the app is in the foreground.
///
/// The app is in the foreground when it's resumed, and before its lifecycle
/// state is known, as before runApp. An inactive app is in the foreground only
/// on desktop, where inactive means a window without focus, which is still
/// drawn. On Android, inactive comes just before the app goes to the
/// background and loses its surface.
bool get inForeground => switch (WidgetsBinding.instance.lifecycleState) {
  null || AppLifecycleState.resumed => true,
  AppLifecycleState.inactive => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  },
  _ => false,
};

/// Completes at once in the foreground, otherwise once the app is back and
/// has drawn a frame.
///
/// On OpenGL ES, Flutter GPU's shader registration and pipeline compilation
/// block the UI thread until the raster thread runs their GL work, which it
/// only does while rasterizing frames. In the background, no frame comes, and
/// a frame needs the UI thread, so those calls would block it for good.
/// Callers make those calls right after this completes, with no `await` in
/// between.
Future<void> untilForeground() async {
  while (!inForeground) {
    final observer = _Foreground();
    WidgetsBinding.instance.addObserver(observer);
    await observer.back.future;
    WidgetsBinding.instance.removeObserver(observer);
    await SchedulerBinding.instance.endOfFrame;
  }
}

/// Completes [back] once the app is [inForeground].
///
/// A [WidgetsBindingObserver] rather than an AppLifecycleListener, which
/// asserts that the state changes one step at a time: tests can skip steps.
class _Foreground() with WidgetsBindingObserver {
  final back = Completer<void>();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (inForeground && !back.isCompleted) {
      back.complete();
    }
  }
}

/// Whether the app can rasterize a frame now: it's [inForeground], and its
/// first frame isn't deferred.
///
/// This is true before runApp too, though `framesEnabled` is false then: an
/// app that awaits RasterizerGpu.initialize before runApp should time out,
/// not wait forever.
bool get framesCanCome =>
    inForeground && WidgetsBinding.instance.sendFramesToEngine;

/// Completes with [future]'s result, or with a [TimeoutException] once [limit]
/// has passed while [framesCanCome].
///
/// Time while frames can't come doesn't count. This checks [framesCanCome]
/// every 100 ms.
Future<T> timeoutWhileFramesCanCome<T>(Future<T> future, Duration limit) {
  final completer = Completer<T>();
  final watch = Stopwatch()..start();
  var counted = Duration.zero, last = Duration.zero;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    final now = watch.elapsed;
    if (framesCanCome) {
      counted += now - last;
    }
    last = now;
    if (counted >= limit) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(null, limit));
      }
    }
  });
  future.then(
    (value) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    },
    onError: (Object error, StackTrace stack) {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
  );
  return completer.future;
}
