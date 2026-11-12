import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import 'frame_clock.dart' show inForeground;

// On OpenGL ES, RasterizerGpu.initialize's self-test remembers some results
// across launches. It keeps them in one small JSON file in
// Directory.systemTemp, which on Android is the code cache. Android clears
// that when the app or the platform is upgraded. On Linux, the file goes in
// the user's cache instead, for one build of the app: see _defaultPath.
//
// The file remembers:
// - A failure of the self-test's checks. It's deterministic for a given app,
//   OS and driver, so later launches skip the self-test and stay on the
//   canvas renderer. Timeouts and exceptions aren't remembered, as they may be
//   transient.
// - The attempts in a row that didn't finish, such as one that a crash or a
//   hang ended. Only attempts in the foreground count. After
//   [maxUnfinishedAttempts] of them, they're remembered as a failure. A kill
//   in the background, which Android does to save memory, doesn't count: the
//   self-test takes no blocking step there.
// A pass isn't remembered: every launch without a remembered failure runs the
// self-test.
//
// An attempt runs from the self-test's start through a probation: the first
// frames that the GPU renderers render after the switch. A driver can pass the
// self-test, then crash on what a game draws next. The file keeps each
// unfinished attempt's stage: null during the self-test, else the GPU frames
// rendered since the switch. The stage is written at the switch, then at
// frames 1, 10, 100 and 1000, so a few times per launch.
//
// Each GPU renderer has its own self-test, so its own file.

/// The file format's version. A file of another version counts as none.
const _version = 2;

/// The number of attempts in a row that didn't finish in the foreground,
/// after which the self-test isn't tried again.
///
/// It's two, as one may be a user swiping the app away during the self-test.
const maxUnfinishedAttempts = 2;

/// On Linux, the app's build. Null elsewhere.
///
/// It's the modification time and size of the app's compiled Dart code,
/// lib/libapp.so beside the executable. Debug builds have none, so there it's
/// the executable's. The runner isn't relinked when only Dart changes, so the
/// executable's own stamp would miss most upgrades. The size counts too, as
/// reproducible builds may give every file one fixed time (Nix does). A file
/// from another build counts as none. So an upgrade tries the self-test again,
/// as Android's clearing of the code cache makes it do.
@visibleForTesting
final String? appStamp = () {
  if (!Platform.isLinux) {
    return null;
  }
  try {
    final executable = File(Platform.resolvedExecutable);
    final app = File('${executable.parent.path}/lib/libapp.so');
    final stat = (app.existsSync() ? app : executable).statSync();
    return '${stat.modified.millisecondsSinceEpoch} ${stat.size}';
  } catch (_) {
    return null;
  }
}();

/// The file's contents: a remembered failure, each unfinished attempt's stage,
/// and the probation's length in frames, as of the last write.
typedef _Memory = ({String? failure, List<int?> unfinished, int probation});

/// An attempt at an OpenGL ES self-test: see [SelfTestCache.startAttempt].
typedef SelfTestAttempt = ({
  void Function() switched,
  int Function() frame,
  void Function(String? failure) finish,
  void Function() abandon,
});

/// What one GPU renderer's self-test remembers, in its file.
class SelfTestCache(
  /// Its file's name.
  final String name,

  /// The renderer's name, for failures' details.
  final String renderer,
) {
  /// The GPU renderer's cache.
  static final gpu = SelfTestCache('rasterizer_gpu_gles.json', 'GPU renderer');

  /// The mesh renderer's cache.
  static final mesh = SelfTestCache(
    'rasterizer_gpu_gles_mesh.json',
    'mesh renderer',
  );

  /// For tests: the file's path, in place of the default one.
  @visibleForTesting
  String? debugFile;

  /// The file's contents, as this launch read them and has written them
  /// since. Null until first needed.
  _Memory? _memory;

  /// This launch's attempt, until it's finished or abandoned.
  _Attempt? _attempt;

  /// The file, in Directory.systemTemp except on Linux.
  ///
  /// On Linux, that's /tmp, which a reboot clears and an upgrade doesn't. So
  /// there the file goes in the user's XDG cache (`$XDG_CACHE_HOME`, else
  /// `~/.cache`), in a folder named after the app's executable. It's kept for
  /// one build of the app ([appStamp]).
  File get _file => File(debugFile ?? _defaultPath);

  String get _defaultPath {
    if (Platform.isLinux) {
      final env = Platform.environment;
      final xdg = env['XDG_CACHE_HOME'], home = env['HOME'];
      // The XDG spec ignores relative paths.
      final cache = xdg != null && xdg.startsWith('/')
          ? xdg
          : home != null && home.startsWith('/')
          ? '$home/.cache'
          : null;
      if (cache != null) {
        return '$cache/${Platform.resolvedExecutable.split('/').last}/$name';
      }
    }
    return '${Directory.systemTemp.path}/$name';
  }

  /// The file's path, for tests and logs.
  String get path => _file.path;

  _Memory _read() {
    try {
      final json = jsonDecode(_file.readAsStringSync());
      // A file from another format version, Dart version or, on Linux, app
      // build counts as none.
      if (json is Map &&
          json['version'] == _version &&
          json['dart'] == Platform.version &&
          json['app'] == appStamp) {
        return (
          failure: json['failure'] as String?,
          unfinished: [for (final f in json['unfinished'] as List) f as int?],
          probation: json['probation'] as int? ?? 0,
        );
      }
    } catch (_) {
      // A missing or unreadable file counts as none.
    }
    return (failure: null, unfinished: const [], probation: 0);
  }

  void _write(String? failure, List<int?> unfinished, {int probation = 0}) {
    _memory = (failure: failure, unfinished: unfinished, probation: probation);
    try {
      if (failure == null && unfinished.isEmpty) {
        if (_file.existsSync()) {
          _file.deleteSync();
        }
      } else {
        final json = {
          'version': _version,
          'dart': Platform.version,
          'app': appStamp,
          'failure': failure,
          'unfinished': unfinished,
          'probation': probation,
        };
        // The XDG cache's folder may not exist yet. Flush the file, as the
        // process may crash right after.
        _file.parent.createSync(recursive: true);
        _file.writeAsStringSync(jsonEncode(json), flush: true);
      }
    } catch (_) {
      // Without the file, the self-test runs every launch.
    }
  }

  /// The self-test's failure remembered from an earlier launch, or null.
  ///
  /// [maxUnfinishedAttempts] unfinished attempts become a failure, which says
  /// where they stopped. This launch's attempt, while it runs, doesn't count.
  String? rememberedFailure() {
    var memory = _memory ??= _read();
    final unfinished = _attempt?._before ?? memory.unfinished;
    if (memory.failure == null && unfinished.length >= maxUnfinishedAttempts) {
      final String failure;
      if (unfinished.every((frames) => frames == null)) {
        failure =
            'crashed or hung during the self-test, ${unfinished.length} '
            'launches in a row';
      } else {
        final stages = [
          for (final frames in unfinished)
            frames == null
                ? 'during the self-test'
                : 'after $frames frame${frames == 1 ? '' : 's'}',
        ];
        failure =
            'crashed or hung '
            '${unfinished.contains(null) ? 'during the self-test or ' : ''}'
            'after the switch to the $renderer, within its first '
            '${memory.probation} frames, ${unfinished.length} launches in a '
            'row (${stages.join(', then ')})';
      }
      _write(failure, const []);
      memory = _memory!;
    }
    return memory.failure;
  }

  /// Starts this launch's attempt, from the self-test's start. It counts as
  /// unfinished while the app is in the foreground.
  ///
  /// Call [SelfTestAttempt.switched] once the GPU renderers have replaced the
  /// canvas ones. Then call [SelfTestAttempt.frame] for each frame they
  /// render. It returns how many they've rendered since the switch.
  ///
  /// [SelfTestAttempt.finish] ends the attempt with its result: a failure to
  /// remember, or null for a pass or a result not to remember. Either way, it
  /// ends the run of unfinished attempts. [SelfTestAttempt.abandon], for
  /// tests, stops counting the attempt and leaves the file as it is, as a kill
  /// would. [probation] only goes into a failure's details.
  SelfTestAttempt startAttempt(int probation) {
    final attempt = _Attempt(this, (_memory ??= _read()).unfinished, probation);
    _attempt = attempt;
    WidgetsBinding.instance.addObserver(attempt);
    attempt._count();
    void end() {
      WidgetsBinding.instance.removeObserver(attempt);
      if (identical(_attempt, attempt)) {
        _attempt = null;
      }
    }

    return (
      switched: () => attempt._stage(0),
      frame: () {
        final frames = ++attempt._frames;
        if (_checkpoint(frames)) {
          attempt._stage(frames);
        }
        return frames;
      },
      finish: (failure) {
        end();
        _write(failure, const []);
      },
      abandon: end,
    );
  }

  /// Deletes the file, so the next launch, or initialize after
  /// RasterizerGpu.debugResetSupport, runs the self-test.
  void forget() => _write(null, const []);

  /// For tests: reads the file again when next needed, as a new launch would,
  /// with no attempt of its own yet.
  void reload() {
    _memory = null;
    _attempt = null;
  }
}

/// Whether an attempt writes its frame count at [frames]: at 1, 10, 100 and
/// 1000.
bool _checkpoint(int frames) =>
    frames == 1 || frames == 10 || frames == 100 || frames == 1000;

/// Writes the attempt into its cache's file while the app is in the
/// foreground, and takes it out while it isn't.
class _Attempt(
  final SelfTestCache _cache,

  /// The unfinished attempts before this one.
  final List<int?> _before,

  /// The probation's length in frames, for the file.
  final int _probation,
) with WidgetsBindingObserver {
  /// The attempt's stage at its last checkpoint: null during the self-test,
  /// else the GPU frames rendered since the switch.
  int? _written;

  /// The GPU frames rendered since the switch.
  int _frames = 0;

  /// Whether the file counts the attempt, as the app is in the foreground.
  /// Null until first checked.
  bool? _counted;

  void _stage(int frames) {
    _written = frames;
    if (_counted == true) {
      _writeCounted();
    }
  }

  void _count() {
    final counted = inForeground;
    if (counted == _counted) {
      return;
    }
    _counted = counted;
    if (counted) {
      _writeCounted();
    } else {
      _cache._write(null, _before, probation: _probation);
    }
  }

  void _writeCounted() =>
      _cache._write(null, [..._before, _written], probation: _probation);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _count();
}
