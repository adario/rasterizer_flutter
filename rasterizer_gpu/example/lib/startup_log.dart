import 'dart:async' show Timer;
import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, WidgetsFlutterBinding;

/// Logs the app's frames while the renderer initializes, which runs the
/// OpenGL ES self-test there, and for as long again after it, as a baseline.
///
/// It logs a `RASTERIZER_EXAMPLE startup` line with each of the two windows'
/// frames, the longest gap between frames, and how many gaps missed a vsync.
/// On OpenGL ES, Flutter GPU blocks the UI thread while it creates
/// pipelines, which shows as gaps.
///
/// Meanwhile, `RASTERIZER_EXAMPLE event` lines mark the first frame
/// rasterized, lifecycle changes, and stalls of the UI thread over 250 ms,
/// with their time since [begin]. A stall shows as a timer that fires late,
/// so stalls show up even in the background, without frames.
class StartupLog._() {
  static final List<FrameTiming> _timings = [];

  /// When [begin] was called, in microseconds on the [Timeline] clock.
  static int? _start;
  static AppLifecycleListener? _lifecycle;

  /// A timer that ticks every 20 ms, to find UI thread stalls.
  static Timer? _heartbeat;

  /// The longest UI thread stall so far, in microseconds.
  static int _stall = 0;

  /// Starts collecting frame timings, and marking events.
  static void begin() {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    _start = Timeline.now;
    SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
    binding.waitUntilFirstFrameRasterized.then(
      (_) => mark('first frame rasterized'),
    );
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => mark('lifecycle ${state.name}'),
    );
    var last = Timeline.now;
    _heartbeat = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final now = Timeline.now, stall = now - last - 20000;
      last = now;
      if (stall > _stall) {
        _stall = stall;
      }
      if (stall > 250000) {
        mark('UI thread stalled ${stall ~/ 1000} ms');
      }
    });
  }

  /// Logs [what], with the time since [begin].
  static void mark(String what) {
    final start = _start;
    if (start == null) {
      return;
    }
    debugPrint(
      'RASTERIZER_EXAMPLE event $what at ${(Timeline.now - start) ~/ 1000} ms',
    );
  }

  /// Marks the end of [what], such as the renderer's initialization, and logs
  /// the startup line once as long again has passed.
  static void end(String what) {
    final start = _start;
    if (start == null) {
      return;
    }
    final end = Timeline.now;
    Future.delayed(Duration(microseconds: end - start + 200000), () {
      SchedulerBinding.instance.removeTimingsCallback(_timings.addAll);
      _lifecycle?.dispose();
      _heartbeat?.cancel();
      debugPrint(
        'RASTERIZER_EXAMPLE startup $what: ${(end - start) ~/ 1000} ms; '
        'during: ${_window(start, end)}; after: '
        '${_window(end, 2 * end - start)}; '
        'longest UI stall ${_stall ~/ 1000} ms',
      );
      _timings.clear();
    });
  }

  /// Summarizes the frames whose vsync started from [from] to [to], in
  /// microseconds on the [Timeline] clock.
  static String _window(int from, int to) {
    final frames = [
      for (final t in _timings)
        if (t.timestampInMicroseconds(FramePhase.vsyncStart) >= from &&
            t.timestampInMicroseconds(FramePhase.vsyncStart) < to)
          t,
    ];
    if (frames.isEmpty) {
      return 'no frames';
    }
    var gap = 0, missed = 0, build = 0, raster = 0;
    for (var i = 0; i < frames.length; i++) {
      build = build > frames[i].buildDuration.inMicroseconds
          ? build
          : frames[i].buildDuration.inMicroseconds;
      raster = raster > frames[i].rasterDuration.inMicroseconds
          ? raster
          : frames[i].rasterDuration.inMicroseconds;
      if (i == 0) {
        continue;
      }
      final g =
          frames[i].timestampInMicroseconds(FramePhase.rasterFinish) -
          frames[i - 1].timestampInMicroseconds(FramePhase.rasterFinish);
      if (g > gap) {
        gap = g;
      }
      // A gap over 1.5 frame periods, at 60 Hz, missed at least one vsync.
      if (g > 25000) {
        missed++;
      }
    }
    return '${frames.length} frames, longest gap ${gap ~/ 1000} ms, $missed '
        'gaps over 25 ms, '
        'longest build ${build ~/ 1000} ms, raster ${raster ~/ 1000} ms';
  }
}
