import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' show World;
import 'package:flame/game.dart';
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/rasterizer_path_component.dart';
import 'package:flame_rasterizer/src/rasterizer_svg.dart' show RasterizerSvg;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show MediaQuery;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// Draws a game's [RasterizerSvg]s with rasterizer_gpu.
///
/// While the game draws its tree, the mixin wraps the game's canvas in a
/// [RasterizerCanvas], which adds the vector content to a frame of the
/// renderer, in runs. After the tree, before Flutter rasterizes the painting,
/// the mixin renders the frame once. The mesh renderer renders each run into
/// an image of its own, and the atlas renderer renders all runs into an
/// atlas. The canvas renderer has nothing to render, as it draws each run's
/// paths into the game's canvas.
///
/// The game creates its renderer when it's first drawn, or when
/// [rasterizerReady] is first read, such as in `onLoad`. It's a renderer for
/// [rasterizerGpu] where that's supported, else the canvas renderer, the same
/// choice as for the [RasterizerSvg]s' imports. Until the renderer is ready,
/// vector content drawn into the game's canvas draws nothing. With
/// [RasterizerGpu.allowOpenGles], on OpenGL ES, the renderer and the imports
/// draw with the canvas renderer until the GPU renderer's self-test passes,
/// then with the GPU renderer ([RasterizerGpuBackend.initialize]).
///
/// A game larger than the renderer takes ([RasterizerRenderer.maxViewportSize]
/// a side), such as a window over 4096 device pixels wide on OpenGL ES, has
/// its vectors rendered at a lower resolution, to fit. Their images are then
/// scaled up, a little softer.
///
/// It works on a [FlameGame] with any world [W], such as a `Forge2DGame`.
/// Dart infers [W] from the game's class, so `with HasRasterizer` is enough.
mixin HasRasterizer<W extends World> on FlameGame<W> {
  RasterizerRenderer? _renderer;
  final RasterizerCanvas _canvas = RasterizerCanvas();

  /// How many frames the renderer keeps in flight, at least 1.
  ///
  /// It's [RasterizerRenderer.create]'s `slots`. Each frame in flight has its
  /// own atlas pages or run targets, and costs their memory. So a frame's
  /// images stay valid until that many frames later. The game reads it once,
  /// when it creates the renderer.
  int get rasterizerSlots => 3;

  /// The GPU renderer to draw with where it's supported, else the canvas
  /// renderer draws.
  ///
  /// By default it's [RasterizerBackend.mesh], the mesh renderer, which draws
  /// SVGs imported once into triangles. [RasterizerBackend.gpu] picks the
  /// atlas renderer, which rasterizes them each frame. The game's
  /// [RasterizerSvg]s must be loaded for the same renderer
  /// ([RasterizerSvg.load]'s `gpu`). Drawing one loaded for the other throws.
  /// The game reads it once, when it creates the renderer.
  RasterizerBackend get rasterizerGpu => RasterizerBackend.mesh;

  /// The mesh renderer's samples per pixel, 4 or 1.
  ///
  /// It's [RasterizerRenderer.create]'s `meshSamples`. With 4, edges are
  /// antialiased where offscreen MSAA is supported. With 1, they're aliased,
  /// which costs the GPU less. The game reads it once, when it creates the
  /// renderer.
  int get rasterizerMeshSamples => 4;

  /// Whether the atlas renderer draws curves as quadratics, else as line
  /// segments.
  ///
  /// The mesh renderer flattens its curves once, when the SVGs are loaded.
  bool rasterizerCurves = true;

  /// The renderer, once it's ready.
  RasterizerRenderer? get rasterizer => _renderer;

  /// The last frame drawn, with its runs, entries, timings and atlas pages.
  ///
  /// The renderer reuses one frame object. So during the game's render, this
  /// is the frame in progress. It's valid until the next frame begins, and
  /// null once the game is removed.
  RasterizerFrame? get rasterizerFrame => _lastFrame;
  RasterizerFrame? _lastFrame;

  /// Completes with the renderer.
  ///
  /// If the game is removed meanwhile, it completes with a renderer that's
  /// already disposed of. While [rasterizerSlots] or [rasterizerMeshSamples]
  /// hold a value that [RasterizerRenderer.create] doesn't take, reading it
  /// throws an [ArgumentError] at once, and so does each frame drawn.
  Future<RasterizerRenderer> get rasterizerReady {
    if (_creating == null) {
      _checkSettings();
    }
    return _creating ??= _create();
  }

  Future<RasterizerRenderer>? _creating;

  // Checks the settings as RasterizerRenderer.create does, but at once:
  // create's future would fail, and nothing awaits it while the game draws.
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

  // How many times the game was removed. A renderer whose creation ends after
  // a removal is disposed of, rather than kept by a game that isn't drawn.
  int _removals = 0;

  Future<RasterizerRenderer> _create() async {
    final removals = _removals;
    final gpu = rasterizerGpu;
    final state = RasterizerGpu.of(gpu);
    // Reports an unsupported GPU renderer once the choice is settled: on
    // OpenGL ES, the canvas renderer draws until the self-test is done.
    state.settledBackend.then((_) {
      final support = state.support;
      // Not in release builds, whose users can't act on it.
      if (support == RasterizerSupport.supported || kReleaseMode) {
        return;
      }
      final detail = state.supportDetail;
      debugPrint(
        "flame_rasterizer: rasterizer_gpu's "
        '${gpu == RasterizerBackend.mesh ? 'mesh' : 'atlas'} renderer is '
        'unsupported here (${support.name}${detail == null ? '' : ': $detail'}'
        '), so its canvas renderer draws',
      );
    });
    final renderer = await RasterizerRenderer.create(
      slots: rasterizerSlots,
      gpu: gpu,
      meshSamples: rasterizerMeshSamples,
    );
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
    // Larger than the renderer takes, such as a window over 4096 pixels wide
    // on OpenGL ES. The vectors render at a lower pixel ratio, to fit, and
    // their images are scaled up and smoothed.
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
      // The frame renders even if a component threw: the canvas already
      // holds the images of the runs that ended before.
      _canvas.end();
      frame.render();
      _lastFrame = frame;
    }
  }

  // The device pixel ratio of the game's view, read each frame. It doesn't
  // depend on MediaQuery from paint, which would make the game widget
  // rebuild.
  double _pixelRatio() =>
      buildContext
          ?.getInheritedWidgetOfExactType<MediaQuery>()
          ?.data
          .devicePixelRatio ??
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
      1;

  /// Disposes of the renderer, and releases the imports of the game's
  /// [RasterizerPathComponent]s.
  ///
  /// The components import their paths again if the game is drawn again.
  @override
  void onRemove() {
    releasePathScenes(this);
    _renderer?.dispose();
    _renderer = null;
    _lastFrame = null;
    _creating = null;
    _removals++;
    super.onRemove();
  }
}
