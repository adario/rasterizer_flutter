/// Renders SVG scenes with one of three renderers ([RasterizerBackend]).
///
/// - The GPU renderer uses Rasterizer's core and Flutter GPU. It works where
///   Impeller gives Flutter GPU a Metal or Vulkan context. On OpenGL ES, it
///   works once [RasterizerGpu.initialize]'s self-test has passed, if
///   [RasterizerGpu.allowOpenGles] is set. Its support is then
///   [RasterizerSupport.supported]. Once per frame, it renders all of the
///   frame's runs ([RasterizerRun]) into one atlas image. It then draws each
///   run from its rectangle with [ui.Canvas.drawImageRect], at the run's
///   place in the app's paint order.
/// - The canvas renderer is the fallback everywhere else. It parses scenes in
///   Dart, and each run draws its scenes' paths with [ui.Canvas.drawPath],
///   straight into the canvas it's drawn into. It works wherever Flutter
///   does, web included.
/// - The mesh renderer is made for games. It imports each SVG once into
///   triangles, which stay in GPU buffers. It renders each run with Flutter
///   GPU into an image of its own, then draws it as the GPU renderer does. It
///   works where Flutter GPU has a context, and on OpenGL ES once its own
///   self-test has passed. Scenes and renderers made with
///   `gpu: RasterizerBackend.mesh` use it where it's supported, else the
///   canvas renderer.
///
/// They have the same API:
///
/// ```dart
/// final frame = renderer.beginFrame(widthPx, heightPx);
/// final run = frame.addRun()..add(scene, 1, 0, 0, 1, x, y);
/// frame.render();
/// run.draw(canvas, scale: devicePixelRatio);
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'src/canvas_renderer.dart';
import 'src/frame_clock.dart';
import 'src/paths/scene_paths.dart';
import 'src/svg_paths/svg_paths.dart';
import 'src/switching.dart';
import 'src/gpu_stub.dart' if (dart.library.ffi) 'src/atlas.dart' as native;

export 'src/rasterizer_canvas.dart' show RasterizerCanvas;

/// Whether a GPU renderer can render here, and if not, why.
enum RasterizerSupport() {
  /// It can render here.
  supported,

  /// The platform isn't macOS, iOS, 64-bit Android or Linux, as with Windows,
  /// 32-bit Android or web.
  unsupportedPlatform,

  /// Flutter renders with Skia, not Impeller.
  noImpeller,

  /// Impeller doesn't give Flutter GPU a context, as it isn't turned on.
  ///
  /// These turn it on:
  /// - on iOS and macOS, `FLTEnableFlutterGPU` in Info.plist.
  /// - on Android, `io.flutter.embedding.android.EnableFlutterGPU` in the
  ///   manifest. This package's manifest sets it.
  /// - on Linux, `fl_dart_project_set_enable_flutter_gpu(project, TRUE)` in
  ///   the runner's `linux/runner/my_application.cc`.
  noFlutterGpu,

  /// Impeller renders with OpenGL ES, and the renderer hasn't passed its
  /// self-test there.
  ///
  /// Android falls back to OpenGL ES without Vulkan, and on devices whose
  /// Vulkan driver Flutter blocks, such as the emulator's. Linux always uses
  /// it. [RasterizerGpuBackend.initialize] runs the self-test, once
  /// [RasterizerGpu.allowOpenGles] is set.
  ///
  /// `io.flutter.embedding.android.ImpellerBackend` set to `vulkan` in the
  /// app's Android manifest asks for Vulkan anyway. Only debug and profile
  /// builds read it: release builds ignore it.
  openGles,
}

/// How scenes are parsed and drawn.
enum RasterizerBackend() {
  /// The GPU renderer: Rasterizer's core, with Flutter GPU.
  ///
  /// The core parses SVGs with NanoSVG. It renders each frame into atlas
  /// images with Flutter GPU. It works only where [RasterizerGpu.support] is
  /// [RasterizerSupport.supported].
  gpu,

  /// The fallback, which works with any of Flutter's renderers.
  ///
  /// vector_graphics_compiler parses SVGs in Dart, and runs draw their paths
  /// with dart:ui's [ui.Canvas].
  canvas,

  /// The mesh renderer, made for games.
  ///
  /// NanoSVG parses each SVG once. Its curves are flattened for the largest
  /// size it's drawn at, and libtess2 turns its fills and stroke outlines into
  /// triangles, which stay in GPU buffers. Each frame then only writes its
  /// entries' transforms, and renders each run into an image of its own.
  ///
  /// The images are 4× multisampled where Flutter GPU supports offscreen
  /// MSAA, else aliased. With [RasterizerRenderer.create]'s `meshSamples` of
  /// 1, they're aliased everywhere. As with the other renderers, an SVG's clip
  /// paths aren't applied.
  ///
  /// It works only where `RasterizerGpu.of(RasterizerBackend.mesh).support`
  /// is [RasterizerSupport.supported]. That's where Flutter GPU has a context,
  /// and on OpenGL ES, once the renderer's own self-test has passed.
  mesh,
}

/// The GPU renderers' support and OpenGL ES self-tests, and the options that
/// all renderers share.
///
/// Each GPU renderer has its own state, from [of]. Members that share a name
/// with one of [RasterizerGpuBackend]'s are the GPU renderer's,
/// [RasterizerBackend.gpu].
abstract final class RasterizerGpu() {
  /// The state of the GPU renderer [gpu]: [RasterizerBackend.gpu] or
  /// [RasterizerBackend.mesh].
  ///
  /// Throws [ArgumentError] for the canvas renderer.
  static RasterizerGpuBackend of(RasterizerBackend gpu) => switch (gpu) {
    RasterizerBackend.gpu => _gpu,
    RasterizerBackend.mesh => _mesh,
    RasterizerBackend.canvas => throw ArgumentError.value(
      gpu,
      'gpu',
      'Not a GPU renderer',
    ),
  };

  static final _gpu = RasterizerGpuBackend._(
    RasterizerBackend.gpu,
    native.SelfTestCache.gpu,
  );
  static final _mesh = RasterizerGpuBackend._(
    RasterizerBackend.mesh,
    native.SelfTestCache.mesh,
  );

  /// Whether Flutter GPU can render here, which both GPU renderers need.
  ///
  /// It's checked once. Off Impeller, getting Flutter GPU's context throws, so
  /// the check looks at whether Impeller is on first.
  static RasterizerSupport get _context =>
      _contextSupport ??= native.checkSupport();
  static RasterizerSupport? _contextSupport;

  /// The GPU renderer's [RasterizerGpuBackend.support].
  static RasterizerSupport get support => _gpu.support;

  /// The GPU renderer's [RasterizerGpuBackend.supportDetail].
  static String? get supportDetail => _gpu.supportDetail;

  /// Whether Impeller renders with OpenGL ES, whether or not the GPU renderers
  /// do.
  static bool get openGles {
    _context;
    return native.openGles;
  }

  /// Lets [RasterizerGpuBackend.initialize] try a GPU renderer on OpenGL ES.
  ///
  /// It's off by default. The self-test checks the renderer's results, and
  /// [rememberSelfTest] stops trying after the renderer crashed or hung the
  /// app twice. But both GPU renderers have only been tried on the Android
  /// emulator's OpenGL ES and on Mesa's llvmpipe on Linux, not on a device's
  /// own driver. `initialize` reads it, so set it before.
  static bool allowOpenGles = false;

  /// The GPU renderer's [RasterizerGpuBackend.initialize].
  static Future<void> initialize() => _gpu.initialize();

  /// The GPU renderer's [RasterizerGpuBackend.initialized].
  static bool get initialized => _gpu.initialized;

  /// The GPU renderer's [RasterizerGpuBackend.settledBackend].
  static Future<RasterizerBackend> get settledBackend => _gpu.settledBackend;

  /// Whether [RasterizerGpuBackend.initialize] remembers, across launches,
  /// that a GPU renderer's self-test failed.
  ///
  /// Later launches then skip the self-test, and draw with the canvas renderer
  /// from the start, as without [allowOpenGles]. It remembers:
  /// - a failure of the self-test's checks, which is the same at every launch
  ///   for one app, OS and driver. Timeouts and exceptions aren't remembered.
  /// - the app crashing or hanging twice in a row, during the self-test or
  ///   after the switch to the GPU renderer, until its renderers have rendered
  ///   [probationFrames] frames. `initialize` counts an attempt as unfinished
  ///   while it runs with the app in the foreground. So a crash in a device's
  ///   driver costs a user two crashes, not one per launch. An app killed in
  ///   the background, as Android does, doesn't count.
  ///   [RasterizerGpuBackend.supportDetail] then says where the attempts
  ///   stopped. Debug builds don't count attempts, as an IDE stops the app in
  ///   the foreground, unless [debugCountAttempts] is set.
  ///
  /// Each GPU renderer keeps this in a small file of its own, in
  /// `Directory.systemTemp`. On Android, that's the app's code cache, which
  /// Android clears when the app or the platform is upgraded. So a new version
  /// of the app, of rasterizer_gpu or of the OS's drivers tries again, but a
  /// GPU driver updated on its own doesn't. On Linux, the file is in the
  /// user's cache (`$XDG_CACHE_HOME`, else `~/.cache`), in a folder named
  /// after the app's executable, and holds for one build of the app. So a new
  /// build tries again, but Mesa updated on its own doesn't.
  ///
  /// A pass isn't remembered: the self-test and its probation run at each
  /// launch until they fail. It's on by default. `initialize` reads it, so set
  /// it before.
  static bool rememberSelfTest = true;

  /// The frames after the switch to a GPU renderer on OpenGL ES, until a
  /// launch's attempt counts as finished ([rememberSelfTest]).
  ///
  /// It's 1800 by default: 30 s of drawing at 60 Hz. Frames rendered by any of
  /// that GPU renderer's renderers count, so a game that shows no vector
  /// content doesn't advance it. 0 finishes the attempt at the switch.
  /// [RasterizerGpuBackend.initialize] reads it, so set it before.
  static int probationFrames = 1800;

  /// For tests: counts attempts ([rememberSelfTest]) in debug builds too.
  @visibleForTesting
  static bool debugCountAttempts = false;

  /// The GPU renderer's [RasterizerGpuBackend.onProbation].
  static bool get onProbation => _gpu.onProbation;

  /// The GPU renderer's [RasterizerGpuBackend.forgetSelfTest].
  static void forgetSelfTest() => _gpu.forgetSelfTest();

  /// For tests: what the self-tests treat as failing.
  ///
  /// It holds the GPU renderer's accumulation formats, by Flutter GPU's
  /// PixelFormat names, `r32Float` and `r16g16b16a16Float`. `mesh` stands for
  /// the mesh renderer's self-test.
  @visibleForTesting
  static Set<String> debugFailSelfTest = {};

  /// For tests: forgets each GPU renderer's support and
  /// [RasterizerGpuBackend.initialize]'s result, so they're checked again.
  ///
  /// It also reads what [rememberSelfTest] keeps again, as a new launch would.
  /// To forget that too, call [RasterizerGpuBackend.forgetSelfTest].
  @visibleForTesting
  static void debugResetSupport() {
    _gpu._reset();
    _mesh._reset();
    _contextSupport = null;
    native.contextError = null;
  }

  /// The GPU renderer's [RasterizerGpuBackend.debugSelfTest].
  @visibleForTesting
  static Future<String?> debugSelfTest() => _gpu.debugSelfTest();

  /// Uses the canvas renderer even where a GPU renderer is supported.
  ///
  /// It applies to scenes and renderers created without a backend after it's
  /// set.
  static bool forceCanvas = false;

  /// The GPU renderer's [RasterizerGpuBackend.backend].
  static RasterizerBackend get backend => _gpu.backend;

  /// Whether the canvas renderer draws each scene as a [ui.Picture] of its
  /// paths, recorded once, rather than drawing its paths each time.
  ///
  /// In a benchmark, pictures halved the UI thread's time, for about the same
  /// raster time.
  static bool canvasPictures = true;

  /// The GPU renderers' shaders, which hook/build.dart builds and pubspec.yaml
  /// lists as an asset.
  static const shaderBundle =
      'packages/rasterizer_gpu/build/shaderbundles/rasterizer.shaderbundle';

  /// Waits for the app's first rasterized frame, and returns whether it came.
  ///
  /// It waits up to 10 s of time in which frames can come: not in the
  /// background, nor while the first frame is deferred. On Android's OpenGL
  /// ES, Flutter GPU's shader and pipeline creation blocks the UI thread on
  /// the raster thread's GL work, which only runs once a frame has been
  /// rasterized. So before `runApp`, the self-test blocks for good, as it did
  /// in a release run. Frames rendered before `runApp`, from a warm-up frame
  /// or straight into the view, don't count, as they aren't rasterized.
  static Future<bool> _firstFrameRasterized() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    if (binding.firstFrameRasterized) {
      return true;
    }
    try {
      await timeoutWhileFramesCanCome(
        binding.waitUntilFirstFrameRasterized,
        const Duration(seconds: 10),
      );
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// One of the GPU renderers, [RasterizerBackend.gpu] or
/// [RasterizerBackend.mesh], from [RasterizerGpu.of].
///
/// It tells whether the renderer can render here. On OpenGL ES, it runs the
/// renderer's own self-test, which lets it render there, and remembers its
/// failures ([RasterizerGpu.rememberSelfTest]). Scenes and renderers made
/// with it as their `gpu` and no backend ([RasterizerScene.fromSvg],
/// [RasterizerRenderer.create]) use it where it's supported, else the canvas
/// renderer.
final class RasterizerGpuBackend._(
  /// Which GPU renderer it is.
  final RasterizerBackend gpu,
  final native.SelfTestCache _cache,
) {
  bool _passed = false, _initialized = false;
  String? _detail;
  Future<void>? _initializing;

  /// The launch's attempt, still open after the switch until the probation's
  /// frames are rendered.
  native.SelfTestAttempt? _probation;

  /// Whether it can render here.
  ///
  /// On OpenGL ES, it's [RasterizerSupport.openGles] until [initialize]'s
  /// self-test has passed.
  RasterizerSupport get support {
    final context = RasterizerGpu._context;
    return context == RasterizerSupport.openGles && _passed
        ? RasterizerSupport.supported
        : context;
  }

  /// More about [support].
  ///
  /// It's Flutter GPU's error when [support] is
  /// [RasterizerSupport.noFlutterGpu]. On OpenGL ES, it says whether and how
  /// the self-test passed, or why it failed.
  String? get supportDetail {
    final context = RasterizerGpu._context;
    return _detail ??
        switch (context) {
          RasterizerSupport.noFlutterGpu => native.contextError,
          RasterizerSupport.openGles =>
            'not self-tested: set RasterizerGpu.allowOpenGles and await '
                '$_api.initialize()',
          _ => null,
        };
  }

  /// Runs its self-test, once, where Impeller renders with OpenGL ES and
  /// [RasterizerGpu.allowOpenGles] is set.
  ///
  /// The self-test renders a small scene and reads it back. The GPU
  /// renderer's accumulates coverage in r32Float, else in r16g16b16a16Float.
  /// The mesh renderer's draws the scene through an affine transform and a
  /// projective one. If it passes, [support] becomes
  /// [RasterizerSupport.supported], and [supportDetail] says how. Otherwise
  /// [support] stays [RasterizerSupport.openGles], and the canvas renderer
  /// draws instead. It never throws, and does nothing elsewhere.
  ///
  /// Apps needn't call it: the first scene or renderer made for it without a
  /// backend starts it. Until it completes, those draw with the canvas
  /// renderer. If the self-test passes, they all switch to this renderer, at
  /// their renderers' next [RasterizerRenderer.beginFrame]. To have them draw
  /// with it from the start, with no switch, await it after `runApp`, before
  /// making any. Nothing is drawn meanwhile then.
  ///
  /// On OpenGL ES, it first waits up to 10 s for the app's first rasterized
  /// frame, as Flutter GPU needs one there. The self-test then compiles the
  /// renderer's pipelines one per frame, as Flutter GPU blocks the UI thread
  /// while it compiles one. Both pause while the app defers its first frame
  /// (`RendererBinding.deferFirstFrame`, as splash screens do) or is in the
  /// background: their timeouts only count time in which frames can be
  /// rasterized. The self-test and the switch take no step that blocks the UI
  /// thread while the app isn't resumed. In the background, one would block
  /// it for good.
  Future<void> initialize() => _initializing ??= _initialize();

  /// Whether [initialize] has completed.
  bool get initialized => _initialized;

  /// Completes with [backend] once it's settled.
  ///
  /// That's at once, unless scenes and renderers made for it without a
  /// backend may still switch to it ([initialize]). Then it's once they have
  /// switched, or won't.
  Future<RasterizerBackend> get settledBackend async {
    if (_switching) {
      await initialize();
    }
    return backend;
  }

  /// Whether it's on probation: switched to on OpenGL ES, with the launch's
  /// attempt still unfinished ([RasterizerGpu.rememberSelfTest]).
  ///
  /// The probation lasts until its renderers have rendered
  /// [RasterizerGpu.probationFrames] frames.
  bool get onProbation => _probation != null;

  /// Forgets a remembered failure ([RasterizerGpu.rememberSelfTest]), so the
  /// next launch runs its self-test again.
  ///
  /// An app's "try the GPU renderer again" setting can call it.
  void forgetSelfTest() => _cache.forget();

  /// The backend that scenes and renderers made for it without one use.
  ///
  /// It's this renderer where it's supported, unless
  /// [RasterizerGpu.forceCanvas] is set. Otherwise it's the canvas renderer.
  RasterizerBackend get backend =>
      !RasterizerGpu.forceCanvas && support == RasterizerSupport.supported
      ? gpu
      : RasterizerBackend.canvas;

  /// For tests: runs its self-test wherever it's supported, Metal and Vulkan
  /// included, without changing [support].
  ///
  /// Returns null if it passed, else why it didn't.
  @visibleForTesting
  Future<String?> debugSelfTest() async {
    final result = await native.selfTest(
      gpu,
      RasterizerGpu.debugFailSelfTest,
      apply: false,
    );
    return result.passed ? null : result.detail;
  }

  /// Its self-test's failure, remembered from an earlier launch
  /// ([RasterizerGpu.rememberSelfTest]), where the self-test would run.
  ///
  /// If there is one, the self-test doesn't run.
  String? get _remembered {
    if (!RasterizerGpu.rememberSelfTest ||
        !RasterizerGpu.allowOpenGles ||
        support != RasterizerSupport.openGles) {
      return null;
    }
    final failure = _cache.rememberedFailure();
    if (failure != null) {
      _detail =
          'not self-tested: it failed at an earlier launch '
          '($_api.forgetSelfTest() tries it again): $failure';
    }
    return failure;
  }

  /// How its members are reached in the API, for [supportDetail]'s messages.
  String get _api => gpu == RasterizerBackend.mesh
      ? 'RasterizerGpu.of(RasterizerBackend.mesh)'
      : 'RasterizerGpu';

  /// Whether scenes and renderers made for it without a backend are made to
  /// switch to it if its self-test passes.
  bool get _switching =>
      RasterizerGpu.allowOpenGles &&
      !_initialized &&
      !RasterizerGpu.forceCanvas &&
      support == RasterizerSupport.openGles &&
      _remembered == null;

  Future<void> _initialize() async {
    native.SelfTestAttempt? attempt;
    String? remember;
    var passed = false;
    var probation = 0;
    try {
      if (RasterizerGpu.allowOpenGles &&
          support == RasterizerSupport.openGles &&
          _remembered == null) {
        if (!await RasterizerGpu._firstFrameRasterized()) {
          _detail =
              'not self-tested: no frame was rasterized within 10 s of frames '
              'being allowed';
        } else {
          // The attempt stays open until the probation's frames after the
          // switch, as a driver may crash on what's drawn next too.
          probation = RasterizerGpu.probationFrames;
          if (RasterizerGpu.rememberSelfTest &&
              (!kDebugMode || RasterizerGpu.debugCountAttempts)) {
            attempt = _cache.startAttempt(probation);
          }
          final result = await native.selfTest(
            gpu,
            RasterizerGpu.debugFailSelfTest,
          );
          _detail = result.detail;
          if (result.passed) {
            passed = true;
            await switchToGpu(gpu, () => _passed = true);
            if (attempt != null && probation > 0) {
              _startProbation(attempt, probation);
              attempt = null;
            }
          } else if (result.conclusive) {
            remember = result.detail;
          }
        }
      }
    } catch (e) {
      _detail = passed
          ? 'self-test passed, but the switch to it failed: $e'
          : 'self-test failed: $e';
    }
    attempt?.finish(remember);
    if (!_passed) {
      settleOnCanvas(gpu);
    }
    _initialized = true;
  }

  /// Called after each frame that one of its renderers renders.
  set _onFrame(void Function()? onFrame) {
    if (gpu == RasterizerBackend.mesh) {
      native.onMeshFrame = onFrame;
    } else {
      native.onGpuFrame = onFrame;
    }
  }

  void _startProbation(native.SelfTestAttempt attempt, int frames) {
    attempt.switched();
    _probation = attempt;
    _onFrame = () {
      if (attempt.frame() < frames) {
        return;
      }
      _onFrame = null;
      _probation = null;
      attempt.finish(null);
    };
  }

  /// For [RasterizerGpu.debugResetSupport].
  void _reset() {
    // The attempt stays in the file as it is, as if the app were killed.
    _probation?.abandon();
    _probation = null;
    _onFrame = null;
    settleOnCanvas(gpu);
    _passed = _initialized = false;
    _initializing = null;
    _detail = null;
    _cache.reload();
  }
}

/// An SVG's outline, for hitboxes: its paths as one [ui.Path].
///
/// It's parsed in Dart, as the canvas renderer's scenes are, whatever the
/// backend. Clips are ignored, as the renderers ignore them.
class SvgOutline._(
  /// The SVG's paths, in its coordinates, x right and y down.
  ///
  /// Filled paths have their contours closed, as SVG fills them. Paths that
  /// are only stroked stay as they are, so their open contours stay open.
  final ui.Path path,

  /// The rectangle that the SVG is drawn from, in its coordinates.
  ///
  /// It's the same as its scenes' [RasterizerSceneRect.rect].
  final ui.Rect rect,
) {
  /// Parses an SVG's bytes.
  ///
  /// Throws [ArgumentError] if they can't be parsed.
  factory SvgOutline.fromSvg(Uint8List bytes) {
    final SvgPaths paths;
    try {
      paths = SvgPaths(utf8.decode(bytes), merge: false);
    } catch (e, stackTrace) {
      Error.throwWithStackTrace(
        ArgumentError('Not parseable SVG data: $e'),
        stackTrace,
      );
    }
    final path = ui.Path();
    for (final p in paths.paths) {
      path.addPath(p.paint.isFilled ? _closed(p.path) : p.path, paths.origin);
    }
    return SvgOutline._(path, _drawnRect(paths.viewBox, paths.bounds));
  }

  /// [path] with its open contours closed.
  static ui.Path _closed(ui.Path path) {
    final metrics = path.computeMetrics().toList();
    if (metrics.every((metric) => metric.isClosed)) {
      return path;
    }
    final closed = ui.Path()..fillType = path.fillType;
    for (final metric in metrics) {
      closed.addPath(
        metric.extractPath(0, metric.length)..close(),
        ui.Offset.zero,
      );
    }
    return closed;
  }
}

/// A neon tube's glow around the paths of a [RasterizerScene.fromPaths].
///
/// Only the mesh renderer draws it. The GPU and canvas renderers draw the
/// same paths without it.
///
/// Each path gets a halo under all of its draws, which fades out from the
/// path's edge to the halo's own. If one of the path's draws strokes it, the
/// halo spreads on both sides of its polylines. Otherwise it spreads outward
/// from each contour, so a hole's halo is hidden under the fill. Halos that
/// overlap add up, within a path as between entries. A halo is light: it
/// covers what's under it as much as its color's strongest channel. So a
/// black halo, or one tinted to black, leaves nothing.
///
/// Each stroke also gets a core over it, which turns near white down its
/// middle and keeps the stroke's color at its edges. Strokes under some 2.7
/// pixels wide get no core. With [RasterizerGlow.widths], fills get a core
/// too.
///
/// Halos and cores are triangles made at import, and drawn with the scene. So
/// a glow takes no layer or pass per path, and an entry's opacity and color
/// transform apply to it. When an entry is faded, its cores show over their
/// draws. Changing a glow takes another import. A glow of no radius or
/// strength is the same as none.
class const RasterizerGlow._(
  /// How far the halo reaches, from a stroke's centre line or a fill's
  /// contour.
  ///
  /// It's in the paths' units, or with [inWidths], in line widths.
  final double radius, {

  /// The halo's alpha on the path, from 0 to 1, as a fraction of its color's.
  ///
  /// Just outside the path, it fades from 0.6 of that. A core has its draw's
  /// alpha.
  final double strength = 1,

  /// The halo's color, or null for the color of the path's last draw.
  ///
  /// A core has its draw's color.
  final ui.Color? color,

  /// Whether [radius] is in line widths: see [RasterizerGlow.widths].
  final bool inWidths = false,
}) {
  this
    : assert(
        radius >= 0 && radius < double.infinity,
        'radius must be finite, >= 0',
      ),
      assert(strength >= 0 && strength <= 1, 'strength must be 0 to 1');

  /// A glow reaching [radius], in the paths' units, as a stroke's width is.
  const RasterizerGlow(double radius, {double strength = 1, ui.Color? color})
    : this._(radius, strength: strength, color: color);

  /// A glow reaching [widths] line widths, so it follows lines that taper.
  ///
  /// For a stroked path, a line width is the widest of the path's strokes.
  /// For a fill, it's the fill's shorter edge at each point of a contour,
  /// which measures a line's width only in a thin shape. So a fill counts as
  /// a line, and gets a core too, unless a draw strokes its path. That core
  /// lies inward of each contour that's neither inside another nor around
  /// one, and reaches half of the shorter edge at each point. A hairline, of
  /// no width, gets neither a halo nor a core.
  const RasterizerGlow.widths(
    double widths, {
    double strength = 1,
    ui.Color? color,
  }) : this._(widths, strength: strength, color: color, inWidths: true);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RasterizerGlow &&
          other.radius == radius &&
          other.strength == strength &&
          other.color == color &&
          other.inWidths == inWidths;

  @override
  int get hashCode => Object.hash(radius, strength, color, inWidths);
}

/// An SVG's paths, or plain paths with their paints, that any number of a
/// frame's entries can draw, each with its own transform.
///
/// A scene is parsed for one backend, and only that backend's renderers can
/// draw it. The exception is a scene that may switch to a GPU renderer on
/// OpenGL ES ([RasterizerGpuBackend.initialize]). It draws with the canvas
/// renderer until the switch, and with that GPU renderer after.
abstract class RasterizerScene {
  /// Parses an SVG's bytes, such as an asset's, for [backend].
  ///
  /// By default, [backend] is the choice of the GPU renderer [gpu],
  /// [RasterizerBackend.gpu] or [RasterizerBackend.mesh]: [gpu] where it's
  /// supported, else the canvas renderer ([RasterizerGpuBackend.backend]).
  /// Throws if the bytes can't be parsed.
  ///
  /// When [backend], or else [gpu], is the mesh renderer, [maxSize] is
  /// required and must be positive, even if the canvas renderer ends up
  /// chosen. It's the most that the SVG's longer side is drawn at, in device
  /// pixels. The SVG's curves are flattened for it, to within 1/4 of a pixel.
  /// Other renderers ignore it.
  ///
  /// A GPU scene's native memory is freed by [dispose], or by a finalizer.
  ///
  /// Without a [backend], while [gpu]'s self-test may still let it draw
  /// ([RasterizerGpuBackend.initialize]), the scene starts the self-test. It
  /// keeps the bytes until it's settled, to parse them for [gpu] at the
  /// switch. If they can't be parsed for [gpu] then, it stays with the canvas
  /// renderer. Runs of [gpu]'s renderers then throw that error when it's
  /// added to them, as [fromSvg] would have.
  factory RasterizerScene.fromSvg(
    Uint8List bytes, {
    RasterizerBackend? backend,
    RasterizerBackend gpu = RasterizerBackend.gpu,
    double? maxSize,
  }) {
    if ((backend ?? gpu) == RasterizerBackend.mesh) {
      if (maxSize == null) {
        throw ArgumentError.notNull('maxSize');
      }
      // Checked here, as the switch would only parse it later.
      if (!(maxSize > 0) || !maxSize.isFinite) {
        throw ArgumentError.value(
          maxSize,
          'maxSize',
          'Not a positive finite number',
        );
      }
    }
    var chosen = backend;
    if (chosen == null) {
      final state = RasterizerGpu.of(gpu);
      if (state._switching) {
        state.initialize();
        return SwitchingScene.fromSvg(bytes, gpu, maxSize);
      }
      chosen = state.backend;
    }
    switch (chosen) {
      case RasterizerBackend.mesh:
        return native.parseMeshScene(bytes, maxSize!);
      case RasterizerBackend.gpu:
        return native.parseScene(bytes);
      case RasterizerBackend.canvas:
        return CanvasScene(bytes);
    }
  }

  /// Plain paths, each drawn with its paint, in paint order, for [backend] or
  /// [gpu], as with [fromSvg].
  ///
  /// A shape's path, with its paint or each of the paints it's drawn with, is
  /// an example. A fill fills its path with the path's [ui.Path.fillType],
  /// with open contours closed. A stroke strokes its path, with open contours
  /// left open. Coordinates are the paths', x right and y down, and the
  /// [viewBox] is their bounds, without their strokes.
  ///
  /// The GPU renderers read each path's contours back with
  /// [ui.Path.computeMetrics]. They flatten them once into polylines, to
  /// within 1/4 of a device pixel when the [viewBox]'s longer side is
  /// [maxSize] device pixels. [maxSize] is the most it's drawn at, and is
  /// required whichever the renderer. So paths count as immutable: changing
  /// one after it's imported gives undefined results. The GPU renderers keep
  /// drawing it as it was. The canvas renderer draws it as it was when it
  /// recorded it as a picture, or else as it is.
  ///
  /// A path keeps its contours while it lives, for the next scene of it with
  /// the same tolerance, such as one with other paints. Contours without a
  /// length are left out, as [ui.Path.computeMetrics] leaves them out. So a
  /// dot drawn as a line of no length with round caps isn't drawn. The
  /// paints' fields are copied. As for SVGs, the GPU renderer's strokes have
  /// a fixed miter limit, and it draws bevel joins as miters.
  ///
  /// Only the mesh renderer draws a [glow]. Its scene's [pathCount] then
  /// counts each path's halo and each draw's core, and its [bounds] reach the
  /// halos. A switching scene's do so from the switch.
  ///
  /// Throws [ArgumentError] if [maxSize] isn't positive. It also throws for a
  /// paint that the GPU renderers can't draw ([canDraw]), whatever the
  /// backend, so that a scene draws the same with each. A GPU scene's native
  /// memory is freed as [fromSvg]'s is.
  factory RasterizerScene.fromPaths(
    List<(ui.Path, ui.Paint)> paths, {
    RasterizerBackend? backend,
    RasterizerBackend gpu = RasterizerBackend.gpu,
    required double maxSize,
    RasterizerGlow? glow,
  }) {
    if (!(maxSize > 0) || !maxSize.isFinite) {
      throw ArgumentError.value(
        maxSize,
        'maxSize',
        'Not a positive finite number',
      );
    }
    final scenePaths = ScenePaths(paths, glow: glow);
    var chosen = backend;
    if (chosen == null) {
      final state = RasterizerGpu.of(gpu);
      if (state._switching) {
        state.initialize();
        return SwitchingScene.fromPaths(scenePaths, gpu, maxSize);
      }
      chosen = state.backend;
    }
    return switch (chosen) {
      RasterizerBackend.mesh => native.importPathMeshScene(scenePaths, maxSize),
      RasterizerBackend.gpu => native.importPathScene(scenePaths, maxSize),
      RasterizerBackend.canvas => CanvasScene.fromPaths(scenePaths),
    };
  }

  /// Whether the GPU renderers can draw a path with [paint], in [fromPaths].
  ///
  /// They can draw a fill, or a stroke of positive width, in an sRGB color,
  /// with [ui.BlendMode.srcOver] and antialiasing. The paint can't have a
  /// shader, a color, mask or image filter, or [ui.Paint.invertColors]. A
  /// hairline, a stroke of width 0, is a device pixel wide under any
  /// transform, so it can't be imported once. What they can't draw can still
  /// be drawn with a [ui.Canvas].
  static bool canDraw(ui.Paint paint) => undrawable(paint) == null;

  /// The backend it's parsed for, whose renderers draw it.
  ///
  /// A scene that may switch ([RasterizerGpuBackend.initialize]) has the
  /// canvas renderer until the switch, then its GPU renderer.
  RasterizerBackend get backend;

  /// Its paths' bounds, grown by half of each stroke's width, in the SVG's
  /// coordinates: x right, y down.
  ///
  /// They're empty if it has no paths. A mesh scene's bounds are its
  /// triangles', which can be tighter than the GPU and canvas renderers'. The
  /// tiger's are 474.2 × 490.0 with the mesh renderer, against 478.5 × 506.9.
  /// So an SVG fitted by its bounds is placed differently by each renderer,
  /// while [viewBox] is the same for all. A scene that switches to a GPU
  /// renderer ([RasterizerGpuBackend.initialize]) has the canvas renderer's
  /// bounds until the switch, then that renderer's.
  ui.Rect get bounds;

  /// The SVG's own rectangle, in its coordinates.
  ///
  /// It's the SVG's viewBox, or else from 0, 0 to its width and height. Its
  /// paths can draw outside it, as [bounds] shows.
  ui.Rect get viewBox;

  /// The number of draws it makes: each path's fill and stroke.
  int get pathCount;

  /// Draws its paths straight into [canvas] with dart:ui, in the SVG's
  /// coordinates, as the canvas renderer does.
  ///
  /// [opacity] scales each path's alpha, and [colorTransform]'s filter
  /// filters each path's color. It draws into any canvas, such as a
  /// picture's, under any transform, with no frame or renderer. Only scenes
  /// that draw with the canvas renderer have paths: it throws [StateError]
  /// unless [backend] is [RasterizerBackend.canvas].
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  });

  /// Frees its memory.
  ///
  /// Frames it was added to keep their own references once rendered. But it
  /// mustn't be disposed of between [RasterizerRun.add] and
  /// [RasterizerFrame.render], nor before a canvas run that draws it is drawn.
  void dispose();
}

/// The rectangle that a [RasterizerScene] is drawn from.
extension RasterizerSceneRect on RasterizerScene {
  /// The rectangle that the scene is drawn from, in its coordinates, such as
  /// to fit it to a size.
  ///
  /// It's the scene's [RasterizerScene.viewBox]. For an SVG with neither a
  /// viewBox nor a size, it's its paths' [RasterizerScene.bounds] instead.
  ui.Rect get rect => _drawnRect(viewBox, bounds);
}

/// [viewBox], or [bounds] if [viewBox] is empty.
ui.Rect _drawnRect(ui.Rect viewBox, ui.Rect bounds) =>
    viewBox.width > 0 && viewBox.height > 0 ? viewBox : bounds;

/// Renders frames with its [backend]'s renderer.
///
/// A GPU renderer keeps [slots] frames in flight, each with its own atlas
/// textures. So a frame's images stay valid until [slots] frames later, when
/// its textures are rendered into again.
abstract class RasterizerRenderer() {
  /// Creates a renderer for [backend].
  ///
  /// By default, [backend] is the GPU renderer [gpu]'s choice, as with
  /// [RasterizerScene.fromSvg]. For a GPU renderer, it throws
  /// [UnsupportedError] unless that renderer's support ([RasterizerGpu.of]) is
  /// [RasterizerSupport.supported].
  ///
  /// Without a [backend], while [gpu]'s self-test may still let it draw
  /// ([RasterizerGpuBackend.initialize]), the renderer starts the self-test.
  /// It draws with the canvas renderer until the self-test passes, then with
  /// [gpu] from the next [beginFrame]. Its [backend] changes then.
  ///
  /// [meshSamples] are the mesh renderer's samples per pixel, 1 or 4, as
  /// Flutter GPU allows. With 4, its runs' targets are multisampled where
  /// Flutter GPU supports offscreen MSAA, so their edges are antialiased. With
  /// 1, or where offscreen MSAA isn't supported, they're aliased, which costs
  /// the GPU less.
  static Future<RasterizerRenderer> create({
    int slots = 3,
    RasterizerBackend? backend,
    RasterizerBackend gpu = RasterizerBackend.gpu,
    int meshSamples = 4,
  }) async {
    if (slots < 1) {
      throw ArgumentError.value(slots, 'slots', 'At least 1');
    }
    if (meshSamples != 1 && meshSamples != 4) {
      throw ArgumentError.value(meshSamples, 'meshSamples', 'Either 1 or 4');
    }
    var chosen = backend;
    if (chosen == null) {
      final state = RasterizerGpu.of(gpu);
      if (state._switching) {
        state.initialize();
        return SwitchingRenderer(slots, gpu, meshSamples);
      }
      chosen = state.backend;
    }
    if (chosen == RasterizerBackend.canvas) {
      return CanvasRenderer(slots);
    }
    final state = RasterizerGpu.of(chosen), support = state.support;
    if (support != RasterizerSupport.supported) {
      final detail = state.supportDetail;
      throw UnsupportedError(
        'rasterizer_gpu: the ${chosen.name} renderer: ${support.name}'
        '${detail == null ? '' : ': $detail'}',
      );
    }
    return chosen == RasterizerBackend.mesh
        ? native.createMeshRenderer(slots, meshSamples)
        : native.createRenderer(slots);
  }

  /// The most that the GPU renderer's atlas pages, and so its viewports,
  /// measure a side.
  ///
  /// Vulkan devices commonly support it, and Metal always does. On OpenGL ES,
  /// the limit is 4096 instead, as Flutter GPU doesn't tell the device's
  /// maximum.
  static const maxAtlasSize = 8192;

  /// The step that atlas pages are sized in.
  ///
  /// Pages grow at once to what a frame needs. They shrink at most once every
  /// 120 frames, to the largest that those frames needed, if that's below
  /// half a page's area. If the viewport changed size meanwhile, as with a
  /// rotation or a window resize, they shrink to that whatever it is.
  /// [trimAtlas] shrinks them too. Pages that no frame needed for 120 frames
  /// are released. Each change reallocates a page's textures.
  static const atlasStep = 256;

  /// The backend it renders with.
  ///
  /// A renderer that may switch ([RasterizerGpuBackend.initialize]) has the
  /// canvas renderer until the switch, then its GPU renderer.
  RasterizerBackend get backend;

  /// How many frames it keeps in flight, from [create].
  int get slots;

  /// The longest viewport side that [beginFrame] takes, in device pixels.
  ///
  /// It's [maxAtlasSize], or 4096 on OpenGL ES, for the GPU and mesh
  /// renderers, and for a renderer that switches to either. It's null for the
  /// plain canvas renderer, which takes any size.
  int? get maxViewportSize;

  /// How many times atlas pages have changed size, frame after frame.
  ///
  /// Each change reallocates their textures. For the mesh renderer, it counts
  /// how many times its runs' targets have been allocated. It's 0 for the
  /// canvas renderer, which has neither.
  int get atlasResizes;

  /// The bytes that its atlas pages' textures hold now, estimated from their
  /// formats.
  ///
  /// The textures are each in-flight frame's target, and each page's depth
  /// and accumulation textures. For the mesh renderer, they're its runs'
  /// targets and their multisampled textures. It's 0 for the canvas renderer,
  /// which has none.
  int get atlasBytes;

  /// Shrinks the atlas pages to the last frame's needs now, and releases the
  /// pages it didn't need.
  ///
  /// Call it when an app knows its frames got lighter, such as at a level
  /// change or when leaving a zoomed view. Later frames grow the pages again
  /// as they need, each growth a reallocation. Called between [beginFrame]
  /// and [RasterizerFrame.render], it waits for that frame, and uses its
  /// needs. The mesh renderer releases its runs' targets, which later frames
  /// allocate again as they need. The canvas renderer does nothing.
  void trimAtlas();

  /// Begins a frame for a [width] x [height] viewport in device pixels, and
  /// ends the last one.
  ///
  /// Entries' transforms map their scene's coordinates to the viewport's, x
  /// right and y down. [curves] has the GPU renderer draw curves as
  /// quadratics, else as line segments.
  ///
  /// The GPU and mesh renderers take viewports up to [maxViewportSize] a
  /// side: [maxAtlasSize], or 4096 on OpenGL ES. So does a renderer that
  /// draws with the canvas renderer until it switches to one of them
  /// ([RasterizerGpuBackend.initialize]). The plain canvas renderer takes any
  /// size.
  RasterizerFrame beginFrame(int width, int height, {bool curves = true});

  /// Frees its native memory and GPU resources.
  ///
  /// Neither it, nor its frame, nor its runs' images may be used after.
  void dispose();
}

/// One frame's runs.
///
/// Add entries to its runs, then [render] it once. Each run can then be
/// drawn. A renderer reuses its frame object, so a frame is only valid until
/// the next [RasterizerRenderer.beginFrame].
abstract class RasterizerFrame() {
  /// The backend that draws it: [RasterizerRenderer.backend] as of
  /// [RasterizerRenderer.beginFrame].
  ///
  /// So for a renderer that switches to a GPU renderer
  /// ([RasterizerGpuBackend.initialize]), it's the canvas renderer until the
  /// switch, then that GPU renderer.
  RasterizerBackend get backend;

  /// Its viewport's width, from [RasterizerRenderer.beginFrame].
  int get width;

  /// Its viewport's height, from [RasterizerRenderer.beginFrame].
  int get height;

  /// How many entries its runs have in all.
  int get entryCount;

  /// The frame's runs, in the order they were added.
  Iterable<RasterizerRun> get runs;

  /// Adds a new run, which is drawn on its own.
  ///
  /// Entries in one run overlap in the order they were added.
  RasterizerRun addRun();

  /// Renders all of its runs, which then have their images.
  ///
  /// The GPU renderer packs the runs' rectangles into atlas pages, and renders
  /// each page once. The mesh renderer renders each run into its own target.
  /// The canvas renderer has nothing to render.
  void render();

  /// The time [render] took to write the frame on the CPU, packing and entries
  /// included, in microseconds.
  ///
  /// It's 0 for the canvas renderer.
  int get cpuMicros;

  /// The time [render] took to upload the frame, in microseconds.
  ///
  /// It's 0 for the canvas renderer.
  int get uploadMicros;

  /// The time [render] took to encode the frame's render passes, in
  /// microseconds.
  ///
  /// It's 0 for the canvas renderer.
  int get encodeMicros;

  /// The sizes of the atlas pages that the last [render] used.
  ///
  /// For the mesh renderer, they're its runs' targets. The canvas renderer has
  /// none.
  List<(int, int)> get pageSizes;
}

/// A color filter applied to each of an entry's paths, rather than to its run
/// as a layer, with the same pixels.
///
/// It's a filter that's linear in premultiplied color and keeps alpha, so it
/// commutes with compositing and antialiasing. Entries with different color
/// transforms share a run.
///
/// [mode] and [matrix] make one, with its [filter], from:
/// - [ui.ColorFilter.mode] with [ui.BlendMode.srcATop] (a tint), `dst` or
///   `clear`, and an sRGB color. Tints are exact.
/// - [ui.ColorFilter.matrix] whose alpha row is (0, 0, 0, 1, 0), and whose
///   color rows' alpha column is 0. Greyscale, sepia, a hue rotation and a
///   saturation are examples, offsets included. Such a matrix's results are
///   clamped to 0 to 1 per path rather than per pixel. That differs where
///   paths that it takes out of range overlap translucently, antialiased
///   edges between paths included. A hue rotation of 2 radians differs there
///   by up to 40/255.
///
/// Modes that scale alpha, such as `modulate`, `srcIn`, `dstIn` and `dstOut`,
/// can't be color transforms. Applied to each path, they would let
/// overlapping paths show through each other, as an entry's opacity does.
///
/// A [ui.ColorFilter] can't be read back: its fields are private, and profile
/// and release builds strip dart:ui's `toString`. So [of] only knows the
/// filters that [mode] and [matrix] made.
class RasterizerColorTransform._(
  /// Its filter, which [of] knows.
  ///
  /// Set on a layer's paint, it gives the pixels that this transform gives
  /// path by path.
  final ui.ColorFilter filter,

  /// The 4 x 4 matrix that it applies to premultiplied colors, row by row.
  ///
  /// Its rows and columns are r, g, b and a. Each color channel is then
  /// clamped from 0 to the alpha. It can't be modified, as [filter] can't.
  final Float32List values,
) {
  this {
    _known[filter] = this;
  }

  /// [ui.ColorFilter.mode] of [color] and [mode], with its transform.
  ///
  /// Returns null if it can't be a transform: see [RasterizerColorTransform].
  static RasterizerColorTransform? mode(ui.Color color, ui.BlendMode mode) {
    if (color.colorSpace != ui.ColorSpace.sRGB) {
      return null;
    }
    final m = _modeMatrix(color.a, color.r, color.g, color.b, mode);
    return m == null
        ? null
        : RasterizerColorTransform._(
            ui.ColorFilter.mode(color, mode),
            m.asUnmodifiableView(),
          );
  }

  /// [ui.ColorFilter.matrix] of [values], 20 of them, row by row, with its
  /// transform.
  ///
  /// Returns null if it can't be a transform: see [RasterizerColorTransform].
  static RasterizerColorTransform? matrix(List<double> values) {
    if (values.length != 20) {
      return null;
    }
    final m = _matrixMatrix(values);
    return m == null
        ? null
        : RasterizerColorTransform._(
            ui.ColorFilter.matrix(values),
            m.asUnmodifiableView(),
          );
  }

  /// The transform [mode] or [matrix] made [filter] with, or null for any
  /// other filter, even an equal one.
  static RasterizerColorTransform? of(ui.ColorFilter filter) => _known[filter];

  static final _known = Expando<RasterizerColorTransform>();

  /// [color] as this transform makes it, as a path of that color takes its
  /// [filter].
  ///
  /// It applies [values] to the premultiplied color, then clamps each color
  /// channel from 0 to the alpha.
  ui.Color apply(ui.Color color) {
    final m = values, a = color.a;
    final r = color.r * a, g = color.g * a, b = color.b * a;
    double row(int i) =>
        m[4 * i] * r + m[4 * i + 1] * g + m[4 * i + 2] * b + m[4 * i + 3] * a;
    final alpha = row(3).clamp(0.0, 1.0);
    if (alpha == 0) {
      return const ui.Color(0x00000000);
    }
    double channel(int i) => row(i).clamp(0.0, alpha) / alpha;
    return ui.Color.from(
      alpha: alpha,
      red: channel(0),
      green: channel(1),
      blue: channel(2),
    );
  }

  /// The matrix of the mode filter of color (r, g, b) at alpha t, the source,
  /// over a pixel, the destination, both premultiplied.
  static Float32List? _modeMatrix(
    double t,
    double r,
    double g,
    double b,
    ui.BlendMode mode,
  ) {
    final m = Float32List(16);
    void diagonal(double c, double a) => m
      ..[0] = c
      ..[5] = c
      ..[10] = c
      ..[15] = a;
    switch (mode) {
      case ui.BlendMode.srcATop: // t·T·A + (1 - t)·C, A
        diagonal(1 - t, 1);
        m
          ..[3] = t * r
          ..[7] = t * g
          ..[11] = t * b;
      case ui.BlendMode.dst:
        diagonal(1, 1);
      case ui.BlendMode.clear:
        break;
      default:
        return null;
    }
    return m;
  }

  /// The matrix on premultiplied colors of [v], a 5 x 4 matrix on
  /// unpremultiplied ones with offsets from 0 to 255, or null.
  ///
  /// It's null unless [v] keeps alpha and its colors don't depend on alpha.
  /// Then c' = M·c + o becomes C' = M·C + o·A once premultiplied.
  static Float32List? _matrixMatrix(List<double> v) {
    if (v[15] != 0 || v[16] != 0 || v[17] != 0 || v[18] != 1 || v[19] != 0) {
      return null;
    }
    final m = Float32List(16)..[15] = 1;
    for (var row = 0; row < 3; row++) {
      if (v[5 * row + 3] != 0) {
        return null;
      }
      for (var c = 0; c < 3; c++) {
        m[4 * row + c] = v[5 * row + c];
      }
      m[4 * row + 3] = v[5 * row + 4] / 255;
    }
    return m;
  }
}

/// A part of a GPU run, in one rectangle of an atlas page.
///
/// A part holds a group of the run's entries whose bounds, grown by a margin,
/// overlap in a chain. No other entry of the run overlaps them. A mesh run
/// has one part, its target: [page] is the target's index among the frame's
/// targets.
class const RasterizerRunPart(
  /// The index of the atlas page it's in.
  final int page,

  /// The atlas page it's in.
  ///
  /// It's valid until [RasterizerRenderer.slots] frames later, and only drawn
  /// once the frame has rendered.
  final ui.Image image,

  /// Its rectangle in [image], in device pixels.
  final ui.Rect source,

  /// A rectangle of the same size in the viewport, in device pixels.
  final ui.Rect destination,
);

/// A run of entries, drawn on its own.
///
/// The GPU renderer draws it as images, from its parts' rectangles in the
/// frame's atlas. The mesh renderer draws its target. The canvas renderer
/// draws its entries' paths.
abstract class RasterizerRun() {
  /// Its position in the frame's runs.
  int get index;

  /// Its parts, for GPU runs, after [place] or [RasterizerFrame.render].
  ///
  /// The parts lie apart from each other in the viewport. So a run of entries
  /// scattered over the viewport takes only their area of the atlas, not the
  /// viewport's. A mesh run has one part, its target. A run has none if it
  /// has nothing to draw, and canvas runs have none.
  List<RasterizerRunPart> get parts;

  /// Whether it has nothing to draw.
  ///
  /// That's when it has no entries, or, for GPU runs once placed, none in the
  /// viewport.
  bool get isEmpty;

  /// Ends it, so it can be drawn before the frame renders.
  ///
  /// That lets it be drawn while painting, as long as the frame renders
  /// before the painting is rasterized. GPU runs are placed in the frame's
  /// atlas now, rather than at [RasterizerFrame.render], which sets their
  /// [parts]. They go onto pages sized for what the last frame's runs needed.
  /// So a run that doesn't fit on one page goes to the next, which is one
  /// more page to render.
  void place();

  /// Adds [scene], drawn with an affine transform from its coordinates to the
  /// viewport's.
  ///
  /// The transform maps (x, y) to (a * x + c * y + tx, b * x + d * y + ty), in
  /// device pixels with y down. Entries added later draw over earlier ones.
  /// [scene] must have been parsed for the renderer's backend.
  /// [addProjective] adds a scene with a perspective.
  ///
  /// [opacity], from 0 to 1, scales the alpha of each of its paths, so paths
  /// that overlap show through each other, unlike with a layer. Entries with
  /// different opacities share the run. An entry whose opacity is 0 isn't
  /// added.
  ///
  /// [colorTransform] filters the color of each of its paths. That gives the
  /// same pixels as a layer with its filter around the entry. Entries with
  /// different color transforms share the run.
  void add(
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  });

  /// [add], with a projective transform, as a perspective gives.
  ///
  /// The transform maps (x, y) to ((a * x + c * y + tx) / w,
  /// (b * x + d * y + ty) / w), where w = g * x + h * y + i. Points where w
  /// isn't positive are behind the eye, and the mesh renderer clips them
  /// away.
  ///
  /// The mesh and canvas renderers draw any such transform. The GPU renderer
  /// only takes affine ones, where g and h are 0, and throws [ArgumentError]
  /// otherwise. It renders its entries without perspective, so a canvas
  /// transform's perspective is applied to its run's images instead, sampled
  /// with [RasterizerRun.draw]'s `filterQuality`.
  void addProjective(
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
    double g,
    double h,
    double i, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  });

  /// [addProjective], with a [Matrix4], such as a canvas's transform.
  ///
  /// Its z row and column are ignored.
  void addMatrix(
    RasterizerScene scene,
    Matrix4 m, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) {
    final s = m.storage;
    addProjective(
      scene,
      s[0],
      s[1],
      s[4],
      s[5],
      s[12],
      s[13],
      s[3],
      s[7],
      s[15],
      opacity: opacity,
      colorTransform: colorTransform,
    );
  }

  /// Draws it into [canvas], whose units are [scale] device pixels, such as a
  /// device pixel ratio, with its viewport's origin at the canvas's.
  ///
  /// [paint] applies to the run as a layer's paint would. A canvas run draws
  /// its paths into a layer with it. A GPU run draws its parts' images with
  /// it, which gives the same pixels. It draws them into a layer instead on
  /// Linux, for an image or mask filter, and for a blend mode that changes
  /// what's under transparent pixels, across several parts. A color filter
  /// that colors transparent pixels colors each part's rectangle, not the
  /// run's whole bounds: both are its entries' bounds with a margin.
  ///
  /// A canvas run draws its entries as they are when it's drawn, so only until
  /// the next [RasterizerRenderer.beginFrame].
  ///
  /// [filterQuality] samples a GPU run's image. The default,
  /// [ui.FilterQuality.none], takes the nearest pixel, as the image is drawn
  /// pixel for pixel. Use [ui.FilterQuality.low] for a canvas whose transform
  /// resamples it, such as one with perspective. A canvas run draws its paths,
  /// and ignores it.
  void draw(
    ui.Canvas canvas, {
    double scale = 1,
    ui.Paint? paint,
    ui.FilterQuality filterQuality = ui.FilterQuality.none,
  });
}
