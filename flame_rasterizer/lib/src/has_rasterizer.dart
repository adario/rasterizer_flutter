import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' show World;
import 'package:flame/game.dart';
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/rasterizer_path_component.dart';
import 'package:flame_rasterizer/src/rasterizer_polygons_component.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart' show RasterizerSvg;
import 'package:flame_rasterizer/src/shared_scenes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show MediaQuery;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Draws a game's [RasterizerSvg]s, [RasterizerPathComponent]s and
/// [RasterizerPolygonsComponent]s with rasterizer_gpu.
///
/// While the game draws its component tree, the mixin wraps the game's canvas
/// in a [RasterizerCanvas]. That canvas adds the vector content to the
/// renderer's frame in runs: consecutive draws that the renderer batches
/// together. After the tree is drawn, and before Flutter rasterizes the
/// painting, the mixin renders the frame once. The mesh renderer renders each
/// run into an image of its own, and the atlas renderer renders all runs into
/// an atlas. The canvas renderer has nothing left to render, because it draws
/// each run's paths straight into the game's canvas.
///
/// The game creates its renderer when it's first drawn, or when
/// [rasterizerReady] is first read, such as in `onLoad`. It creates the
/// [rasterizerGpu] renderer when that's supported, or else the canvas
/// renderer, the same choice that [RasterizerSvg] makes for its imports.
/// Until the renderer is ready, vector content drawn into the game's canvas
/// draws nothing.
///
/// On OpenGL ES, creating a GPU renderer compiles its shaders, which takes up
/// to a second ([RasterizerGpu.allowOpenGles]). [rasterizerReady] completes
/// after that, so a game that awaits it in `onLoad` shows `GameWidget`'s
/// `loadingBuilder` in the meantime.
///
/// When the game is larger than the renderer's largest viewport
/// ([RasterizerRenderer.maxViewportSize] per side), such as a window over
/// 4096 device pixels wide on OpenGL ES, the renderer draws the vectors at a
/// lower resolution that fits. Their images then scale up and look a little
/// softer.
///
/// It works on a [FlameGame] with any world [W], such as a `Forge2DGame`.
/// Dart infers [W] from the game's class, so `with HasRasterizer` is enough.
mixin HasRasterizer<W extends World> on FlameGame<W> {
  RasterizerRenderer? _renderer;
  final RasterizerCanvas _canvas = RasterizerCanvas();

  /// How many frames the renderer keeps in flight, at least 1.
  ///
  /// It's passed to [RasterizerRenderer.create] as `slots`. Each frame in
  /// flight has its own atlas pages or run targets, and costs their memory.
  /// A frame's images stay valid until that many frames later. 2 are enough,
  /// unless the app captures the game's frames after they're drawn, such as
  /// with `RepaintBoundary.toImage`: then it needs 3. The game reads this
  /// once, when it creates the renderer.
  int get rasterizerSlots => 2;

  /// The GPU renderer to draw with when it's supported; otherwise the canvas
  /// renderer draws.
  ///
  /// By default it's [RasterizerBackend.mesh], the mesh renderer, which
  /// imports each SVG once into triangles. [RasterizerBackend.gpu] picks the
  /// atlas renderer, which rasterizes the SVGs each frame. The game's
  /// [RasterizerSvg]s must be loaded for the same renderer
  /// ([RasterizerSvg.load]'s `gpu`). Drawing one loaded for the other
  /// renderer throws. The game reads this once, when it creates the renderer.
  RasterizerBackend get rasterizerGpu => RasterizerBackend.mesh;

  /// The mesh renderer's samples per pixel, 4 or 1.
  ///
  /// It's passed to [RasterizerRenderer.create] as `meshSamples`. With 4, the
  /// renderer antialiases edges where offscreen MSAA is supported. With 1,
  /// edges are aliased, which costs the GPU less. The game reads this once,
  /// when it creates the renderer.
  int get rasterizerMeshSamples => 4;

  /// Whether the atlas renderer draws curves as quadratics rather than as
  /// line segments.
  ///
  /// The mesh renderer ignores it, as it flattens curves once, when the SVGs
  /// are loaded.
  bool rasterizerCurves = true;

  /// The renderer, or null until it's ready.
  RasterizerRenderer? get rasterizer => _renderer;

  /// The last frame drawn, with its runs, entries, timings and atlas pages.
  ///
  /// The renderer reuses one frame object, so during the game's render this
  /// is the frame in progress. It stays valid until the next frame begins,
  /// and is null after the game is removed.
  RasterizerFrame? get rasterizerFrame => _lastFrame;
  RasterizerFrame? _lastFrame;

  /// Completes with the renderer when it can draw, which on OpenGL ES is
  /// after its shaders have compiled.
  ///
  /// If the game is removed in the meantime, it completes with a renderer
  /// that's already disposed of. If [rasterizerSlots] or
  /// [rasterizerMeshSamples] has a value that [RasterizerRenderer.create]
  /// rejects, reading this throws an [ArgumentError] right away, and so does
  /// every frame the game draws.
  Future<RasterizerRenderer> get rasterizerReady {
    if (_creating == null) {
      _checkSettings();
    }
    return _creating ??= _create();
  }

  Future<RasterizerRenderer>? _creating;

  // Checks the settings as RasterizerRenderer.create does, but synchronously.
  // Otherwise create's future would fail, and nothing awaits it while the
  // game draws.
  void _checkSettings() {
    final slots = rasterizerSlots;
    if (slots < 1) {
      throw ArgumentError.value(slots, 'rasterizerSlots', 'At least 1');
    }
    final samples = rasterizerMeshSamples;
    if (samples != 1 && samples != 4) {
      throw ArgumentError.value(
        samples,
        'rasterizerMeshSamples',
        'Either 1 or 4',
      );
    }
  }

  // How many times the game was removed. _create disposes of a renderer whose
  // creation finishes after a removal, so that a game that isn't drawn
  // doesn't keep it.
  int _removals = 0;

  Future<RasterizerRenderer> _create() async {
    final removals = _removals;
    final gpu = rasterizerGpu;
    final state = RasterizerGpu.of(gpu);
    final support = state.support;
    // Not in release builds, whose users can't act on it.
    if (support != RasterizerSupport.supported && !kReleaseMode) {
      final detail = state.supportDetail;
      debugPrint(
        "flame_rasterizer: rasterizer_gpu's "
        '${gpu == RasterizerBackend.mesh ? 'mesh' : 'atlas'} renderer is '
        'unsupported here (${support.name}${detail == null ? '' : ': $detail'}'
        '), so its canvas renderer draws',
      );
    }
    final renderer = await RasterizerRenderer.create(
      slots: rasterizerSlots,
      gpu: gpu,
      meshSamples: rasterizerMeshSamples,
    );
    if (support == RasterizerSupport.supported &&
        state.support == RasterizerSupport.warmUpTimeout &&
        !kReleaseMode) {
      debugPrint(
        "flame_rasterizer: rasterizer_gpu's "
        '${gpu == RasterizerBackend.mesh ? 'mesh' : 'atlas'} renderer timed '
        'out (${state.supportDetail}), so its canvas renderer draws',
      );
    }
    if (removals != _removals) {
      renderer.dispose();
      return renderer;
    }
    return _renderer = renderer;
  }

  @override
  void render(Canvas canvas) {
    final renderer = _renderer;
    var pixelRatio = _pixelRatio();
    var w = (canvasSize.x * pixelRatio).ceil();
    var h = (canvasSize.y * pixelRatio).ceil();
    if (renderer == null || w <= 0 || h <= 0) {
      rasterizerReady;
      final outer = unreadyCanvas;
      unreadyCanvas = canvas;
      try {
        super.render(canvas);
      } finally {
        unreadyCanvas = outer;
      }
      return;
    }
    // When the canvas is larger than the renderer's largest viewport, such as
    // a window over 4096 pixels wide on OpenGL ES, the vectors render at a
    // lower pixel ratio that fits. Their images are then scaled up and
    // smoothed.
    final maxSize = renderer.maxViewportSize;
    var filterQuality = FilterQuality.none;
    if (maxSize != null && (w > maxSize || h > maxSize)) {
      pixelRatio *= maxSize / math.max(w, h);
      w = math.min(maxSize, (canvasSize.x * pixelRatio).ceil());
      h = math.min(maxSize, (canvasSize.y * pixelRatio).ceil());
      filterQuality = FilterQuality.low;
    }
    final frame = renderer.beginFrame(w, h, curves: rasterizerCurves);
    _canvas.begin(canvas, frame, pixelRatio, filterQuality: filterQuality);
    try {
      super.render(_canvas);
    } finally {
      // Render the frame even if a component threw, because the canvas
      // already holds the images of the runs that ended before the error.
      _canvas.end();
      frame.render();
      _lastFrame = frame;
    }
  }

  // The device pixel ratio of the game's view, read each frame. It reads
  // MediaQuery without depending on it, because a dependency taken during
  // paint would make the game widget rebuild.
  double _pixelRatio() =>
      buildContext
          ?.getInheritedWidgetOfExactType<MediaQuery>()
          ?.data
          .devicePixelRatio ??
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
      1;

  /// Disposes of the renderer and releases the imports of the game's
  /// [RasterizerPathComponent]s and [RasterizerPolygonsComponent]s.
  ///
  /// If the game is drawn again, the components import their paths and
  /// polygons again.
  @override
  void onRemove() {
    releaseScenes(this);
    _renderer?.dispose();
    _renderer = null;
    _lastFrame = null;
    _creating = null;
    _removals++;
    super.onRemove();
  }
}
