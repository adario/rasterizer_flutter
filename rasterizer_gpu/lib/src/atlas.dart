import 'dart:ffi';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'core.dart' as ra;
import '../rasterizer_gpu.dart';
import 'atlas_pages.dart';
import 'atlas_parts.dart';
import 'canvas_paths.dart';
import 'frame_clock.dart';
import 'gpu_renderer.dart';
import 'image_run.dart';
import 'meshes.dart';
import 'paths/scene_paths.dart';
import 'self_test.dart';
import 'switching.dart';

export 'self_test_cache.dart' show SelfTestAttempt, SelfTestCache;

// The GPU renderer, and the entry points of both GPU renderers: the core,
// through FFI, and Flutter GPU. rasterizer_gpu.dart imports this file where
// dart:ffi is available, else gpu_stub.dart, which has the same functions.

/// Flutter GPU's error, when checkSupport found no context.
String? contextError;

/// Called after each frame that a GPU renderer renders, whatever its
/// viewport.
///
/// RasterizerGpu sets it to count the frames of the OpenGL ES probation.
void Function()? onGpuFrame;

/// The same as [onGpuFrame], after each frame that a mesh renderer renders.
void Function()? onMeshFrame;

/// Whether Impeller renders with OpenGL ES, as checkSupport found.
bool openGles = false;

/// The format the GPU renderer accumulates coverage in.
///
/// On OpenGL ES, it's the format the self-test passed with.
gpu.PixelFormat accumulationFormat = gpu.PixelFormat.r32Float;

/// The largest size of atlas pages, mesh targets and viewports.
///
/// That's RasterizerRenderer.maxAtlasSize, but 4096 on OpenGL ES. OpenGL ES
/// only guarantees 2048, and Flutter GPU doesn't tell the device's maximum.
/// The data texture is 4096 wide, so the self-test checks that size.
int maxPageSize = RasterizerRenderer.maxAtlasSize;

/// Whether Flutter GPU can render here, for both GPU renderers.
///
/// On OpenGL ES, it returns [RasterizerSupport.openGles]: the renderers draw
/// only once their self-tests pass.
RasterizerSupport checkSupport() {
  if (!Platform.isMacOS &&
      !Platform.isIOS &&
      !Platform.isAndroid &&
      !Platform.isLinux) {
    return RasterizerSupport.unsupportedPlatform;
  }
  // The build hook builds no native code for 32-bit Android.
  if (Platform.isAndroid &&
      Abi.current() != Abi.androidArm64 &&
      Abi.current() != Abi.androidX64) {
    return RasterizerSupport.unsupportedPlatform;
  }
  // dart:ui's flag for an Impeller engine.
  if (!ui.ImageFilter.isShaderFilterSupported) {
    return RasterizerSupport.noImpeller;
  }
  final gpu.GpuContext context;
  try {
    context = gpu.gpuContext;
  } catch (e) {
    contextError = '$e';
    return RasterizerSupport.noFlutterGpu;
  }
  // Flutter GPU documents this as false only on the OpenGL ES backend, which
  // can't yet render into a texture's non-zero mip levels.
  if (!context.doesSupportFramebufferRenderMipmap) {
    openGles = true;
    maxPageSize = 4096;
    return RasterizerSupport.openGles;
  }
  return RasterizerSupport.supported;
}

/// Runs the OpenGL ES self-test of the GPU renderer [backend], gpu or mesh.
///
/// It returns whether the test passed, its detail, and whether a failure is
/// conclusive: one from its checks alone, not from exceptions or timeouts,
/// which may be transient. Only a conclusive failure is remembered. The test
/// runs wherever the renderer can, as tests check it on Metal and Vulkan too.
///
/// The GPU renderer's test renders [selfTestSvg], accumulating in r32Float,
/// else in r16g16b16a16Float. The format that passes becomes
/// [accumulationFormat], unless [apply] is false. The mesh renderer's test
/// renders it through an affine transform and a projective one. For tests,
/// [fail] names formats to treat as failing, and `mesh` fails the mesh
/// renderer's test.
Future<({bool passed, String detail, bool conclusive})> selfTest(
  RasterizerBackend backend,
  Set<String> fail, {
  bool apply = true,
}) async {
  final where = openGles ? 'OpenGL ES, ' : '';
  if (backend == RasterizerBackend.mesh) {
    String? failure;
    var conclusive = true;
    if (fail.contains('mesh')) {
      failure = 'forced to fail';
    } else {
      final run = _SelfTestRun();
      try {
        failure = await timeoutWhileFramesCanCome(
          _meshSelfTest(run),
          const Duration(seconds: 20),
        );
      } catch (e) {
        run.stopped = true;
        failure = '$e';
        conclusive = false;
      }
    }
    final edges = gpu.gpuContext.doesSupportOffscreenMSAA
        ? '4× multisampled'
        : 'aliased';
    return failure == null
        ? (
            passed: true,
            detail: '${where}self-tested, $edges',
            conclusive: true,
          )
        : (
            passed: false,
            detail: 'self-test failed: $failure',
            conclusive: conclusive,
          );
  }
  final failures = <String>[];
  var conclusive = true;
  for (final format in [
    gpu.PixelFormat.r32Float,
    gpu.PixelFormat.r16g16b16a16Float,
  ]) {
    final String? failure;
    if (fail.contains(format.name)) {
      failure = 'forced to fail';
    } else {
      final run = _SelfTestRun();
      try {
        // The test steps a frame at a time, so it pauses in the background,
        // where the timeout doesn't count.
        failure = await timeoutWhileFramesCanCome(
          _selfTest(format, run),
          const Duration(seconds: 20),
        );
      } catch (e) {
        run.stopped = true;
        failures.add('${format.name}: $e');
        conclusive = false;
        continue;
      }
    }
    if (failure == null) {
      if (apply) {
        accumulationFormat = format;
      }
      return (
        passed: true,
        detail:
            '${where}self-tested, accumulating in ${format.name}'
            '${failures.isEmpty ? '' : ' (${failures.join('; ')})'}',
        conclusive: true,
      );
    }
    failures.add('${format.name}: $failure');
  }
  return (
    passed: false,
    detail: 'self-test failed: ${failures.join('; ')}',
    conclusive: conclusive,
  );
}

/// Renders [selfTestSvg] with curves and without, and reads it back through a
/// canvas.
///
/// Returns null if its pixels are as expected, else the failure.
Future<String?> _selfTest(gpu.PixelFormat format, _SelfTestRun testRun) async {
  await testRun.step();
  final library = await gpu.ShaderLibrary.fromAsset(RasterizerGpu.shaderBundle);
  if (library == null) {
    return "can't load ${RasterizerGpu.shaderBundle}";
  }
  final scene = AtlasScene(
    ra.Scene.fromSvgBytes(Uint8List.fromList(selfTestSvg.codeUnits)),
  );
  AtlasRenderer? renderer;
  try {
    await testRun.step();
    renderer = AtlasRenderer._(library, 1, format);
    // Compiles the renderer's pipeline states one per frame, as on OpenGL ES
    // each blocks the UI thread while it compiles.
    for (var i = 0; i < GpuRenderer.warmUpSteps; i++) {
      await testRun.step();
      renderer._gpu.warmUp(i);
      await SchedulerBinding.instance.endOfFrame;
    }
    for (final curves in [true, false]) {
      await testRun.step();
      final frame = renderer.beginFrame(
        selfTestSize,
        selfTestSize,
        curves: curves,
      );
      final run = frame.addRun()..add(scene, 1, 0, 0, 1, 0, 0);
      frame.render();
      final failure = await _checkRun(run);
      if (failure != null) {
        return '${curves ? 'with' : 'without'} curves, $failure';
      }
    }
    return null;
  } finally {
    renderer?.dispose();
    scene.dispose();
  }
}

/// Renders [selfTestSvg] with a mesh renderer, and reads it back through a
/// canvas.
///
/// It renders through an affine transform, then through a projective one that
/// draws the same. Returns null if the pixels are as expected, else the
/// failure.
Future<String?> _meshSelfTest(_SelfTestRun testRun) async {
  await testRun.step();
  final library = await gpu.ShaderLibrary.fromAsset(RasterizerGpu.shaderBundle);
  if (library == null) {
    return "can't load ${RasterizerGpu.shaderBundle}";
  }
  final scene = parseMeshScene(
    Uint8List.fromList(selfTestSvg.codeUnits),
    selfTestSize.toDouble(),
  );
  MeshRenderer? renderer;
  try {
    await testRun.step();
    // Makes the renderer's pipeline, which on OpenGL ES blocks the UI thread
    // while it compiles.
    renderer = MeshRenderer(library, 1, 4);
    for (final projective in [false, true]) {
      await SchedulerBinding.instance.endOfFrame;
      await testRun.step();
      final frame = renderer.beginFrame(selfTestSize, selfTestSize);
      final run = frame.addRun();
      if (projective) {
        run.addProjective(scene, 2, 0, 0, 2, 0, 0, 0, 0, 2);
      } else {
        run.add(scene, 1, 0, 0, 1, 0, 0);
      }
      frame.render();
      final failure = await _checkRun(run);
      if (failure != null) {
        return '${projective ? 'projective' : 'affine'}, $failure';
      }
    }
    return null;
  } finally {
    renderer?.dispose();
    scene.dispose();
  }
}

/// Reads [run]'s image back through a canvas, and checks it.
///
/// Returns null if its pixels are [selfTestSvg]'s, else the failure.
Future<String?> _checkRun(RasterizerRun run) async {
  if (run.parts.isEmpty) {
    return 'nothing rendered';
  }
  final part = run.parts.first, image = part.image;
  final recorder = ui.PictureRecorder();
  // On OpenGL ES, reading the texture's image directly gives zeros, or an
  // earlier frame's pixels.
  ui.Canvas(
    recorder,
  ).drawImage(image, ui.Offset.zero, ui.Paint()..blendMode = ui.BlendMode.src);
  final picture = recorder.endRecording();
  final ui.Image copy;
  try {
    copy = await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
  }
  final ByteData? data;
  try {
    data = await copy.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    copy.dispose();
  }
  if (data == null) {
    return 'no readback';
  }
  final s = part.source, d = part.destination;
  return checkSelfTest(
    Uint8List.sublistView(data),
    4 * image.width,
    s.left.toInt(),
    s.top.toInt(),
    (d.left.toInt(), d.top.toInt(), d.width.toInt(), d.height.toInt()),
  );
}

/// Parses an SVG's [bytes] into a scene for the GPU renderer.
RasterizerScene parseScene(Uint8List bytes) =>
    AtlasScene(ra.Scene.fromSvgBytes(bytes));

/// Creates a GPU renderer with [slots] frames in flight.
///
/// RasterizerRenderer.create only calls this where the renderer is supported.
/// On OpenGL ES, the switch to it calls this just before it becomes
/// supported.
Future<RasterizerRenderer> createRenderer(int slots) async {
  await _inForeground();
  final library = await gpu.ShaderLibrary.fromAsset(RasterizerGpu.shaderBundle);
  if (library == null) {
    throw StateError(
      'rasterizer_gpu: can\'t load ${RasterizerGpu.shaderBundle}',
    );
  }
  await _inForeground();
  return AtlasRenderer._(library, slots, accumulationFormat);
}

/// Imports an SVG's [bytes] as a scene for the mesh renderer.
///
/// It flattens the curves for the largest size the scene is drawn at: its
/// longer side [maxSize] device pixels.
RasterizerScene parseMeshScene(Uint8List bytes, double maxSize) =>
    MeshScene(ra.Mesh.fromSvgBytes(bytes, maxSize: maxSize));

/// Imports [paths] as a scene for the GPU renderer.
///
/// It flattens them as [ScenePaths.contours] does for [maxSize].
RasterizerScene importPathScene(ScenePaths paths, double maxSize) => AtlasScene(
  ra.Scene.fromPaths(
    paths.contours(maxSize),
    _pathDraws(paths),
    _bounds(paths.viewBox),
  ),
);

/// Imports [paths] as a scene for the mesh renderer.
///
/// It flattens them as [ScenePaths.contours] does for [maxSize].
RasterizerScene importPathMeshScene(ScenePaths paths, double maxSize) =>
    MeshScene(
      ra.Mesh.fromPaths(
        paths.contours(maxSize),
        _pathDraws(paths),
        _bounds(paths.viewBox),
        tolerance: paths.tolerance(maxSize),
        glow: _glow(paths.glow),
      ),
    );

/// [glow] for the core, with its color in sRGB.
ra.Glow? _glow(RasterizerGlow? glow) => glow == null
    ? null
    : ra.Glow(
        radius: glow.radius,
        strength: glow.strength,
        color: glow.color
            ?.withValues(colorSpace: ui.ColorSpace.sRGB)
            .toARGB32(),
        inWidths: glow.inWidths,
      );

ra.Bounds _bounds(ui.Rect r) => ra.Bounds(r.left, r.top, r.right, r.bottom);

/// [paths]' draws for the core: a stroke or a fill each.
List<ra.PathDraw> _pathDraws(ScenePaths paths) => [
  for (final (i, draw) in paths.draws.indexed)
    if (draw.paint.stroke case final stroke?)
      ra.PathDraw(
        path: paths.pathIndices[i],
        color: stroke.color.toARGB32(),
        strokeWidth: stroke.strokeWidth,
        miterLimit: miterLimitOf(stroke),
        cap: stroke.strokeCap,
        join: stroke.strokeJoin,
      )
    else
      ra.PathDraw(
        path: paths.pathIndices[i],
        color: draw.paint.fill!.color.toARGB32(),
        evenOdd: draw.path.fillType == ui.PathFillType.evenOdd,
      ),
];

/// Creates a mesh renderer with [slots] frames in flight.
///
/// Its targets have [samples] per pixel where offscreen MSAA is supported.
/// It's only called where the renderer is supported, as [createRenderer] is.
Future<RasterizerRenderer> createMeshRenderer(int slots, int samples) async {
  await _inForeground();
  final library = await gpu.ShaderLibrary.fromAsset(RasterizerGpu.shaderBundle);
  if (library == null) {
    throw StateError(
      'rasterizer_gpu: can\'t load ${RasterizerGpu.shaderBundle}',
    );
  }
  await _inForeground();
  return MeshRenderer(library, slots, samples);
}

/// Waits as [untilForeground] does, on OpenGL ES only.
///
/// There, Flutter GPU's calls that block the UI thread block it for good in
/// the background. Elsewhere, this completes at once.
Future<void> _inForeground() async {
  if (openGles) {
    await untilForeground();
  }
}

/// One run of a self-test.
///
/// A run that timed out is stopped, so it doesn't go on beside the next run
/// and compete with it for frames.
class _SelfTestRun() {
  /// Whether the run timed out, and so was stopped.
  bool stopped = false;

  /// Waits as [_inForeground] does, before each of the run's steps.
  ///
  /// Then it throws if the run was stopped meanwhile. Nothing reads that
  /// error, as nothing reads the stopped run's result either.
  Future<void> step() async {
    await _inForeground();
    if (stopped) {
      throw StateError('Self-test run stopped after its timeout');
    }
  }
}

/// A scene that the core parsed, for the GPU renderer.
class AtlasScene(final ra.Scene scene) implements RasterizerScene {
  this : bounds = _rect(scene.bounds), viewBox = _viewBox(scene.svgBounds);

  @override
  RasterizerBackend get backend => RasterizerBackend.gpu;

  @override
  final ui.Rect bounds, viewBox;

  @override
  int get pathCount => scene.count;

  @override
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) => throw StateError('A GPU scene has no paths to draw with dart:ui');

  @override
  void dispose() => scene.dispose();

  static ui.Rect _rect(ra.Bounds b) => b.isNull || !b.isRect
      ? ui.Rect.zero
      : ui.Rect.fromLTRB(b.lx, b.ly, b.ux, b.uy);
  static ui.Rect _viewBox(ra.Bounds b) =>
      ui.Rect.fromLTRB(b.lx, b.ly, b.ux, b.uy);
}

/// The GPU renderer.
///
/// Once per frame, it renders all of the frame's runs into atlas pages. Each
/// run then draws as images, from its parts' rectangles there.
///
/// It keeps [slots] frames in flight, each with its own atlas textures. So a
/// frame's images stay valid until [slots] frames later, when its textures
/// are rendered into again.
class AtlasRenderer._(
  gpu.ShaderLibrary library,
  @override final int slots,
  gpu.PixelFormat accumulationFormat,
) implements RasterizerRenderer {
  this
    : _gpu = GpuRenderer(library, accumulationFormat: accumulationFormat),
      _slotPages = List.generate(slots, (_) => []);

  @override
  RasterizerBackend get backend => RasterizerBackend.gpu;

  final GpuRenderer _gpu;
  final ra.Renderer _renderer = ra.Renderer();
  ra.FrameBuffer _buffer = ra.FrameBuffer();
  final ra.SceneList _list = ra.SceneList();
  // Per frame in flight, each page's target. Per page, its depth and
  // accumulation. Both lists have as many pages as [_sizes].
  final List<List<_PageTargets>> _slotPages;
  final List<SharedTargets> _shared = [];
  final AtlasPages _sizes = AtlasPages(maxPageSize);
  int _frames = 0;

  // After a frame whose runs were placed as they ended: the page extents its
  // runs would need, packed together. The next frame's pages grow to these
  // first, as runs placed as they end go onto pages that already exist.
  List<(int, int)> _planned = const [];

  @override
  int get maxViewportSize => maxPageSize;

  @override
  int get atlasResizes => _sizes.resizes;

  @override
  int get atlasBytes {
    int bytes(gpu.Texture? texture) =>
        texture?.getBaseMipLevelSizeInBytes() ?? 0;
    var n = 0;
    for (final slot in _slotPages) {
      for (final page in slot) {
        n += bytes(page.targets.target);
      }
    }
    for (final shared in _shared) {
      n += bytes(shared.depth) + bytes(shared.accumulation);
    }
    return n;
  }

  @override
  void trimAtlas() {
    if (_disposed) {
      return;
    }
    // A frame being built may have placed runs on its pages already, so the
    // trim waits until it renders.
    if (_frame._open) {
      _trimPending = true;
      return;
    }
    _sizes.trim();
    _release();
  }

  bool _trimPending = false;

  /// Adds texture holders for every page that [_sizes] has, and drops those of
  /// the pages it released.
  void _keepPages() {
    final n = _sizes.length;
    while (_shared.length < n) {
      _shared.add(SharedTargets());
    }
    for (final slot in _slotPages) {
      while (slot.length < n) {
        slot.add(_PageTargets());
      }
    }
    _release();
  }

  /// Drops the texture holders of the pages that [_sizes] released.
  void _release() {
    final n = _sizes.length;
    if (_shared.length > n) {
      _shared.length = n;
    }
    for (final slot in _slotPages) {
      if (slot.length > n) {
        slot.length = n;
      }
    }
  }

  bool _disposed = false;

  /// Called with each atlas page's frame, as the core wrote it, before it's
  /// uploaded.
  ///
  /// For tools that check frames.
  void Function(int page, ra.Frame frame)? debugFrameWritten;

  /// Whether to write each frame into a new, zeroed buffer, and upload it
  /// through a new staging buffer and data texture.
  ///
  /// Reused ones hold an earlier frame's bytes past the frame's own. Fresh ones
  /// check that the shaders read only what the core writes.
  bool debugFreshFrameBuffers = false;

  late final AtlasFrame _frame = AtlasFrame._(this);

  @override
  AtlasFrame beginFrame(int width, int height, {bool curves = true}) {
    if (_disposed) {
      throw StateError('RasterizerRenderer disposed');
    }
    final maxSize = maxPageSize;
    if (width <= 0 || height <= 0 || width > maxSize || height > maxSize) {
      throw ArgumentError(
        'Invalid viewport size $width×$height, which must be within '
        '$maxSize×$maxSize',
      );
    }
    return _frame.._begin(width, height, curves);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _frame._dispose();
    _list.dispose();
    _buffer.dispose();
    _renderer.dispose();
    for (final slot in _slotPages) {
      for (final page in slot) {
        page._dispose();
      }
      slot.clear();
    }
    _shared.clear();
  }
}

/// A frame of the GPU renderer.
///
/// [render] renders its runs' entries into atlas pages.
class AtlasFrame._(final AtlasRenderer _renderer) implements RasterizerFrame {
  final List<AtlasRun> _runs = [];
  int _runCount = 0;
  int _width = 0, _height = 0, _slot = 0;
  bool _curves = true, _rendered = false;

  // The margin around each entry's bounds, for miters and antialiasing, and
  // the gap between parts in the atlas, so filtering never reads a
  // neighbour.
  static const _margin = 2, _gap = 1;

  // For placing runs as they end: how many were placed, the sizes and images
  // of the pages used so far, and the shelf being filled.
  int _placedCount = 0;
  final List<(int, int)> _placedSizes = [];
  final List<ui.Image> _placedImages = [];
  int _placePage = 0, _placeX = 0, _placeY = 0, _placeShelf = 0;

  // The entries, in the order they were added. Per entry: its scene, its
  // transform (6 doubles: a b c d tx ty), its opacity, its color transform
  // (0, or 1 + its index in [_colorTransforms]) and its run's index. Then its
  // rectangle in the viewport (4 ints: lx ly ux uy): its bounds with the
  // margin, rounded out and clipped to the viewport. Then the next of its
  // run's entries with a rectangle, or -1, and its part, or -1.
  final List<ra.Scene> _scenes = [];
  Float64List _ctms = Float64List(6 * 256);
  Float32List _opacities = Float32List(256);
  Int32List _entryColors = Int32List(256);
  Int32List _entryRuns = Int32List(256);
  Int32List _entryRects = Int32List(4 * 256);
  Int32List _entryNext = Int32List(256);
  Int32List _entryParts = Int32List(256);

  // The runs' parts, 7 ints each: page (-1 until placed), atlas x y, viewport
  // x y, width and height.
  Int32List _parts = Int32List(7 * 64);
  int _partCount = 0;

  // Groups a run's entries into parts, with its list of their ids.
  final AtlasParts _grouper = AtlasParts();
  final List<int> _groupIds = [];

  // The entries' color transforms, each once, and their indices.
  final List<RasterizerColorTransform> _colorTransforms = [];
  final Map<RasterizerColorTransform, int> _colorIds = Map.identity();

  // Native memory: the RaListEntry structs, rewritten for each page, and the
  // color transforms' matrices.
  Pointer<Uint8> _native = nullptr;
  int _nativeCapacity = 0;
  Pointer<Float> _nativeMatrices = nullptr;
  int _nativeMatricesCapacity = 0;

  @override
  int cpuMicros = 0, uploadMicros = 0, encodeMicros = 0;

  @override
  final List<(int, int)> pageSizes = [];

  @override
  int get width => _width;
  @override
  int get height => _height;
  @override
  int get entryCount => _scenes.length;

  @override
  Iterable<AtlasRun> get runs => _runs.take(_runCount);

  void _begin(int width, int height, bool curves) {
    final renderer = _renderer;
    _width = width;
    _height = height;
    _curves = curves;
    _rendered = false;
    _runCount = 0;
    _partCount = 0;
    _scenes.clear();
    _colorTransforms.clear();
    _colorIds.clear();
    _slot = renderer._frames++ % renderer.slots;
    _placedCount = _placePage = _placeX = _placeY = _placeShelf = 0;
    _placedSizes.clear();
    _placedImages.clear();
    final planned = renderer._planned;
    for (var p = 0; p < planned.length && p < renderer._sizes.length; p++) {
      renderer._sizes.fit(p, planned[p].$1, planned[p].$2);
    }
    renderer._planned = const [];
  }

  @override
  RasterizerBackend get backend => RasterizerBackend.gpu;

  @override
  AtlasRun addRun() {
    _checkOpen();
    if (_runCount == _runs.length) {
      _runs.add(AtlasRun._(this, _runCount));
    }
    return _runs[_runCount++].._reset();
  }

  void _add(
    AtlasRun run,
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
    double opacity,
    RasterizerColorTransform? colorTransform,
  ) {
    _checkOpen();
    if (run._placed) {
      throw StateError('RasterizerRun already placed');
    }
    scene = resolveScene(scene, RasterizerBackend.gpu);
    if (scene is! AtlasScene) {
      throw ArgumentError.value(
        scene,
        'scene',
        'Not a scene for the GPU renderer',
      );
    }
    if (!(opacity > 0)) {
      return;
    }
    final i = _scenes.length;
    if (i == _entryRuns.length) {
      _ctms = Float64List(_ctms.length * 2)..setAll(0, _ctms);
      _opacities = Float32List(_opacities.length * 2)..setAll(0, _opacities);
      _entryColors = Int32List(_entryColors.length * 2)
        ..setAll(0, _entryColors);
      _entryRuns = Int32List(_entryRuns.length * 2)..setAll(0, _entryRuns);
      _entryRects = Int32List(_entryRects.length * 2)..setAll(0, _entryRects);
      _entryNext = Int32List(_entryNext.length * 2)..setAll(0, _entryNext);
      _entryParts = Int32List(_entryParts.length * 2)..setAll(0, _entryParts);
    }
    _entryParts[i] = -1;
    _opacities[i] = opacity < 1 ? opacity : 1;
    _entryColors[i] = colorTransform == null
        ? 0
        : _colorIds[colorTransform] ??=
              (_colorTransforms..add(colorTransform)).length;
    _scenes.add(scene.scene);
    _ctms
      ..[6 * i] = a
      ..[6 * i + 1] = b
      ..[6 * i + 2] = c
      ..[6 * i + 3] = d
      ..[6 * i + 4] = tx
      ..[6 * i + 5] = ty;
    _entryRuns[i] = run.index;
    final r = scene.bounds;
    if (r.isEmpty) {
      return;
    }
    // The bounds' corners through the transform, in the viewport.
    final x0 = a * r.left + c * r.top + tx, y0 = b * r.left + d * r.top + ty;
    final dxw = a * r.width,
        dyw = b * r.width,
        dxh = c * r.height,
        dyh = d * r.height;
    final minX = x0 + (dxw < 0 ? dxw : 0) + (dxh < 0 ? dxh : 0),
        maxX = x0 + (dxw > 0 ? dxw : 0) + (dxh > 0 ? dxh : 0);
    final minY = y0 + (dyw < 0 ? dyw : 0) + (dyh < 0 ? dyh : 0),
        maxY = y0 + (dyw > 0 ? dyw : 0) + (dyh > 0 ? dyh : 0);
    if (minX < run._lx) {
      run._lx = minX;
    }
    if (minY < run._ly) {
      run._ly = minY;
    }
    if (maxX > run._ux) {
      run._ux = maxX;
    }
    if (maxY > run._uy) {
      run._uy = maxY;
    }
    // Its rectangle, clamped first, as huge bounds don't round to ints.
    if (!(minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite)) {
      return;
    }
    const out = 2.0 * _margin;
    final w = _width + out, h = _height + out;
    final lx = (minX.clamp(-out, w).floor() - _margin).clamp(0, _width),
        ly = (minY.clamp(-out, h).floor() - _margin).clamp(0, _height);
    final ux = (maxX.clamp(-out, w).ceil() + _margin).clamp(0, _width),
        uy = (maxY.clamp(-out, h).ceil() + _margin).clamp(0, _height);
    if (ux <= lx || uy <= ly) {
      return;
    }
    _entryRects
      ..[4 * i] = lx
      ..[4 * i + 1] = ly
      ..[4 * i + 2] = ux
      ..[4 * i + 3] = uy;
    _entryNext[i] = -1;
    if (run._last >= 0) {
      _entryNext[run._last] = i;
    } else {
      run._first = i;
    }
    run._last = i;
  }

  @override
  void render() {
    _checkOpen();
    _rendered = true;
    final renderer = _renderer;
    final watch = Stopwatch()..start();
    cpuMicros = uploadMicros = encodeMicros = 0;
    pageSizes.clear();

    final slot = renderer._slotPages[_slot];
    final List<(int, int)> sizes;
    List<(int, int)>? pageExtents;
    if (_placedCount == 0) {
      // No run was placed as it ended: packs them all together, onto pages
      // sized to fit.
      final extents = pageExtents = _pack(assign: true);
      sizes = [
        for (var p = 0; p < extents.length; p++)
          renderer._sizes.fit(p, extents[p].$1, extents[p].$2),
      ];
      renderer._keepPages();
    } else {
      // Some runs were placed as they ended, onto pages at their sizes when
      // first used. Places the rest now.
      for (final run in runs) {
        if (!run._placed) {
          _place(run);
        }
      }
      sizes = _placedSizes;
    }

    renderer._gpu.beginFrame();
    final images = <ui.Image>[];
    for (var p = 0; p < sizes.length; p++) {
      final (tw, th) = sizes[p];
      pageSizes.add((tw, th));
      _writeEntries(p, th);
      renderer._list.params = ra.Params(useCurves: _curves, clearColor: 0);
      if (renderer.debugFreshFrameBuffers) {
        renderer._buffer.dispose();
        renderer._buffer = ra.FrameBuffer();
        slot[p].targets
          ..data = null
          ..staging = null;
      }
      final frame = renderer._renderer.render(
        renderer._list,
        tw.toDouble(),
        th.toDouble(),
        1,
        renderer._buffer,
      );
      cpuMicros += watch.elapsedMicroseconds;
      renderer.debugFrameWritten?.call(p, frame);
      final texture = renderer._gpu.render(
        frame,
        slot[p].targets,
        renderer._shared[p],
        tw,
        th,
      );
      uploadMicros += renderer._gpu.uploadMicros;
      encodeMicros += renderer._gpu.encodeMicros;
      images.add(slot[p].image(texture));
      watch.reset();
    }
    for (final run in runs) {
      run._setParts(images);
    }
    // What the runs needed, packed together, for AtlasPages.endFrame. When
    // runs were placed as they ended, the next frame's pages grow to it too.
    final needs = pageExtents ?? (renderer._planned = _pack(assign: false));
    renderer._sizes.endFrame(_width, _height, needs);
    renderer._release();
    if (renderer._trimPending) {
      renderer._trimPending = false;
      renderer.trimAtlas();
    }
    cpuMicros += watch.elapsedMicroseconds;
    onGpuFrame?.call();
  }

  /// Groups [run]'s entries into parts, once, with [AtlasParts].
  void _group(AtlasRun run) {
    if (run._grouped) {
      return;
    }
    run._grouped = true;
    run._partStart = _partCount;
    final ids = _groupIds..clear();
    for (var i = run._first; i >= 0; i = _entryNext[i]) {
      ids.add(i);
    }
    _grouper.group(_entryRects, ids, _addPart, _setPart);
    run._partCount = _partCount - run._partStart;
  }

  /// Adds a part, not placed yet, at the viewport rectangle [lx], [ly], [ux],
  /// [uy], and returns its index.
  int _addPart(int lx, int ly, int ux, int uy) {
    final q = _partCount++;
    if (7 * _partCount > _parts.length) {
      _parts = Int32List(_parts.length * 2)..setAll(0, _parts);
    }
    _parts
      ..[7 * q] = -1
      ..[7 * q + 1] = 0
      ..[7 * q + 2] = 0
      ..[7 * q + 3] = lx
      ..[7 * q + 4] = ly
      ..[7 * q + 5] = ux - lx
      ..[7 * q + 6] = uy - ly;
    return q;
  }

  void _setPart(int i, int q) => _entryParts[i] = q;

  /// [run]'s parts, tallest first, the order they're placed in.
  List<int> _tallestFirst(AtlasRun run) {
    final start = run._partStart;
    final parts = [for (var q = start; q < start + run._partCount; q++) q];
    if (parts.length > 1) {
      parts.sort((a, b) => _parts[7 * b + 6] - _parts[7 * a + 6]);
    }
    return parts;
  }

  /// Packs the runs' parts onto shelves, and returns the pages' extents.
  ///
  /// Parts go in run order, each run's tallest first. When a page is full, a
  /// new one starts. With [assign], the parts are placed where they're packed.
  ///
  /// A shelf is about as wide as the side of a square with the parts' area,
  /// rounded up to [RasterizerRenderer.atlasStep], and at least as wide as the
  /// widest part. So a page's area is about the parts', rather than as wide
  /// as the viewport.
  List<(int, int)> _pack({required bool assign}) {
    final maxSize = maxPageSize;
    var area = 0, widest = 0;
    for (final run in runs) {
      _group(run);
      for (var q = run._partStart; q < run._partStart + run._partCount; q++) {
        final w = _parts[7 * q + 5], h = _parts[7 * q + 6];
        area += (w + _gap) * (h + _gap);
        if (w > widest) {
          widest = w;
        }
      }
    }
    const step = RasterizerRenderer.atlasStep;
    final side = (math.sqrt(area).ceil() + step - 1) ~/ step * step;
    final shelfWidth = math.max(widest, math.min(side, maxSize));
    var page = 0, x = 0, y = 0, shelfHeight = 0, pageWidth = 0, pageHeight = 0;
    final pageExtents = <(int, int)>[];
    for (final run in runs) {
      for (final q in _tallestFirst(run)) {
        final w = _parts[7 * q + 5], h = _parts[7 * q + 6];
        if (x > 0 && x + w > shelfWidth) {
          x = 0;
          y += shelfHeight + _gap;
          shelfHeight = 0;
        }
        if (y > 0 && y + h > maxSize) {
          pageExtents.add((pageWidth, pageHeight));
          page++;
          x = y = shelfHeight = pageWidth = pageHeight = 0;
        }
        if (assign) {
          _parts
            ..[7 * q] = page
            ..[7 * q + 1] = x
            ..[7 * q + 2] = y;
        }
        x += w + _gap;
        if (h > shelfHeight) {
          shelfHeight = h;
        }
        if (x - _gap > pageWidth) {
          pageWidth = x - _gap;
        }
        if (y + h > pageHeight) {
          pageHeight = y + h;
        }
      }
    }
    if (pageWidth > 0) {
      pageExtents.add((pageWidth, pageHeight));
    }
    return pageExtents;
  }

  /// Places [run]'s parts, tallest first, after the parts placed so far.
  ///
  /// They go on the current page's shelves, as wide as the page, else on the
  /// next page. Pages keep the sizes that [_begin] gave them from the last
  /// frame's needs. A page that's new, or too small for a part, grows before
  /// its first part goes on it. That's safe, as no image of the page has been
  /// handed out yet this frame.
  void _place(AtlasRun run) {
    run._placed = true;
    _placedCount++;
    _group(run);
    for (final q in _tallestFirst(run)) {
      final w = _parts[7 * q + 5], h = _parts[7 * q + 6];
      while (true) {
        final (tw, th) = _placedPage(_placePage, w, h);
        var x = _placeX, y = _placeY, shelf = _placeShelf;
        if (x > 0 && x + w > tw) {
          x = 0;
          y += shelf + _gap;
          shelf = 0;
        }
        if (x + w <= tw && y + h <= th) {
          _parts
            ..[7 * q] = _placePage
            ..[7 * q + 1] = x
            ..[7 * q + 2] = y;
          _placeX = x + w + _gap;
          _placeY = y;
          _placeShelf = h > shelf ? h : shelf;
          break;
        }
        _placePage++;
        _placeX = _placeY = _placeShelf = 0;
      }
    }
    run._setParts(_placedImages);
  }

  /// Page [p]'s size this frame, fixed once the page is used.
  ///
  /// When the frame first uses the page, this grows it to fit a [w] x [h]
  /// part, and hands out its image.
  (int, int) _placedPage(int p, int w, int h) {
    if (p < _placedSizes.length) {
      return _placedSizes[p];
    }
    final renderer = _renderer, sizes = renderer._sizes;
    // A page that no earlier frame sized is at least the viewport's size, so
    // a first frame's runs don't spread over many pages. It shrinks to what
    // frames need once a window of them is done.
    final size = p == sizes.length
        ? sizes.fit(p, w > _width ? w : _width, h > _height ? h : _height)
        : sizes.fit(p, w, h);
    renderer._keepPages();
    final targets = renderer._slotPages[_slot][p];
    _placedSizes.add(size);
    _placedImages.add(
      targets.image(
        renderer._gpu.target(
          targets.targets,
          renderer._shared[p],
          size.$1,
          size.$2,
        ),
      ),
    );
    return size;
  }

  /// Writes the entries of the parts on [page] as RaListEntry structs, and
  /// sets them as the list's, along with the color transforms' matrices.
  ///
  /// The page's texture is [textureHeight] high. Each entry's transform is
  /// followed by its part's move from the viewport to its atlas rectangle, in
  /// the core's device space, where y is up:
  /// x' = x - vx + ax, y' = textureHeight - (y - vy + ay). The entry's device
  /// clip is that rectangle.
  void _writeEntries(int page, int textureHeight) {
    final count = _scenes.length;
    if (count > _nativeCapacity) {
      if (_native != nullptr) {
        calloc.free(_native);
      }
      _nativeCapacity = count < 256 ? 256 : count * 2;
      _native = calloc<Uint8>(_nativeCapacity * ra.SceneList.entrySize);
    }
    final bytes = _native
        .asTypedList(_nativeCapacity * ra.SceneList.entrySize)
        .buffer
        .asByteData();
    final colors = _colorTransforms.length;
    if (colors > _nativeMatricesCapacity) {
      if (_nativeMatrices != nullptr) {
        calloc.free(_nativeMatrices);
      }
      _nativeMatricesCapacity = colors < 16 ? 16 : colors * 2;
      _nativeMatrices = calloc<Float>(16 * _nativeMatricesCapacity);
    }
    if (colors > 0) {
      final matrices = _nativeMatrices.asTypedList(16 * colors);
      for (var j = 0; j < colors; j++) {
        matrices.setAll(16 * j, _colorTransforms[j].values);
      }
    }
    _renderer._list.setColorMatrices(_nativeMatrices, colors);
    var n = 0;
    for (var i = 0; i < count; i++) {
      final q = _entryParts[i];
      if (q < 0 || _parts[7 * q] != page) {
        continue;
      }
      final ax = _parts[7 * q + 1], ay = _parts[7 * q + 2];
      final vx = _parts[7 * q + 3], vy = _parts[7 * q + 4];
      final w = _parts[7 * q + 5], h = _parts[7 * q + 6];
      final ox = (ax - vx).toDouble(),
          oy = (textureHeight - ay + vy).toDouble();
      final o = n++ * ra.SceneList.entrySize, k = 6 * i;
      bytes
        ..setInt64(o, _scenes[i].address, Endian.host)
        ..setFloat32(o + ra.SceneList.entryCtm, _ctms[k], Endian.host)
        ..setFloat32(o + ra.SceneList.entryCtm + 4, -_ctms[k + 1], Endian.host)
        ..setFloat32(o + ra.SceneList.entryCtm + 8, _ctms[k + 2], Endian.host)
        ..setFloat32(o + ra.SceneList.entryCtm + 12, -_ctms[k + 3], Endian.host)
        ..setFloat32(
          o + ra.SceneList.entryCtm + 16,
          _ctms[k + 4] + ox,
          Endian.host,
        )
        ..setFloat32(
          o + ra.SceneList.entryCtm + 20,
          oy - _ctms[k + 5],
          Endian.host,
        )
        ..setFloat32(
          o + ra.SceneList.entryDeviceClip,
          ax.toDouble(),
          Endian.host,
        )
        ..setFloat32(
          o + ra.SceneList.entryDeviceClip + 4,
          (textureHeight - ay - h).toDouble(),
          Endian.host,
        )
        ..setFloat32(
          o + ra.SceneList.entryDeviceClip + 8,
          (ax + w).toDouble(),
          Endian.host,
        )
        ..setFloat32(
          o + ra.SceneList.entryDeviceClip + 12,
          (textureHeight - ay).toDouble(),
          Endian.host,
        )
        ..setFloat32(o + ra.SceneList.entryOpacity, _opacities[i], Endian.host)
        ..setUint32(
          o + ra.SceneList.entryColorMatrix,
          _entryColors[i],
          Endian.host,
        );
    }
    _renderer._list.setEntries(_native, n);
  }

  /// The transform the core draws entry [i] with, and its device clip, as the
  /// last [render] wrote them, rounded to floats.
  ///
  /// The transform is a b c d tx ty in device space, and the clip lx ly ux uy.
  /// Null before [render], or for an entry in no part. For tools that render
  /// the same list natively.
  (List<double>, List<double>)? coreEntry(int i) {
    final q = _entryParts[i];
    if (!_rendered || q < 0 || _parts[7 * q] < 0) {
      return null;
    }
    final th = pageSizes[_parts[7 * q]].$2;
    final ax = _parts[7 * q + 1], ay = _parts[7 * q + 2];
    final vx = _parts[7 * q + 3], vy = _parts[7 * q + 4];
    final w = _parts[7 * q + 5], h = _parts[7 * q + 6];
    final ox = (ax - vx).toDouble(), oy = (th - ay + vy).toDouble(), k = 6 * i;
    final f = Float32List.fromList([
      _ctms[k],
      -_ctms[k + 1],
      _ctms[k + 2],
      -_ctms[k + 3],
      _ctms[k + 4] + ox,
      oy - _ctms[k + 5],
    ]);
    final clip = Float32List.fromList([
      ax.toDouble(),
      (th - ay - h).toDouble(),
      (ax + w).toDouble(),
      (th - ay).toDouble(),
    ]);
    return (f.toList(), clip.toList());
  }

  /// Entry [i]'s run index and page, after [render].
  ///
  /// The page is -1 if the entry is on none.
  (int, int) entryRun(int i) {
    final q = _entryParts[i];
    return (_entryRuns[i], q < 0 ? -1 : _parts[7 * q]);
  }

  bool get _open => _width > 0 && !_rendered;

  void _checkOpen() {
    if (_renderer._disposed) {
      throw StateError('RasterizerRenderer disposed');
    }
    if (_rendered) {
      throw StateError('RasterizerFrame already rendered: begin a new one');
    }
  }

  void _dispose() {
    if (_native != nullptr) {
      calloc.free(_native);
    }
    _native = nullptr;
    if (_nativeMatrices != nullptr) {
      calloc.free(_nativeMatrices);
    }
    _nativeMatrices = nullptr;
    _nativeMatricesCapacity = 0;
    _nativeCapacity = 0;
  }
}

/// A run of the GPU renderer, drawn as images, from its parts' rectangles in
/// the frame's atlas pages.
class AtlasRun._(final AtlasFrame _frame, @override final int index)
    extends ImageRun {
  // Its entries' bounds in the viewport, its first and last entries with a
  // rectangle, or -1, and once grouped, the range of its parts among the
  // frame's.
  double _lx = double.infinity,
      _ly = double.infinity,
      _ux = double.negativeInfinity,
      _uy = double.negativeInfinity;
  int _first = -1, _last = -1, _partStart = 0, _partCount = 0;
  bool _grouped = false, _placed = false;

  @override
  List<RasterizerRunPart> parts = const [];

  @override
  bool get isEmpty => _grouped ? _partCount == 0 : !_lx.isFinite;

  void _reset() {
    _lx = _ly = double.infinity;
    _ux = _uy = double.negativeInfinity;
    _first = _last = -1;
    _partStart = _partCount = 0;
    _grouped = _placed = false;
    parts = const [];
  }

  @override
  void place() {
    _frame._checkOpen();
    if (!_placed) {
      _frame._place(this);
    }
  }

  /// Sets [parts] from its placed parts, with the pages' [images].
  void _setParts(List<ui.Image> images) {
    final p = _frame._parts;
    parts = [
      for (var q = _partStart; q < _partStart + _partCount; q++)
        if (p[7 * q] >= 0)
          RasterizerRunPart(
            p[7 * q],
            images[p[7 * q]],
            ui.Rect.fromLTWH(
              p[7 * q + 1].toDouble(),
              p[7 * q + 2].toDouble(),
              p[7 * q + 5].toDouble(),
              p[7 * q + 6].toDouble(),
            ),
            ui.Rect.fromLTWH(
              p[7 * q + 3].toDouble(),
              p[7 * q + 4].toDouble(),
              p[7 * q + 5].toDouble(),
              p[7 * q + 6].toDouble(),
            ),
          ),
    ];
  }

  @override
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
  }) => _frame._add(this, scene, a, b, c, d, tx, ty, opacity, colorTransform);

  /// [add], for affine transforms only: g and h must be 0.
  ///
  /// w is then the constant i, which divides the rest.
  @override
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
  }) {
    if (g != 0 || h != 0) {
      throw ArgumentError(
        'The GPU renderer only draws affine transforms: g and h must be 0',
      );
    }
    // Where w isn't positive, the whole scene is behind the eye. Added with
    // no opacity, it's still checked, but not drawn.
    final s = 1 / i;
    _frame._add(
      this,
      scene,
      a * s,
      b * s,
      c * s,
      d * s,
      tx * s,
      ty * s,
      i > 0 ? opacity : 0,
      colorTransform,
    );
  }
}

/// A frame in flight's textures for one atlas page, and the image of its
/// target.
class _PageTargets() {
  final RenderTargets targets = RenderTargets();
  gpu.Texture? _texture;
  ui.Image? _image;

  /// The image of [texture], made again only when the texture changed.
  ui.Image image(gpu.Texture texture) {
    if (!identical(texture, _texture)) {
      _texture = texture;
      // The replaced image was this page's in the last frame of this frame in
      // flight, slots frames ago. RasterizerRunPart.image is valid only until
      // now. A picture that drew it keeps its own reference.
      _image?.dispose();
      _image = texture.asImage();
    }
    return _image!;
  }

  void _dispose() {
    _image?.dispose();
    _image = null;
    _texture = null;
  }
}
