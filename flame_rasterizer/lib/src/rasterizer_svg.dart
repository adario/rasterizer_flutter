import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_rasterizer/src/has_rasterizer.dart' show HasRasterizer;
import 'package:flame_rasterizer/src/internal.dart';
import 'package:flame_rasterizer/src/svg_hitbox.dart';
import 'package:flutter/foundation.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

/// An SVG that any number of components draw with rasterizer_gpu, in a game
/// with [HasRasterizer].
///
/// It's imported for the GPU renderer `gpu` where that renderer is supported,
/// else for the canvas renderer ([RasterizerGpuBackend.backend]). That must
/// still be the game's renderer when the SVG is drawn, so the game's
/// [HasRasterizer.rasterizerGpu] must be `gpu`. It keeps the SVG's bytes, to
/// parse its paths for dart:ui if it's drawn into a picture of its own (see
/// [render]).
class RasterizerSvg._(
  final Uint8List _bytes,

  /// The SVG imported for the renderer, which [render] draws.
  final RasterizerScene scene,
) {
  /// Imports an SVG's bytes for the GPU renderer [gpu], the mesh renderer by
  /// default, where it's supported.
  ///
  /// Throws [ArgumentError] if the bytes can't be parsed, or, for the mesh
  /// renderer, if [maxSize] isn't positive.
  ///
  /// For the mesh renderer, [maxSize] is the largest size, in device pixels,
  /// at which the SVG's longer side is drawn. The mesh renderer flattens the
  /// curves for that size, to within 1/4 of a pixel. Drawn larger, the curves
  /// show their segments sooner. It defaults to the view's longer side, for a
  /// full-screen SVG. Pass the largest size the game draws the SVG at, such as
  /// its component's longer side times the camera's largest zoom and the
  /// device pixel ratio. The triangles are made once, for that size, and
  /// drawn at every size, with no level of detail. So a larger [maxSize]
  /// costs the GPU more wherever the SVG is drawn small.
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

  /// For tests: [RasterizerSvg.fromBytes], imported for [backend].
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
  /// It's the implicit view's longer side when the SVG is loaded, or 2048
  /// without a view.
  static double get defaultMaxSize {
    final size = PlatformDispatcher.instance.implicitView?.physicalSize;
    if (size == null || size.isEmpty) {
      return 2048;
    }
    return size.width > size.height ? size.width : size.height;
  }

  /// Loads an SVG asset with [cache], [Flame.assets] by default.
  ///
  /// [fileName] is the asset's full path, such as `assets/coin.svg`, in
  /// [package] if given, as for [AssetsCache.readBinaryFile]. [gpu] and
  /// [maxSize] are as for [RasterizerSvg.fromBytes].
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
  /// the backend of [scene].
  late final SvgOutline outline = SvgOutline.fromSvg(_bytes);

  // The SVG imported for the canvas renderer, when [scene] isn't, once it's
  // drawn into a picture of its own. Null if the import failed.
  RasterizerScene? _paths;
  bool _parsedPaths = false;

  /// The rectangle that [render] fits to the drawn size, in the SVG's
  /// coordinates.
  ///
  /// It's [scene]'s [RasterizerSceneRect.rect]: the SVG's viewBox, or else
  /// its width and height, or else its paths' bounds.
  final Rect rect = scene.rect;

  /// The SVG's size, as [rect]'s.
  ///
  /// It's one vector, shared, so don't change it.
  late final Vector2 size = Vector2(rect.width, rect.height);

  /// Draws the SVG with its [rect] stretched from (0, 0) to [drawnSize], in
  /// [canvas]'s current coordinates.
  ///
  /// The alpha of [overridePaint] fades each path. Its other fields apply to
  /// the SVG as a whole, as to a sprite (see [RasterizerCanvas.drawScene]).
  ///
  /// Into a game's [RasterizerCanvas], the SVG draws with the frame. Into any
  /// other canvas, such as the picture of a `Snapshot`, a camera post process
  /// or a Flame `Layer`, it draws its paths with dart:ui, as rasterizer_gpu's
  /// canvas renderer does, in a layer with the paint's other fields. Unless
  /// [scene] is for the canvas renderer, the first such draw also imports the
  /// SVG for the canvas renderer, which parses its paths in Dart. Into the
  /// game's own canvas, before its renderer is ready, the SVG draws nothing.
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
    // A paint that draws nothing parses nothing.
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

  /// The SVG imported for the canvas renderer: [scene], or else an import
  /// made the first time. Null if that import failed.
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
  /// `onRemove`. Not between drawing the SVG and its frame's render, which
  /// reads it (see [RasterizerScene.dispose]).
  void dispose() {
    scene.dispose();
    _paths?.dispose();
    _paths = null;
  }
}
