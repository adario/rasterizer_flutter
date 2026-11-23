/// Renders SVG scenes with one of three renderers ([RasterizerBackend]).
///
/// - The GPU renderer uses Rasterizer's core and Flutter GPU. It works where
///   Impeller gives Flutter GPU a Metal or Vulkan context, and an OpenGL ES
///   one while [RasterizerGpu.allowOpenGles] is on, as it is by default. Its
///   support is then [RasterizerSupport.supported]. Once per frame, it
///   renders all of the frame's runs ([RasterizerRun]) into one atlas image.
///   It then draws each run from its rectangle with
///   [ui.Canvas.drawImageRect], at the run's place in the app's paint order.
/// - The canvas renderer is the fallback everywhere else. It parses scenes in
///   Dart, and each run draws its scenes' paths with [ui.Canvas.drawPath],
///   straight into the canvas it's drawn into. It works wherever Flutter
///   does, web included.
/// - The mesh renderer is made for games. It imports each SVG once into
///   triangles, which stay in GPU buffers. It renders each run with Flutter
///   GPU into an image of its own, then draws it as the GPU renderer does. It
///   works where the GPU renderer does. Scenes and renderers made with
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

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'src/canvas_renderer.dart';
import 'src/paths/scene_paths.dart';
import 'src/svg_paths/svg_paths.dart';
import 'src/gpu_stub.dart' if (dart.library.ffi) 'src/atlas.dart' as native;

export 'src/rasterizer_canvas.dart' show RasterizerCanvas;

/// Whether a GPU renderer can render here, and if not, why.
enum RasterizerSupport() {
  /// It can render here.
  supported,

  /// The platform isn't macOS, iOS, 64-bit Android, Linux or Windows, as with
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

  /// Impeller renders with OpenGL ES, and [RasterizerGpu.allowOpenGles] is
  /// off.
  ///
  /// Android falls back to OpenGL ES without Vulkan, and on devices whose
  /// Vulkan driver Flutter blocks, such as the emulator's. Linux always uses
  /// it.
  ///
  /// `io.flutter.embedding.android.ImpellerBackend` set to `vulkan` in the
  /// app's Android manifest asks for Vulkan anyway. Only debug and profile
  /// builds read it: release builds ignore it.
  openGles,

  /// Impeller renders with OpenGL ES, but can't make textures 4096 pixels
  /// wide, as both GPU renderers need. OpenGL ES only guarantees 2048.
  smallTextures,

  /// Impeller renders with OpenGL ES, and a renderer made for it didn't
  /// finish compiling its pipelines within [RasterizerGpu.warmUpTimeout], so
  /// [RasterizerRenderer.create] made the canvas renderer instead.
  warmUpTimeout,
}

/// Which renderer parses and draws scenes.
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
  /// NanoSVG parses each SVG once. The renderer flattens its curves for the
  /// largest size it draws the SVG at, and libtess2 turns its fills and
  /// stroke outlines into triangles, which stay in GPU buffers. Each frame
  /// then only writes its entries' transforms, and renders each run into an
  /// image of its own.
  ///
  /// The images are 4× multisampled where Flutter GPU supports offscreen
  /// MSAA, else aliased. With [RasterizerRenderer.create]'s `meshSamples` of
  /// 1, they're aliased everywhere. As with the other renderers, it ignores an
  /// SVG's clip paths.
  ///
  /// It works only where `RasterizerGpu.of(RasterizerBackend.mesh).support`
  /// is [RasterizerSupport.supported]: where the GPU renderer's is.
  mesh,
}

/// The GPU renderers' support, and the options that all renderers share.
///
/// Each GPU renderer has its own state, from [of]. Members that share a name
/// with one of [RasterizerGpuBackend]'s are the GPU renderer's,
/// [RasterizerBackend.gpu].
abstract final class RasterizerGpu() {
  /// Returns the state of the GPU renderer [gpu]: [RasterizerBackend.gpu] or
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

  static final _gpu = RasterizerGpuBackend._(RasterizerBackend.gpu);
  static final _mesh = RasterizerGpuBackend._(RasterizerBackend.mesh);

  /// Whether Flutter GPU can render here, which both GPU renderers need.
  ///
  /// It's checked once. Off Impeller, getting Flutter GPU's context throws, so
  /// the check looks at whether Impeller is on first.
  static RasterizerSupport get _context =>
      _contextSupport ??= native.checkSupport(debugCheckedTextureWidth);
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

  /// Lets the GPU renderers draw on OpenGL ES.
  ///
  /// It's on by default. They then draw there from the first frame, as on
  /// Metal and Vulkan, but for two steps:
  /// - each renderer compiles its pipelines as it's made, which stalls the UI
  ///   thread, then the raster thread. [RasterizerRenderer.create] completes
  ///   once both are done, so the first frame doesn't pay for them, and an
  ///   app can show a loader meanwhile. In release builds with no shader
  ///   cache, on Mesa's llvmpipe, the GPU renderer's took about 0.55 s and
  ///   0.15 s, and the mesh renderer's 0.23 s and 0.87 s. On the Android
  ///   emulator, they took about 0.1 s and 50-90 ms, and 60 ms and 30 ms.
  /// - the first GPU renderer made starts a format probe, which checks that it
  ///   draws right while accumulating coverage in r32Float. Where it doesn't,
  ///   the renderer accumulates in r16g16b16a16Float instead: at once where
  ///   r32Float textures can't be made, else once the probe has read its
  ///   pixels back, so its first frames may be wrong. The probe then checks
  ///   r16g16b16a16Float too. [RasterizerGpuBackend.supportDetail] says what
  ///   the probe found.
  ///
  /// Support checks one more thing: that textures can be 4096 pixels wide, as
  /// the GPU renderers need. OpenGL ES only guarantees 2048. Where they can't,
  /// support is [RasterizerSupport.smallTextures], and the canvas renderer
  /// draws. Nothing else is checked. A driver that draws wrongly, in either
  /// format, draws wrongly, with no fallback to the canvas renderer, and one
  /// that crashes crashes the app. One that never finishes compiling the
  /// pipelines falls back to the canvas renderer after [warmUpTimeout],
  /// unless it holds the UI thread meanwhile.
  /// Both GPU renderers have only been tried on the Android emulator's OpenGL
  /// ES and on Mesa's llvmpipe on Linux, not on a device's own driver. Turn it
  /// off to draw with the canvas renderer on OpenGL ES. Scenes and renderers
  /// read it as they're made, so set it before.
  static bool allowOpenGles = true;

  /// How long [RasterizerRenderer.create] waits for a GPU renderer to compile
  /// its pipelines on OpenGL ES ([allowOpenGles]).
  ///
  /// If they haven't compiled by then, it makes the canvas renderer instead,
  /// and that GPU renderer's support becomes [RasterizerSupport.warmUpTimeout].
  static Duration warmUpTimeout = const Duration(seconds: 5);

  /// For tests: what the format probe treats as failing.
  ///
  /// It holds accumulation formats, by Flutter GPU's PixelFormat names, such
  /// as `r32Float`. A format in it fails at once. One followed by ` pixels`,
  /// such as `r32Float pixels`, fails once its pixels are read back, as a
  /// driver that draws it wrongly does.
  @visibleForTesting
  static Set<String> debugFailFormatProbe = {};

  /// For tests: how wide a texture support checks that Flutter GPU can make
  /// on OpenGL ES.
  ///
  /// It's 4096, the widest the GPU renderers' textures get there. Wider than
  /// the device allows, support is [RasterizerSupport.smallTextures].
  @visibleForTesting
  static int debugCheckedTextureWidth = 4096;

  /// For tests: the OpenGL ES format probe that the first GPU renderer made
  /// started, if any.
  ///
  /// It completes with the probe's failure, or null if it passed.
  @visibleForTesting
  static Future<String?>? get debugFormatProbe => native.formatProbe;

  /// For tests: forgets each GPU renderer's support and the format probe's
  /// result, so they're checked again.
  @visibleForTesting
  static void debugResetSupport() {
    _contextSupport = null;
    _gpu._timedOut = _mesh._timedOut = null;
    native.contextError = null;
    native.resetFormatProbe();
  }

  /// For tests: runs the format probe on its own wherever the GPU renderer is
  /// supported, Metal and Vulkan included, without changing its format.
  ///
  /// Returns null if it passed, else why it didn't.
  @visibleForTesting
  static Future<String?> debugProbeFormat() =>
      native.debugProbeFormat(debugFailFormatProbe);

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
}

/// One of the GPU renderers, [RasterizerBackend.gpu] or
/// [RasterizerBackend.mesh], from [RasterizerGpu.of].
///
/// It tells whether the renderer can render here. Scenes and renderers made
/// with it as their `gpu` and no backend ([RasterizerScene.fromSvg],
/// [RasterizerRenderer.create]) use it where it's supported, else the canvas
/// renderer.
final class RasterizerGpuBackend._(
  /// Which GPU renderer it is.
  final RasterizerBackend gpu,
) {
  /// Whether it can render here.
  ///
  /// On OpenGL ES, it's [RasterizerSupport.supported] while
  /// [RasterizerGpu.allowOpenGles] is on, else [RasterizerSupport.openGles],
  /// or [RasterizerSupport.warmUpTimeout] once a renderer made for it timed
  /// out.
  RasterizerSupport get support {
    final context = RasterizerGpu._context;
    if (context != RasterizerSupport.openGles || !RasterizerGpu.allowOpenGles) {
      return context;
    }
    return _timedOut == null
        ? RasterizerSupport.supported
        : RasterizerSupport.warmUpTimeout;
  }

  /// The [RasterizerGpu.warmUpTimeout] that a renderer made for it exceeded,
  /// if any.
  Duration? _timedOut;

  /// More about [support].
  ///
  /// It's Flutter GPU's error when [support] is
  /// [RasterizerSupport.noFlutterGpu] or [RasterizerSupport.smallTextures].
  /// On OpenGL ES, it says how the renderer draws there: for the GPU
  /// renderer, the format it accumulates coverage in and what the format probe
  /// found ([RasterizerGpu.allowOpenGles]), and for the mesh renderer, whether
  /// its targets are multisampled.
  String? get supportDetail => switch (RasterizerGpu._context) {
    RasterizerSupport.noFlutterGpu ||
    RasterizerSupport.smallTextures => native.contextError,
    RasterizerSupport.openGles when !RasterizerGpu.allowOpenGles =>
      'OpenGL ES: set RasterizerGpu.allowOpenGles',
    RasterizerSupport.openGles when _timedOut != null =>
      "OpenGL ES: the pipelines didn't compile within "
          '${_timedOut!.inMilliseconds} ms',
    RasterizerSupport.openGles =>
      'OpenGL ES, ${switch (gpu) {
        RasterizerBackend.mesh => native.meshDetail,
        _ => native.formatDetail,
      }}',
    _ => null,
  };

  /// The backend that scenes and renderers made for it without one use.
  ///
  /// It's this renderer where it's supported, unless
  /// [RasterizerGpu.forceCanvas] is set. Otherwise it's the canvas renderer.
  RasterizerBackend get backend =>
      !RasterizerGpu.forceCanvas && support == RasterizerSupport.supported
      ? gpu
      : RasterizerBackend.canvas;
}

/// An SVG's outline, for hitboxes: its paths as one [ui.Path].
///
/// It parses the SVG in Dart, as the canvas renderer does, whatever the
/// backend, and ignores clips, as the renderers do.
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
  /// Throws [ArgumentError] if it can't parse them.
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

  /// Returns [path] with its open contours closed.
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
/// from each contour, so the fill hides a hole's halo. Halos that
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

  /// Creates a glow reaching [radius], in the paths' units, as a stroke's width
  /// is.
  const RasterizerGlow(double radius, {double strength = 1, ui.Color? color})
    : this._(radius, strength: strength, color: color);

  /// Creates a glow reaching [widths] line widths, so it follows lines that
  /// taper.
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

/// A path and the paint to draw it with, for [RasterizerScene.fromPaths].
typedef RasterizerPaintedPath = ({ui.Path path, ui.Paint paint});

/// Polygons, for [RasterizerScene.fromPolygons]: a path that the GPU
/// renderers needn't flatten.
///
/// [vertices] holds each vertex's x then y, polygon after polygon, x right
/// and y down. [vertexCounts] holds each polygon's number of vertices. A
/// polygon doesn't repeat its first vertex at its end. Both lists are kept
/// as they are, so they must not change, as a path imported mustn't.
class RasterizerPolygons(
  final Float32List vertices,
  final Int32List vertexCounts,
) {
  /// Takes [vertices] and [vertexCounts].
  ///
  /// Throws [ArgumentError] if a polygon has fewer than 3 vertices, or if the
  /// counts don't add up to [vertices].
  this {
    var total = 0;
    for (final count in vertexCounts) {
      if (count < 3) {
        throw ArgumentError.value(count, 'vertexCounts', 'Fewer than 3');
      }
      total += count;
    }
    if (2 * total != vertices.length) {
      throw ArgumentError.value(
        vertices.length,
        'vertices',
        'Not twice the ${vertexCounts.length} polygons\' $total vertices',
      );
    }
  }

  /// The vertices' bounds, or [ui.Rect.zero] without polygons.
  late final ui.Rect bounds = () {
    if (vertices.isEmpty) {
      return ui.Rect.zero;
    }
    var left = vertices[0], right = left, top = vertices[1], bottom = top;
    for (var i = 2; i < vertices.length; i += 2) {
      final x = vertices[i], y = vertices[i + 1];
      if (x < left) {
        left = x;
      } else if (x > right) {
        right = x;
      }
      if (y < top) {
        top = y;
      } else if (y > bottom) {
        bottom = y;
      }
    }
    return ui.Rect.fromLTRB(left, top, right, bottom);
  }();

  /// The polygons as a path, made the first time it's read, for the canvas
  /// renderer and other dart:ui drawing.
  late final ui.Path path = () {
    final path = ui.Path();
    var offset = 0;
    for (final count in vertexCounts) {
      path.addPolygon([
        for (var k = offset; k < offset + 2 * count; k += 2)
          ui.Offset(vertices[k], vertices[k + 1]),
      ], true);
      offset += 2 * count;
    }
    return path;
  }();
}

/// Polygons and the paint to draw them with, for
/// [RasterizerScene.fromPolygons].
typedef RasterizerPaintedPolygons = ({
  RasterizerPolygons polygons,
  ui.Paint paint,
});

/// An SVG's paths, or plain paths with their paints, that any number of a
/// frame's entries can draw, each with its own transform.
///
/// A scene is parsed for one backend, and only that backend's renderers can
/// draw it.
abstract class RasterizerScene {
  /// Parses an SVG's bytes, such as an asset's, for [backend].
  ///
  /// By default, [backend] is the choice of the GPU renderer [gpu],
  /// [RasterizerBackend.gpu] or [RasterizerBackend.mesh]: [gpu] where it's
  /// supported, else the canvas renderer ([RasterizerGpuBackend.backend]).
  /// Throws if it can't parse the bytes.
  ///
  /// When [backend], or else [gpu], is the mesh renderer, [maxSize] is
  /// required and must be positive, even if the canvas renderer ends up
  /// chosen. It's the most that the SVG's longer side is drawn at, in device
  /// pixels. The mesh renderer flattens the SVG's curves for it, to within 1/4
  /// of a pixel.
  /// Other renderers ignore it.
  ///
  /// [dispose], or else a finalizer, frees a GPU scene's native memory.
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
      if (!(maxSize > 0) || !maxSize.isFinite) {
        throw ArgumentError.value(
          maxSize,
          'maxSize',
          'Not a positive finite number',
        );
      }
    }
    final chosen = backend ?? RasterizerGpu.of(gpu).backend;
    switch (chosen) {
      case RasterizerBackend.mesh:
        return native.parseMeshScene(bytes, maxSize!);
      case RasterizerBackend.gpu:
        return native.parseScene(bytes);
      case RasterizerBackend.canvas:
        return CanvasScene(bytes);
    }
  }

  /// Creates a scene of plain paths, each drawn with its paint, in paint
  /// order, for [backend] or [gpu], as with [fromSvg].
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
  /// dot drawn as a line of no length with round caps isn't drawn. It copies
  /// the paints' fields. As for SVGs, the GPU renderer's strokes have
  /// a fixed miter limit, and it draws bevel joins as miters.
  ///
  /// Only the mesh renderer draws a [glow]. Its scene's [pathCount] then
  /// counts each path's halo and each draw's core, and its [bounds] reach the
  /// halos.
  ///
  /// Throws [ArgumentError] if [maxSize] isn't positive. It also throws for a
  /// paint that the GPU renderers can't draw ([canDraw]), whatever the
  /// backend, so that a scene draws the same with each. A GPU scene's native
  /// memory is freed as [fromSvg]'s is.
  factory RasterizerScene.fromPaths(
    List<RasterizerPaintedPath> paths, {
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
    return _fromScenePaths(
      ScenePaths(paths, glow: glow),
      backend ?? RasterizerGpu.of(gpu).backend,
      maxSize,
    );
  }

  /// Creates a scene of polygons, each drawn with its paint, in paint order,
  /// as [fromPaths] does with paths.
  ///
  /// The GPU renderers take the polygons' vertices as they are, rather than
  /// flattening a path's contours. Fills are non-zero. The canvas renderer
  /// draws each [RasterizerPolygons.path].
  ///
  /// With [separate], the mesh renderer fills each polygon on its own, rather
  /// than the polygons' union, which is much faster for many polygons: a
  /// convex one is a fan of triangles. So where polygons overlap, their
  /// triangles do too, and the overlaps show where a scene is drawn with an
  /// opacity, or with colors or glows that aren't opaque. Other renderers
  /// ignore [separate].
  ///
  /// Throws [ArgumentError] as [fromPaths] does.
  factory RasterizerScene.fromPolygons(
    List<RasterizerPaintedPolygons> polygons, {
    RasterizerBackend? backend,
    RasterizerBackend gpu = RasterizerBackend.gpu,
    required double maxSize,
    RasterizerGlow? glow,
    bool separate = false,
  }) {
    if (!(maxSize > 0) || !maxSize.isFinite) {
      throw ArgumentError.value(
        maxSize,
        'maxSize',
        'Not a positive finite number',
      );
    }
    return _fromScenePaths(
      ScenePaths.polygons(polygons, glow: glow, separate: separate),
      backend ?? RasterizerGpu.of(gpu).backend,
      maxSize,
    );
  }

  /// Imports [paths] for [backend].
  static RasterizerScene _fromScenePaths(
    ScenePaths paths,
    RasterizerBackend backend,
    double maxSize,
  ) => switch (backend) {
    RasterizerBackend.mesh => native.importPathMeshScene(paths, maxSize),
    RasterizerBackend.gpu => native.importPathScene(paths, maxSize),
    RasterizerBackend.canvas => CanvasScene.fromPaths(paths),
  };

  /// Returns whether the GPU renderers can draw a path with [paint], in
  /// [fromPaths].
  ///
  /// They can draw a fill, or a stroke of positive width, in an sRGB color,
  /// with [ui.BlendMode.srcOver] and antialiasing. The paint can't have a
  /// shader, a color, mask or image filter, or [ui.Paint.invertColors]. A
  /// hairline, a stroke of width 0, is a device pixel wide under any
  /// transform, so they can't import it once. A [ui.Canvas] can still draw
  /// what they can't.
  static bool canDraw(ui.Paint paint) => undrawable(paint) == null;

  /// The backend it's parsed for, whose renderers draw it.
  RasterizerBackend get backend;

  /// Its paths' bounds, grown by half of each stroke's width, in the SVG's
  /// coordinates: x right, y down.
  ///
  /// They're empty if it has no paths. A mesh scene's bounds are its
  /// triangles', which can be tighter than the GPU and canvas renderers'. The
  /// tiger's are 474.2 × 490.0 with the mesh renderer, against 478.5 × 506.9.
  /// So each renderer places an SVG fitted by its bounds differently, while
  /// [viewBox] is the same for all.
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
  /// Frames it was added to keep their own references once rendered. But
  /// don't dispose of it between [RasterizerRun.add] and
  /// [RasterizerFrame.render], nor before drawing a canvas run that draws it.
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

/// Returns [viewBox], or [bounds] if [viewBox] is empty.
ui.Rect _drawnRect(ui.Rect viewBox, ui.Rect bounds) =>
    viewBox.width > 0 && viewBox.height > 0 ? viewBox : bounds;

/// Renders frames with its [backend]'s renderer.
///
/// A GPU renderer keeps [slots] frames in flight, each with its own atlas
/// textures. So a frame's images stay valid until [slots] frames later, when
/// it renders into its textures again. 2 are enough for frames drawn as
/// they're built, as Flutter rasterizes a frame before it builds the one
/// after next. An app that takes an image of a frame later, such as with
/// `RepaintBoundary.toImage` after the frame, needs 3.
abstract class RasterizerRenderer() {
  /// Creates a renderer for [backend].
  ///
  /// By default, [backend] is the GPU renderer [gpu]'s choice, as with
  /// [RasterizerScene.fromSvg]. For a GPU renderer, it throws
  /// [UnsupportedError] unless that renderer's support ([RasterizerGpu.of]) is
  /// [RasterizerSupport.supported].
  ///
  /// [meshSamples] are the mesh renderer's samples per pixel, 1 or 4, as
  /// Flutter GPU allows. With 4, its runs' targets are multisampled where
  /// Flutter GPU supports offscreen MSAA, so their edges are antialiased. With
  /// 1, or where offscreen MSAA isn't supported, they're aliased, which costs
  /// the GPU less.
  ///
  /// On OpenGL ES, a GPU renderer compiles its pipelines as it's made, and
  /// the future completes once they've compiled, on the UI thread and then
  /// on the raster thread ([RasterizerGpu.allowOpenGles]). If they haven't
  /// within [RasterizerGpu.warmUpTimeout], it completes with the canvas
  /// renderer, and the GPU renderer's support becomes
  /// [RasterizerSupport.warmUpTimeout], so that scenes made after without a
  /// backend are for the canvas renderer. Scenes made before are for the GPU
  /// renderer, which the canvas renderer can't draw: make them after.
  static Future<RasterizerRenderer> create({
    int slots = 2,
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
    final chosen = backend ?? RasterizerGpu.of(gpu).backend;
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
    final timeout = RasterizerGpu.warmUpTimeout;
    try {
      return await (chosen == RasterizerBackend.mesh
          ? native.createMeshRenderer(slots, meshSamples, timeout)
          : native.createRenderer(
              slots,
              RasterizerGpu.debugFailFormatProbe,
              timeout,
            ));
    } on TimeoutException {
      state._timedOut = timeout;
      return CanvasRenderer(slots);
    }
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
  /// [trimAtlas] shrinks them too. The renderer releases pages that no frame
  /// needed for 120 frames. Each change reallocates a page's textures.
  static const atlasStep = 256;

  /// The backend it renders with.
  RasterizerBackend get backend;

  /// How many frames it keeps in flight, from [create].
  int get slots;

  /// The longest viewport side that [beginFrame] takes, in device pixels.
  ///
  /// It's [maxAtlasSize], or 4096 on OpenGL ES, for the GPU and mesh
  /// renderers. It's null for the canvas renderer, which takes any size.
  int? get maxViewportSize;

  /// How many times atlas pages have changed size, frame after frame.
  ///
  /// Each change reallocates their textures. For the mesh renderer, it counts
  /// how many times the renderer has allocated its runs' targets. It's 0 for
  /// the canvas renderer, which has neither.
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
  /// side: [maxAtlasSize], or 4096 on OpenGL ES. The canvas renderer takes
  /// any size.
  RasterizerFrame beginFrame(int width, int height, {bool curves = true});

  /// Frees its native memory and GPU resources.
  ///
  /// Don't use it, its frame or its runs' images after.
  void dispose();
}

/// A width and height, in pixels.
typedef RasterizerPixelSize = ({int width, int height});

/// One frame's runs.
///
/// Add entries to its runs, [render] it once, then draw each run. A renderer
/// reuses its frame object, so a frame is only valid until
/// the next [RasterizerRenderer.beginFrame].
abstract class RasterizerFrame() {
  /// The backend that draws it: its renderer's [RasterizerRenderer.backend].
  RasterizerBackend get backend;

  /// Its viewport's width, from [RasterizerRenderer.beginFrame].
  int get width;

  /// Its viewport's height, from [RasterizerRenderer.beginFrame].
  int get height;

  /// How many entries its runs have in all.
  int get entryCount;

  /// The frame's runs, in the order [addRun] added them.
  Iterable<RasterizerRun> get runs;

  /// Adds a new run, which is drawn on its own.
  ///
  /// Entries in one run overlap in the order [RasterizerRun.add] added them.
  ///
  /// [clip], in the viewport's device pixels, is where the run's image can
  /// show, such as the bounds of the clip it's drawn under. The run then
  /// skips entries that paint nothing in it, and the GPU and mesh renderers
  /// render only what's in it, within a pixel or two. So a paint that spreads
  /// the run's image, such as a blur, loses what lay outside it.
  RasterizerRun addRun({ui.Rect? clip});

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
  List<RasterizerPixelSize> get pageSizes;
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
///   saturation are examples, offsets included. The renderers clamp such a
///   matrix's results to 0 to 1 per path rather than per pixel. That differs
///   where paths that it takes out of range overlap translucently, antialiased
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

  /// Returns [ui.ColorFilter.mode] of [color] and [mode], with its transform.
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

  /// Returns [ui.ColorFilter.matrix] of [values], 20 of them, row by row, with
  /// its transform.
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

  /// Returns the transform [mode] or [matrix] made [filter] with, or null for
  /// any other filter, even an equal one.
  static RasterizerColorTransform? of(ui.ColorFilter filter) => _known[filter];

  static final _known = Expando<RasterizerColorTransform>();

  /// Returns [color] as this transform makes it, as a path of that color takes
  /// its [filter].
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

  /// Returns the matrix of the mode filter of color (r, g, b) at alpha t, the
  /// source, over a pixel, the destination, both premultiplied.
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

  /// Returns the matrix on premultiplied colors of [v], a 5 x 4 matrix on
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
  /// before the painting is rasterized. It places GPU runs in the frame's
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
  /// different opacities share the run. It skips an entry whose opacity is
  /// 0.
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

  /// Adds [scene] as [add] does, with a projective transform, as a
  /// perspective gives.
  ///
  /// The transform maps (x, y) to ((a * x + c * y + tx) / w,
  /// (b * x + d * y + ty) / w), where w = g * x + h * y + i. Points where w
  /// isn't positive are behind the eye, and the mesh renderer clips them
  /// away.
  ///
  /// The mesh and canvas renderers draw any such transform. The GPU renderer
  /// only takes affine ones, where g and h are 0, and throws [ArgumentError]
  /// otherwise. It renders its entries without perspective, so the canvas
  /// applies its transform's perspective to the run's images instead, sampled
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

  /// Adds [scene] as [addProjective] does, with a [Matrix4], such as a
  /// canvas's transform.
  ///
  /// It ignores the matrix's z row and column.
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
  /// [ui.FilterQuality.none], takes the nearest pixel, as it draws the image
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
