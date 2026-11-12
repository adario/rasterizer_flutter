import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart' show SchedulerBinding;

import '../rasterizer_gpu.dart';
import 'canvas_renderer.dart';
import 'gpu_stub.dart' if (dart.library.ffi) 'atlas.dart' as native;
import 'paths/scene_paths.dart';

// Canvas first, on OpenGL ES. While a GPU renderer's self-test
// (RasterizerGpuBackend.initialize) may still let it draw, the scenes and
// renderers made for it without a backend are the switching ones below. They
// draw with the canvas renderer. They switch to that GPU renderer all at once,
// after its self-test passed and every live one has its GPU scene or renderer
// ready. So no GPU scene ever reaches a canvas renderer. Each GPU renderer
// switches on its own.

// The switching scenes and renderers, held weakly, so the garbage collector
// can still free them.
final _scenes = <WeakReference<SwitchingScene>>[];
final _renderers = <WeakReference<SwitchingRenderer>>[];

/// The [RasterizerScene] of [scene] for [backend]: [scene] itself, unless it's
/// a [SwitchingScene].
RasterizerScene resolveScene(
  RasterizerScene scene,
  RasterizerBackend backend,
) => scene is SwitchingScene ? scene._sceneFor(backend) : scene;

/// The name of [backend]'s renderer, for errors.
String rendererName(RasterizerBackend backend) => switch (backend) {
  RasterizerBackend.gpu => 'GPU renderer',
  RasterizerBackend.canvas => 'canvas renderer',
  RasterizerBackend.mesh => 'mesh renderer',
};

/// A scene that draws with its canvas scene until the switch.
///
/// It keeps what its canvas scene was made from: an SVG's bytes or plain
/// paths. Before the switch, [parse] makes its scene for the GPU renderer
/// [gpu] from them.
class SwitchingScene(
  CanvasScene canvas,

  /// The GPU renderer it switches to.
  final RasterizerBackend gpu,

  /// Makes its scene for [gpu].
  RasterizerScene Function() parse,
) implements RasterizerScene {
  this : _parser = parse, _canvas = canvas {
    _canvasBounds = canvas.bounds;
    viewBox = canvas.viewBox;
    _scenes.add(WeakReference(this));
  }

  /// A scene of an SVG's [bytes], parsed for [gpu] at the switch.
  ///
  /// For the mesh renderer, it imports them for [maxSize].
  factory SwitchingScene.fromSvg(
    Uint8List bytes,
    RasterizerBackend gpu,
    double? maxSize,
  ) => SwitchingScene(
    CanvasScene(bytes),
    gpu,
    () => gpu == RasterizerBackend.mesh
        ? native.parseMeshScene(bytes, maxSize!)
        : native.parseScene(bytes),
  );

  /// A scene of plain [paths], imported for [gpu] at the switch and flattened
  /// for [maxSize].
  factory SwitchingScene.fromPaths(
    ScenePaths paths,
    RasterizerBackend gpu,
    double maxSize,
  ) => SwitchingScene(
    CanvasScene.fromPaths(paths),
    gpu,
    () => gpu == RasterizerBackend.mesh
        ? native.importPathMeshScene(paths, maxSize)
        : native.importPathScene(paths, maxSize),
  );

  /// Makes its scene for [gpu]. Null once it has switched, or settled on the
  /// canvas renderer.
  RasterizerScene Function()? _parser;

  /// Its canvas scene. Null once a GPU renderer has drawn it after the switch.
  CanvasScene? _canvas;

  /// Its scene for [gpu], once parsed.
  RasterizerScene? _gpu;
  bool _switched = false, _disposed = false;

  /// Why it couldn't be parsed for [gpu] at the switch.
  ///
  /// It then stays out of the switch. [gpu]'s renderers throw this when they
  /// add it, as its parse would have.
  (Object, StackTrace)? _failure;

  @override
  RasterizerBackend get backend => _switched ? gpu : RasterizerBackend.canvas;

  // From the first parse, the canvas one, so it doesn't change at the switch.
  // The core's view box matches it (see the README).
  @override
  late final ui.Rect viewBox;

  // The bounds of the backend it draws with, as for [pathCount]. The GPU
  // renderer's match the canvas renderer's (see the README). A mesh scene's
  // are its triangles' bounds, though, which reach its glow's halos. The
  // canvas renderer doesn't draw those.
  @override
  ui.Rect get bounds => (_switched ? _gpu?.bounds : null) ?? _canvasBounds;
  late final ui.Rect _canvasBounds;

  // The count of the backend it draws with. The parsers count draws
  // differently: for tiger.svg, the core counts 240, the canvas renderer 301.
  @override
  int get pathCount => (_switched ? _gpu! : _canvas!).pathCount;

  RasterizerScene _parse() => _parser!();

  RasterizerScene _sceneFor(RasterizerBackend backend) {
    if (_disposed) {
      throw StateError('RasterizerScene disposed');
    }
    if (backend == RasterizerBackend.canvas) {
      return _canvas ??
          (throw ArgumentError(
            'A scene that switched to the ${rendererName(gpu)}, drawn by a '
            'canvas renderer',
          ));
    }
    if (backend != gpu) {
      throw ArgumentError(
        'A scene for the ${rendererName(gpu)}, drawn by the '
        '${rendererName(backend)}',
      );
    }
    if (_failure case (final error, final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (_gpu == null && _parser == null) {
      throw ArgumentError(
        'A scene that settled on the canvas renderer, drawn by the '
        '${rendererName(gpu)}',
      );
    }
    // The canvas scene stays after the switch, until a GPU renderer first
    // draws this one: a canvas frame begun before the switch can still add it.
    // Canvas runs keep their own reference to it until drawn. So it's dropped
    // for the garbage collector, not disposed of.
    if (_switched) {
      _canvas = null;
    }
    return _gpu ??= _parse();
  }

  // Only until the switch, as [backend] says, even though the canvas scene
  // stays a little longer.
  @override
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) {
    if (_disposed) {
      throw StateError('RasterizerScene disposed');
    }
    if (_switched) {
      throw StateError(
        'A scene that switched to the ${rendererName(gpu)} has no paths',
      );
    }
    _canvas!.draw(
      canvas,
      opacity: opacity,
      colorFilter: colorTransform?.filter,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _parser = null;
    _canvas?.dispose();
    _canvas = null;
    _gpu?.dispose();
    _gpu = null;
  }
}

/// A renderer that draws with a canvas renderer until the switch.
///
/// From the first frame after the switch, it draws with a renderer for the
/// GPU renderer [gpu].
class SwitchingRenderer(
  @override final int slots,

  /// The GPU renderer it switches to.
  final RasterizerBackend gpu,

  /// The mesh renderer's samples per pixel, as [RasterizerRenderer.create]'s.
  final int meshSamples,
) implements RasterizerRenderer {
  this : _current = CanvasRenderer(slots) {
    _renderers.add(WeakReference(this));
  }

  /// The renderer it draws with now.
  RasterizerRenderer _current;

  /// Its renderer for [gpu], once made, until it takes over.
  RasterizerRenderer? _gpu;
  bool _switched = false, _disposed = false;

  @override
  RasterizerBackend get backend => _current.backend;

  // The GPU renderer's limit, even on canvas. So a viewport that the GPU
  // renderer would reject fails from the start, not after the switch.
  @override
  int get maxViewportSize => native.maxPageSize;

  @override
  int get atlasResizes => _current.atlasResizes;

  @override
  int get atlasBytes => _current.atlasBytes;

  @override
  void trimAtlas() => _current.trimAtlas();

  @override
  RasterizerFrame beginFrame(int width, int height, {bool curves = true}) {
    final maxSize = maxViewportSize;
    if (width > maxSize || height > maxSize) {
      throw ArgumentError(
        'Invalid viewport size $width×$height, which must be within '
        '$maxSize×$maxSize',
      );
    }
    if (_switched && _gpu != null) {
      // The canvas renderer's frames have nothing in flight, as its runs keep
      // their own scenes until drawn. So it can go now.
      _current.dispose();
      _current = _gpu!;
      _gpu = null;
    }
    return _current.beginFrame(width, height, curves: curves);
  }

  @override
  void dispose() {
    _disposed = true;
    _current.dispose();
    _gpu?.dispose();
    _gpu = null;
  }
}

/// Switches the live scenes and renderers for the GPU renderer [gpu] to it,
/// after its self-test passed.
///
/// It makes one of [gpu]'s renderers for every live [SwitchingRenderer] that
/// switches to it. It parses every live [SwitchingScene] that switches to it,
/// a few per frame. Then it calls [flip] and switches them all at once,
/// synchronously, and returns. [flip] makes [gpu] supported, so the scenes
/// and renderers made for it afterwards are plain ones.
Future<void> switchToGpu(RasterizerBackend gpu, void Function() flip) async {
  const budget = Duration(milliseconds: 4);
  // Whether [ref]'s scene or renderer is live, for [gpu], and not ready yet.
  bool pending(WeakReference<Object> ref) {
    return switch (ref.target) {
      SwitchingScene s =>
        s.gpu == gpu && !s._disposed && s._gpu == null && s._failure == null,
      SwitchingRenderer r => r.gpu == gpu && !r._disposed && r._gpu == null,
      _ => false,
    };
  }

  while (true) {
    // Renderers first, which are few. Creating one loads the shader library,
    // cached by then, and makes its pipelines.
    for (final ref in [..._renderers]) {
      if (!pending(ref)) {
        continue;
      }
      final r = ref.target!;
      final renderer = await (gpu == RasterizerBackend.mesh
          ? native.createMeshRenderer(r.slots, r.meshSamples)
          : native.createRenderer(r.slots));
      if (r._disposed) {
        renderer.dispose();
      } else {
        r._gpu = renderer;
      }
    }
    // Then scenes, a few per frame, within the budget.
    final sw = Stopwatch()..start();
    var later = false;
    for (final ref in [..._scenes]) {
      if (!pending(ref)) {
        continue;
      }
      if (sw.elapsed > budget) {
        later = true;
        break;
      }
      final s = ref.target!;
      // The canvas renderer may parse an SVG that the core can't. Then that
      // scene alone stays out of the switch.
      try {
        s._gpu = s._parse();
      } catch (e, stackTrace) {
        s._failure = (e, stackTrace);
      }
    }
    if (later) {
      await SchedulerBinding.instance.endOfFrame;
      continue;
    }
    // New scenes or renderers may have come while awaiting. Flip only once
    // none is pending.
    if (!_renderers.any(pending) && !_scenes.any(pending)) {
      break;
    }
  }
  flip();
  for (final ref in _scenes) {
    final s = ref.target;
    if (s == null || s._disposed || s.gpu != gpu) {
      continue;
    }
    s._parser = null;
    s._switched = s._failure == null;
  }
  for (final ref in _renderers) {
    final r = ref.target;
    if (r != null && r.gpu == gpu) {
      r._switched = true;
    }
  }
  _forget(gpu);
}

/// Keeps the switching scenes and renderers for the GPU renderer [gpu] on the
/// canvas renderer.
///
/// It's called after [gpu]'s self-test failed or wasn't run, or its switch
/// failed. The scenes and renderers drop what was made for [gpu].
void settleOnCanvas(RasterizerBackend gpu) {
  for (final ref in _scenes) {
    final s = ref.target;
    if (s != null && s.gpu == gpu) {
      s._parser = null;
      s._gpu?.dispose();
      s._gpu = null;
    }
  }
  for (final ref in _renderers) {
    final r = ref.target;
    if (r != null && r.gpu == gpu) {
      r._gpu?.dispose();
      r._gpu = null;
    }
  }
  _forget(gpu);
}

/// Stops tracking the switching scenes and renderers for [gpu], and the
/// garbage collected ones.
void _forget(RasterizerBackend gpu) {
  _scenes.removeWhere((ref) => ref.target == null || ref.target!.gpu == gpu);
  _renderers.removeWhere((ref) => ref.target == null || ref.target!.gpu == gpu);
}
