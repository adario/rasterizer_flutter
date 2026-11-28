import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_rasterizer/src/has_rasterizer.dart' show HasRasterizer;
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/svg_hitbox.dart';
import 'package:flutter/foundation.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// An SVG that any number of components can draw with rasterizer_gpu in a
/// game with [HasRasterizer].
///
/// [load] and [RasterizerSvg.fromBytes] import the SVG: they make its
/// [scene] for the GPU renderer `gpu` when that renderer is supported, or
/// else for the canvas renderer ([RasterizerGpuBackend.backend]). The game
/// must still use that renderer when components draw the SVG, so the game's
/// [HasRasterizer.rasterizerGpu] must be `gpu`.
///
/// The SVG also keeps its bytes, so that it can parse its paths for dart:ui
/// if it's drawn into a picture of its own (see [render]).
class RasterizerSvg._(
  final Uint8List _bytes,

  /// The SVG imported for the renderer, which [render] draws.
  final RasterizerScene scene,
) {
  /// Creates an SVG from [bytes], imported for the GPU renderer [gpu] (the
  /// mesh renderer by default) when that renderer is supported.
  ///
  /// Throws [ArgumentError] if the bytes can't be parsed, or if [maxSize]
  /// isn't positive for the mesh renderer.
  ///
  /// For the mesh renderer, [maxSize] is the largest size, in device pixels, at
  /// which the game draws the SVG's longer side. The mesh renderer flattens the
  /// curves for that size, to within 1/4 of a pixel. When the SVG is drawn
  /// larger, the segments of its curves start to show. [maxSize] defaults to
  /// the view's longer side, which suits a full-screen SVG. Pass the largest
  /// size the game draws the SVG at, such as its component's longer side times
  /// the camera's largest zoom and the device pixel ratio. The mesh renderer
  /// makes the triangles once for that size, and draws the same triangles at
  /// every size, with no level of detail. So a larger [maxSize] costs the GPU
  /// more wherever the game draws the SVG small.
  RasterizerSvg.fromBytes(
    Uint8List bytes, {
    RasterizerBackend gpu = RasterizerBackend.mesh,
    double? maxSize,
  }) : this._(
         bytes,
         RasterizerScene.fromSvg(
           bytes,
           gpu: gpu,
           maxSize: maxSize ?? defaultMaxSize,
         ),
       );

  /// For tests: creates an SVG as [RasterizerSvg.fromBytes] does, imported
  /// for [backend].
  @visibleForTesting
  RasterizerSvg.debugFromBytes(
    Uint8List bytes,
    RasterizerBackend backend, {
    double? maxSize,
  }) : this._(
         bytes,
         RasterizerScene.fromSvg(
           bytes,
           backend: backend,
           maxSize: maxSize ?? defaultMaxSize,
         ),
       );

  /// The default `maxSize` of [RasterizerSvg.fromBytes], in device pixels.
  ///
  /// It's the implicit view's longer side when the SVG is loaded, or 2048 if
  /// there's no view or its size is empty.
  static double get defaultMaxSize {
    final size = PlatformDispatcher.instance.implicitView?.physicalSize;
    if (size == null || size.isEmpty) {
      return 2048;
    }
    return size.width > size.height ? size.width : size.height;
  }

  /// Loads an SVG asset with [cache], which defaults to [Flame.assets].
  ///
  /// [fileName] is the asset's full path, such as `assets/coin.svg`, and
  /// [package] is the package that holds it, if any, as for
  /// [AssetsCache.readBinaryFile]. [gpu] and [maxSize] are as for
  /// [RasterizerSvg.fromBytes].
  static Future<RasterizerSvg> load(
    String fileName, {
    AssetsCache? cache,
    String? package,
    RasterizerBackend gpu = RasterizerBackend.mesh,
    double? maxSize,
  }) async => RasterizerSvg.fromBytes(
    await (cache ?? Flame.assets).readBinaryFile(fileName, package: package),
    gpu: gpu,
    maxSize: maxSize,
  );

  /// The SVG's outline, for hitboxes such as [SvgHitbox].
  ///
  /// The first time it's read, it parses the SVG's paths in Dart, whatever
  /// [scene]'s backend is.
  late final SvgOutline outline = SvgOutline.fromSvg(_bytes);

  // The SVG imported for the canvas renderer when [scene] is for another
  // renderer. It's made the first time the SVG is drawn into a picture of its
  // own, and is null if that import failed.
  RasterizerScene? _paths;
  bool _parsedPaths = false;

  /// The rectangle that [render] fits to the drawn size, in the SVG's
  /// coordinates.
  ///
  /// It's [scene]'s [RasterizerSceneRect.rect]: the SVG's viewBox, or else
  /// its width and height, or else its paths' bounds.
  final Rect rect = scene.rect;

  /// The SVG's size, which is [rect]'s size.
  ///
  /// Everything that reads it shares this one vector, so don't change it.
  late final Vector2 size = Vector2(rect.width, rect.height);

  /// Draws the SVG with its [rect] stretched from (0, 0) to [drawnSize], in
  /// [canvas]'s current coordinates.
  ///
  /// The alpha of [overridePaint] fades each path. Its other fields apply to
  /// the SVG as a whole, as to a sprite (see [RasterizerCanvas.drawScene]).
  ///
  /// Drawn into a game's [RasterizerCanvas], the SVG becomes part of the
  /// renderer's frame. Drawn into any other canvas, such as the picture of a
  /// `Snapshot`, a camera post process or a Flame `Layer`, it draws its paths
  /// with dart:ui as rasterizer_gpu's canvas renderer does, inside a canvas
  /// layer that applies the paint's other fields. Unless [scene] is for the
  /// canvas renderer, the first such draw also imports the SVG for the canvas
  /// renderer, which parses its paths in Dart. In the game's own canvas,
  /// before the game's renderer is ready, the SVG draws nothing.
  void render(Canvas canvas, Vector2 drawnSize, {Paint? overridePaint}) {
    final r = rect;
    if (r.isEmpty) {
      return;
    }
    final sx = drawnSize.x / r.width;
    final sy = drawnSize.y / r.height;
    if (canvas is! RasterizerCanvas) {
      if (!identical(canvas, unreadyCanvas)) {
        _drawPaths(canvas, sx, sy, overridePaint);
      }
      return;
    }
    canvas.drawScene(
      scene,
      sx,
      0,
      0,
      sy,
      -r.left * sx,
      -r.top * sy,
      paint: overridePaint,
    );
  }

  /// Draws the SVG's paths into [canvas], with its [rect] scaled by [sx] and
  /// [sy] from (0, 0), and with [paint] as [render] describes.
  void _drawPaths(Canvas canvas, double sx, double sy, Paint? paint) {
    // Skip parsing for a paint that draws nothing.
    if (!((paint?.color.a ?? 1) > 0)) {
      return;
    }
    final paths = _pathScene();
    if (paths == null) {
      return;
    }
    RasterizerCanvas.drawWithPaint(canvas, paint, (opacity, colorTransform) {
      canvas
        ..save()
        ..scale(sx, sy)
        ..translate(-rect.left, -rect.top);
      paths.drawPaths(canvas, opacity: opacity, colorTransform: colorTransform);
      canvas.restore();
    });
  }

  /// Returns the SVG imported for the canvas renderer: [scene] if it's for
  /// that renderer, or else an import made on the first call. Returns null if
  /// that import failed.
  RasterizerScene? _pathScene() {
    if (scene.backend == RasterizerBackend.canvas) {
      return scene;
    }
    if (!_parsedPaths) {
      _parsedPaths = true;
      try {
        _paths = RasterizerScene.fromSvg(
          _bytes,
          backend: RasterizerBackend.canvas,
        );
      } on ArgumentError catch (e) {
        // Not in release builds, whose users can't act on it.
        if (!kReleaseMode) {
          debugPrint(
            "flame_rasterizer: a RasterizerSvg drawn into a canvas that isn't "
            "a game's RasterizerCanvas, such as a snapshot's or a post "
            "process's, couldn't be parsed for dart:ui, so it isn't drawn "
            'there: $e',
          );
        }
      }
    }
    return _paths;
  }

  /// Frees the SVG's memory. Don't draw it afterwards.
  ///
  /// Call it outside the game's render, such as from an update or an
  /// `onRemove`. Never call it between drawing the SVG and rendering its
  /// frame, which still reads it (see [RasterizerScene.dispose]).
  void dispose() {
    scene.dispose();
    _paths?.dispose();
    _paths = null;
  }
}
