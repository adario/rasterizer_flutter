/// Renders SVG scenes with one of three renderers ([RasterizerBackend]).
///
/// Each frame holds runs ([RasterizerRun]). A run is a group of entries,
/// each a scene ([RasterizerScene]) with a transform, that's drawn as one
/// unit at one place in the app's paint order.
///
/// - The GPU renderer uses Rasterizer's native core and Flutter GPU. It
///   works where Impeller gives Flutter GPU a Metal or Vulkan context, or an
///   OpenGL ES context while [RasterizerGpu.allowOpenGles] is on (the
///   default). There, its support is [RasterizerSupport.supported]. Once per
///   frame, it renders all of the frame's runs into an atlas: a few large
///   textures, called pages, that it packs the runs' rectangles into. It
///   then draws each run from its rectangles with [ui.Canvas.drawImageRect],
///   at the run's place in the app's paint order.
/// - The canvas renderer is the fallback everywhere else. It parses scenes in
///   Dart, and each run draws its scenes' paths with [ui.Canvas.drawPath]
///   directly into the canvas that the run is drawn into. It works wherever
///   Flutter does, including on the web.
/// - The mesh renderer is made for games. It imports each SVG once, turning
///   it into triangles that stay in GPU buffers. It renders each run with
///   Flutter GPU into its own image, then draws that image as the GPU
///   renderer does. It works wherever the GPU renderer does. Scenes and
///   renderers created with `gpu: RasterizerBackend.mesh` use it where it's
///   supported, and the canvas renderer elsewhere.
///
/// All three have the same API:
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

  /// The platform isn't macOS, iOS, 64-bit Android, Linux or Windows, as is
  /// the case on 32-bit Android or the web.
  unsupportedPlatform,

  /// Flutter renders with Skia, not Impeller.
  noImpeller,

  /// Impeller doesn't give Flutter GPU a context, because Flutter GPU isn't
  /// turned on.
  ///
  /// To turn it on, set:
  /// - on iOS and macOS, `FLTEnableFlutterGPU` in Info.plist.
  /// - on Android, `io.flutter.embedding.android.EnableFlutterGPU` in the
  ///   manifest. This package's manifest sets it.
  /// - on Linux, `fl_dart_project_set_enable_flutter_gpu(project, TRUE)` in
  ///   the runner's `linux/runner/my_application.cc`.
  noFlutterGpu,

  /// Impeller renders with OpenGL ES, and [RasterizerGpu.allowOpenGles] is
  /// off.
  ///
  /// Android falls back to OpenGL ES on devices without Vulkan, and on
  /// devices whose Vulkan driver Flutter blocks, such as the emulator's.
  /// Linux always uses OpenGL ES.
  ///
  /// Setting `io.flutter.embedding.android.ImpellerBackend` to `vulkan` in
  /// the app's Android manifest asks for Vulkan anyway. Only debug and
  /// profile builds read this setting; release builds ignore it.
  openGles,

  /// Impeller renders with OpenGL ES, but can't make the 4096-pixel-wide
  /// textures that both GPU renderers need. OpenGL ES only guarantees 2048.
  smallTextures,

  /// Impeller renders with OpenGL ES, and a GPU renderer didn't finish
  /// compiling its pipelines within [RasterizerGpu.warmUpTimeout], so
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
  /// largest size it will draw the SVG at, and libtess2 turns its fills and
  /// stroke outlines into triangles, which stay in GPU buffers. Each frame
  /// then only writes its entries' transforms and renders each run into its
  /// own image.
  ///
  /// The images are 4× multisampled where Flutter GPU supports offscreen
  /// MSAA, and aliased elsewhere. With `meshSamples: 1` in
  /// [RasterizerRenderer.create], they're aliased everywhere. Like the other
  /// renderers, it ignores an SVG's clip paths.
  ///
  /// It works only where `RasterizerGpu.of(RasterizerBackend.mesh).support`
  /// is [RasterizerSupport.supported], which is wherever the GPU renderer's
  /// support is too.
  mesh,
}

/// The GPU renderers' support and the options that all renderers share.
///
/// [of] returns each GPU renderer's own state. Members named like members of
/// [RasterizerGpuBackend] give the state of the GPU renderer,
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

  /// Whether Flutter GPU can render here, as both GPU renderers need.
  ///
  /// It's checked once. Without Impeller, getting Flutter GPU's context
  /// throws, so the check first looks at whether Impeller is on.
  static RasterizerSupport get _context =>
      _contextSupport ??= native.checkSupport(debugCheckedTextureWidth);
  static RasterizerSupport? _contextSupport;

  /// The GPU renderer's [RasterizerGpuBackend.support].
  static RasterizerSupport get support => _gpu.support;

  /// The GPU renderer's [RasterizerGpuBackend.supportDetail].
  static String? get supportDetail => _gpu.supportDetail;

  /// Whether Impeller renders with OpenGL ES, whether or not the GPU renderers
  /// draw there ([allowOpenGles]).
  static bool get openGles {
    _context;
    return native.openGles;
  }

  /// Whether the GPU renderers may draw on OpenGL ES.
  ///
  /// It's on by default. The GPU renderers then draw on OpenGL ES from the
  /// first frame, as on Metal and Vulkan, except for two extra steps:
  /// - Each renderer compiles its pipelines when it's created, which stalls
  ///   the UI thread and then the raster thread. [RasterizerRenderer.create]
  ///   completes after both are done, so the first frame doesn't pay for
  ///   them, and an app can show a loader meanwhile. In release builds with
  ///   no shader cache on Mesa's llvmpipe, this took about 0.55 s on the UI
  ///   thread and 0.15 s on the raster thread for the GPU renderer, and
  ///   0.23 s and 0.87 s for the mesh renderer. On the Android emulator, it
  ///   took about 0.1 s and 50-90 ms, and 60 ms and 30 ms.
  /// - The first [RasterizerBackend.gpu] renderer created starts a format
  ///   probe. The probe checks that the renderer draws correctly while
  ///   accumulating coverage in r32Float. Where it doesn't, the renderer
  ///   accumulates in r16g16b16a16Float instead. It switches at once where
  ///   r32Float textures can't be made, and otherwise after the probe has
  ///   read its pixels back, so its first frames may be wrong. The probe then
  ///   checks r16g16b16a16Float too. [RasterizerGpuBackend.supportDetail]
  ///   says what the probe found. The mesh renderer runs no probe.
  ///
  /// Support checks one more thing: that textures can be 4096 pixels wide, as
  /// the GPU renderers need. OpenGL ES only guarantees 2048. Where they can't,
  /// support is [RasterizerSupport.smallTextures], and the canvas renderer
  /// draws. Nothing else is checked. If a driver draws wrongly in both
  /// formats, the renderer keeps drawing wrongly, with no fallback to the
  /// canvas renderer, and a driver that crashes crashes the app. A driver
  /// that never finishes compiling the pipelines falls back to the canvas
  /// renderer after [warmUpTimeout], unless it blocks the UI thread
  /// meanwhile.
  ///
  /// Both GPU renderers have only been tested on the Android emulator's
  /// OpenGL ES and on Mesa's llvmpipe on Linux, not on a device's own driver.
  /// Turn this off to draw with the canvas renderer on OpenGL ES. Scenes and
  /// renderers read it when they're created, so set it before creating them.
  static bool allowOpenGles = true;

  /// How long [RasterizerRenderer.create] waits for a GPU renderer to compile
  /// its pipelines on OpenGL ES ([allowOpenGles]).
  ///
  /// If they haven't compiled by then, it makes the canvas renderer instead,
  /// and that GPU renderer's support becomes [RasterizerSupport.warmUpTimeout].
  static Duration warmUpTimeout = const Duration(seconds: 5);

  /// For tests: what the format probe treats as failing.
  ///
  /// It holds accumulation formats by their Flutter GPU `PixelFormat` names,
  /// such as `r32Float`. A listed format fails at once. A format followed by
  /// ` pixels`, such as `r32Float pixels`, fails after its pixels are read
  /// back, as with a driver that draws it wrongly.
  @visibleForTesting
  static Set<String> debugFailFormatProbe = {};

  /// For tests: the texture width that the support check makes sure Flutter
  /// GPU can create on OpenGL ES.
  ///
  /// It's 4096 by default, the widest that the GPU renderers' textures get
  /// there. When it's wider than the device allows, support is
  /// [RasterizerSupport.smallTextures].
  @visibleForTesting
  static int debugCheckedTextureWidth = 4096;

  /// For tests: the OpenGL ES format probe that the first
  /// [RasterizerBackend.gpu] renderer started, if any.
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

  /// For tests: runs the format probe by itself wherever the GPU renderer is
  /// supported, including on Metal and Vulkan, without changing the
  /// renderer's format.
  ///
  /// Returns null if it passed, or else why it failed.
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
  /// In a benchmark, pictures halved the UI thread's time and left the raster
  /// time about the same.
  static bool canvasPictures = true;

  /// The GPU renderers' shaders, which hook/build.dart builds and pubspec.yaml
  /// lists as an asset.
  static const shaderBundle =
      'packages/rasterizer_gpu/build/shaderbundles/rasterizer.shaderbundle';
}

/// One of the GPU renderers, [RasterizerBackend.gpu] or
/// [RasterizerBackend.mesh], from [RasterizerGpu.of].
///
/// It tells whether that renderer can render here. Scenes and renderers
/// created with it as their `gpu` and no `backend` ([RasterizerScene.fromSvg],
/// [RasterizerRenderer.create]) use it where it's supported, and the canvas
/// renderer elsewhere.
final class RasterizerGpuBackend._(
  /// Which GPU renderer it is.
  final RasterizerBackend gpu,
) {
  /// Whether it can render here.
  ///
  /// On OpenGL ES, it's [RasterizerSupport.supported] while
  /// [RasterizerGpu.allowOpenGles] is on, and [RasterizerSupport.openGles]
  /// otherwise. It becomes [RasterizerSupport.warmUpTimeout] after a renderer
  /// of this kind timed out while compiling its pipelines.
  RasterizerSupport get support {
    final context = RasterizerGpu._context;
    if (context != RasterizerSupport.openGles || !RasterizerGpu.allowOpenGles) {
      return context;
    }
    return _timedOut == null
        ? RasterizerSupport.supported
        : RasterizerSupport.warmUpTimeout;
  }

  /// The [RasterizerGpu.warmUpTimeout] that a renderer of this kind exceeded,
  /// if any.
  Duration? _timedOut;

  /// More about [support].
  ///
  /// It's Flutter GPU's error when [support] is
  /// [RasterizerSupport.noFlutterGpu] or [RasterizerSupport.smallTextures].
  /// On OpenGL ES, it says how the renderer draws there. For the GPU
  /// renderer, that's the format it accumulates coverage in and what the
  /// format probe found ([RasterizerGpu.allowOpenGles]). For the mesh
  /// renderer, it's whether its targets are multisampled. It also says when
  /// [RasterizerGpu.allowOpenGles] is off or the pipelines timed out.
  /// Otherwise it's null.
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

  /// The backend that scenes and renderers use when they're created with
  /// this as their `gpu` and no `backend`.
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
/// backend. Like the renderers, it ignores clips.
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
  /// Creates an outline by parsing an SVG's bytes.
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

/// A glow like a neon tube's around the paths of a scene from
/// [RasterizerScene.fromPaths] or [RasterizerScene.fromPolygons].
///
/// Only the mesh renderer draws it. The GPU and canvas renderers draw the
/// same paths without it.
///
/// Each path gets a halo under all of its draws. The halo fades out from the
/// path's edge to its own outer edge. If one of the path's draws strokes the
/// path, the halo spreads on both sides of its polylines. Otherwise, it
/// spreads outward from each contour, so the fill hides the halo of a hole.
/// Overlapping halos add up, both within a path and between entries. A halo
/// adds light: it covers what's under it only as much as its color's
/// strongest channel. So a black halo, or one tinted to black, is invisible.
///
/// Each stroke also gets a core drawn over it, which turns nearly white along
/// its middle and keeps the stroke's color at its edges. Strokes narrower
/// than about 2.7 pixels get no core. With [RasterizerGlow.widths], fills get
/// a core too.
///
/// Halos and cores are triangles that the scene creates once, when it's
/// imported, and draws with its paths. So a glow takes no extra layer or pass
/// per path, and an entry's opacity and color transform apply to it. When an
/// entry is faded, its cores show over their draws. Changing a glow means
/// creating the scene again. A glow with a radius or strength of 0 is the
/// same as no glow.
class const RasterizerGlow._(
  /// How far the halo reaches, from a stroke's centre line or a fill's
  /// contour.
  ///
  /// It's in the paths' units, or with [inWidths], in line widths.
  final double radius, {

  /// The halo's alpha on the path, from 0 to 1, as a fraction of its color's
  /// alpha.
  ///
  /// Just outside the path, the halo fades out from 0.6 of that. A core has
  /// its draw's alpha.
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

  /// Creates a glow that reaches [radius] in the paths' units, the units of a
  /// stroke's width.
  const RasterizerGlow(double radius, {double strength = 1, ui.Color? color})
    : this._(radius, strength: strength, color: color);

  /// Creates a glow that reaches [widths] line widths, so it follows lines
  /// that taper.
  ///
  /// For a stroked path, a line width is the widest of the path's strokes.
  /// For a fill, it's the fill's shorter edge at each point of a contour,
  /// which matches a line's width only in a thin shape. So a fill counts as a
  /// line and gets a core too, unless one of the path's draws strokes it.
  /// That core lies inside each contour that is neither inside another
  /// contour nor around one, and reaches half of the shorter edge at each
  /// point. A hairline, which has no width, gets neither a halo nor a core.
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

/// A shape made of one or more polygons, which a scene draws as it draws a
/// path.
///
/// Polygons have no curves, so the GPU renderers draw them without first
/// flattening them into lines, as they must with a path.
/// [RasterizerScene.fromPolygons] creates a scene of them.
///
/// [vertices] holds the x and then the y of each vertex, polygon after
/// polygon, with x to the right and y down. [vertexCounts] holds the number
/// of vertices of each polygon. Each polygon closes by itself, so don't
/// repeat its first vertex at its end. The class keeps both lists without
/// copying them, so don't change them, just as you mustn't change a path
/// after creating a scene from it.
class RasterizerPolygons(
  final Float32List vertices,
  final Int32List vertexCounts,
) {
  /// Creates polygons from [vertices] and [vertexCounts].
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

  /// The bounds of the vertices, or [ui.Rect.zero] if there are no polygons.
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

  /// The polygons as a path, for the canvas renderer and other dart:ui
  /// drawing.
  ///
  /// It's created the first time it's read.
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

/// An SVG's paths, or plain paths with their paints, ready to draw.
///
/// Any number of a frame's entries can draw the same scene, each with its own
/// transform. An entry is one placement of a scene in a run, added with
/// [RasterizerRun.add].
///
/// A scene is parsed for one backend, and only that backend's renderers can
/// draw it.
abstract class RasterizerScene {
  /// Creates a scene by parsing an SVG's bytes, such as an asset's, for
  /// [backend].
  ///
  /// By default, the GPU renderer [gpu] ([RasterizerBackend.gpu] or
  /// [RasterizerBackend.mesh]) chooses [backend]: [gpu] where it's supported,
  /// and the canvas renderer elsewhere ([RasterizerGpuBackend.backend]).
  /// Throws if it can't parse the bytes.
  ///
  /// When [backend] is the mesh renderer, or [backend] is null and [gpu] is,
  /// [maxSize] is required and must be positive and finite, even if the
  /// canvas renderer ends up chosen. It's the largest size, in device pixels,
  /// that the SVG's longer side is drawn at. The mesh renderer flattens the
  /// SVG's curves to within 1/4 of a pixel at that size. Other renderers
  /// ignore it.
  ///
  /// [dispose] frees a GPU scene's native memory, or a finalizer does if you
  /// don't call it.
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

  /// Creates a scene of plain paths, each drawn with its paint in list order,
  /// for [backend] or [gpu] as with [fromSvg].
  ///
  /// For example, each element can be a shape's path with one of the paints
  /// it's drawn with. A fill fills its path with the path's
  /// [ui.Path.fillType] and closes open contours. A stroke strokes its path
  /// and leaves open contours open. Coordinates are the paths' own, with x
  /// right and y down, and the [viewBox] is the paths' bounds, not counting
  /// their strokes.
  ///
  /// The GPU renderers read each path's contours with
  /// [ui.Path.computeMetrics] and flatten them once into polylines, to within
  /// 1/4 of a device pixel when the [viewBox]'s longer side is [maxSize]
  /// device pixels. [maxSize] is the largest size the scene is drawn at, and
  /// it's required for every renderer.
  ///
  /// Treat the paths as immutable: changing one after creating the scene
  /// gives undefined results. The GPU renderers keep drawing it as it was.
  /// The canvas renderer draws it as it was when it recorded it as a picture
  /// ([RasterizerGpu.canvasPictures]), and otherwise as it is.
  ///
  /// Each path keeps its contours while it lives, for the next scene made
  /// from it with the same tolerance, such as one with other paints. Contours
  /// of zero length are left out, as [ui.Path.computeMetrics] leaves them
  /// out. So a dot drawn as a zero-length line with round caps doesn't show.
  /// The scene copies the paints' fields. As with SVGs, the GPU renderer's
  /// strokes have a fixed miter limit, and it draws bevel joins as miters.
  ///
  /// Only the mesh renderer draws a [glow]. A mesh scene's [pathCount] then
  /// also counts each path's halo and each draw's core, and its [bounds]
  /// include the halos.
  ///
  /// Throws [ArgumentError] if [maxSize] isn't positive and finite. Whatever
  /// the backend, it also throws for a paint that the GPU renderers can't
  /// draw ([canDraw]), so that a scene looks the same with every renderer. A
  /// GPU scene's native memory is freed as with [fromSvg].
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

  /// Creates a scene of polygons, each drawn with its paint in list order, as
  /// [fromPaths] does with paths.
  ///
  /// The GPU renderers use the polygons' vertices directly, without
  /// flattening anything. Fills use the non-zero rule. The canvas renderer
  /// draws each [RasterizerPolygons.path].
  ///
  /// With [separate], the mesh renderer fills each polygon on its own instead
  /// of filling their union, and fills a convex polygon as a fan of
  /// triangles. That's much faster for many polygons. However, where polygons
  /// overlap, their triangles overlap too, and the overlap shows when an
  /// entry draws the scene with an opacity below 1, or with colors or glows
  /// that aren't opaque. The other renderers ignore [separate].
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

  /// Returns whether the GPU renderers can draw a path with [paint] in
  /// [fromPaths].
  ///
  /// They can draw a fill, or a stroke of positive width, in an sRGB color
  /// with [ui.BlendMode.srcOver] and antialiasing. The paint can't have a
  /// shader, a color filter, a mask filter, an image filter or
  /// [ui.Paint.invertColors]. A hairline (a stroke of width 0) is one device
  /// pixel wide under any transform, so they can't turn it into geometry
  /// once, when the scene is created. A [ui.Canvas] can still draw what they
  /// can't.
  static bool canDraw(ui.Paint paint) => undrawable(paint) == null;

  /// The backend it's parsed for, whose renderers draw it.
  RasterizerBackend get backend;

  /// Its paths' bounds, grown by half of each stroke's width, in the SVG's
  /// coordinates: x right, y down.
  ///
  /// They're empty if it has no paths. A mesh scene's bounds are its
  /// triangles' bounds, which can be tighter than those of the GPU and canvas
  /// renderers. For the Ghostscript tiger, they're 474.2 × 490.0 with the
  /// mesh renderer and 478.5 × 506.9 with the others. So an SVG fitted by its
  /// bounds lands slightly differently with each renderer, while [viewBox] is
  /// the same for all.
  ui.Rect get bounds;

  /// The SVG's own rectangle, in its coordinates.
  ///
  /// It's the SVG's viewBox, or else the rectangle from (0, 0) to its width
  /// and height. Its paths can draw outside it, as [bounds] shows.
  ui.Rect get viewBox;

  /// The number of draws it makes: each path's fill and stroke.
  int get pathCount;

  /// Draws its paths straight into [canvas] with dart:ui, in the SVG's
  /// coordinates, as the canvas renderer does.
  ///
  /// [opacity] scales each path's alpha, and [colorTransform]'s filter
  /// filters each path's color. It draws into any canvas, such as a picture
  /// recorder's, under any transform, without a frame or renderer. Only
  /// canvas scenes keep their paths, so it throws [StateError] unless
  /// [backend] is [RasterizerBackend.canvas].
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  });

  /// Frees its memory.
  ///
  /// Frames that it was added to keep their own references to it after they
  /// render. Don't dispose of it between [RasterizerRun.add] and
  /// [RasterizerFrame.render], though, nor before drawing a canvas run that
  /// draws it.
  void dispose();
}

/// The rectangle that a [RasterizerScene] is drawn from.
extension RasterizerSceneRect on RasterizerScene {
  /// The rectangle that the scene is drawn from, in its coordinates, for
  /// example to fit it to a size.
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
/// the renderer renders into those textures again. Two slots are enough for
/// frames drawn as they're built, because Flutter rasterizes a frame before
/// it builds the one after next. An app that takes an image of a frame
/// later, such as with `RepaintBoundary.toImage` after the frame, needs 3.
abstract class RasterizerRenderer() {
  /// Creates a renderer for [backend].
  ///
  /// By default, the GPU renderer [gpu] chooses [backend], as with
  /// [RasterizerScene.fromSvg]. For a GPU renderer, it throws
  /// [UnsupportedError] unless that renderer's support ([RasterizerGpu.of]) is
  /// [RasterizerSupport.supported].
  ///
  /// [meshSamples] is the mesh renderer's number of samples per pixel: 1 or
  /// 4, the values Flutter GPU allows. With 4, its runs' targets are
  /// multisampled where Flutter GPU supports offscreen MSAA, so their edges
  /// are antialiased. With 1, or where offscreen MSAA isn't supported,
  /// they're aliased, which costs the GPU less.
  ///
  /// On OpenGL ES, a GPU renderer compiles its pipelines when it's created,
  /// first on the UI thread and then on the raster thread
  /// ([RasterizerGpu.allowOpenGles]), and the future completes after they've
  /// compiled. If they haven't compiled within [RasterizerGpu.warmUpTimeout],
  /// the future completes with a canvas renderer instead. The GPU renderer's
  /// support then becomes [RasterizerSupport.warmUpTimeout], so scenes
  /// created afterwards without a backend are canvas scenes. Scenes created
  /// before are GPU scenes, which the canvas renderer can't draw, so create
  /// scenes after the renderer.
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

  /// The longest side, in pixels, of the GPU renderer's atlas pages, and so
  /// of its viewports.
  ///
  /// Vulkan devices commonly support it, and Metal always does. On OpenGL ES,
  /// the limit is 4096 instead, as Flutter GPU doesn't report the device's
  /// maximum.
  static const maxAtlasSize = 8192;

  /// The step, in pixels, that atlas page sizes are multiples of.
  ///
  /// Pages grow at once to what a frame needs. They shrink at most once every
  /// 120 frames, to the largest size that those frames needed, if that's
  /// below half a page's area. If the viewport changed size meanwhile, as
  /// with a rotation or a window resize, they shrink to that size whatever
  /// its area. [trimAtlas] shrinks them too. The renderer releases pages that
  /// no frame has needed for 120 frames. Each change reallocates a page's
  /// textures.
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

  /// How many times atlas pages have changed size, over all frames so far.
  ///
  /// Each change reallocates their textures. For the mesh renderer, it counts
  /// how many times the renderer has allocated its runs' targets. It's 0 for
  /// the canvas renderer, which has neither.
  int get atlasResizes;

  /// The current size of its atlas pages' textures in bytes, estimated from
  /// their formats.
  ///
  /// The textures are each in-flight frame's target, and each page's depth
  /// and accumulation textures. For the mesh renderer, they're its runs'
  /// targets and their multisampled textures. It's 0 for the canvas renderer,
  /// which has none.
  int get atlasBytes;

  /// Shrinks the atlas pages to the last frame's needs at once, and releases
  /// the pages that frame didn't need.
  ///
  /// Call it when an app knows its frames got lighter, such as at a level
  /// change or when leaving a zoomed view. Later frames grow the pages again
  /// as needed, and each growth reallocates textures. When called between
  /// [beginFrame] and [RasterizerFrame.render], it waits for that frame and
  /// uses its needs. The mesh renderer releases its runs' targets, which
  /// later frames allocate again as needed. The canvas renderer does nothing.
  void trimAtlas();

  /// Begins a frame for a [width] x [height] viewport in device pixels, and
  /// ends the previous one.
  ///
  /// Entries' transforms map their scene's coordinates to the viewport's,
  /// with x right and y down. With [curves], the GPU renderer draws curves as
  /// quadratics; without it, as line segments.
  ///
  /// The GPU and mesh renderers take viewports up to [maxViewportSize] a
  /// side: [maxAtlasSize], or 4096 on OpenGL ES. The canvas renderer takes
  /// any size.
  RasterizerFrame beginFrame(int width, int height, {bool curves = true});

  /// Frees its native memory and GPU resources.
  ///
  /// Don't use it, its frame or its runs' images afterwards.
  void dispose();
}

/// A width and height, in pixels.
typedef RasterizerPixelSize = ({int width, int height});

/// One frame's runs, rendered together.
///
/// Add entries to its runs, [render] it once, then draw each run. A renderer
/// reuses its frame object, so a frame is only valid until the next
/// [RasterizerRenderer.beginFrame].
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

  /// Adds a run, which is drawn on its own.
  ///
  /// Entries in one run overlap in the order [RasterizerRun.add] added them.
  ///
  /// [clip], in the viewport's device pixels, is where the run's image can
  /// show, such as the bounds of the clip it's drawn under. The run then
  /// skips entries that paint nothing in it, and the GPU and mesh renderers
  /// render only what's in it, within a pixel or two. So a paint that spreads
  /// the run's image, such as a blur, loses what was outside the clip.
  RasterizerRun addRun({ui.Rect? clip});

  /// Renders all of its runs, which gives them their images.
  ///
  /// The GPU renderer packs the runs' rectangles into atlas pages, and renders
  /// each page once. The mesh renderer renders each run into its own target.
  /// The canvas renderer has nothing to render.
  void render();

  /// The time [render] took to write the frame on the CPU, including packing
  /// and entries, in microseconds.
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

/// A color filter applied to each of an entry's paths rather than to its run
/// as a layer, giving the same pixels.
///
/// It's a filter that's linear in premultiplied color and keeps alpha, so it
/// commutes with compositing and antialiasing. Entries with different color
/// transforms can share a run.
///
/// [mode] and [matrix] create one, with its [filter], from:
/// - [ui.ColorFilter.mode] with [ui.BlendMode.srcATop] (a tint), `dst` or
///   `clear`, and an sRGB color. Tints are exact.
/// - [ui.ColorFilter.matrix] whose alpha row is (0, 0, 0, 1, 0) and whose
///   color rows have 0 in the alpha column. Examples include greyscale,
///   sepia, hue rotation and saturation, with or without offsets. The
///   renderers clamp such a matrix's results to the range 0 to 1 per path
///   rather than per pixel. The result differs from a layer's where paths
///   that the matrix takes out of range overlap translucently, including at
///   antialiased edges between paths. A hue rotation of 2 radians differs
///   there by up to 40/255.
///
/// Modes that scale alpha, such as `modulate`, `srcIn`, `dstIn` and `dstOut`,
/// can't be color transforms. Applied to each path, they would let
/// overlapping paths show through each other, as an entry's opacity does.
///
/// A [ui.ColorFilter] can't be read back: its fields are private, and profile
/// and release builds strip dart:ui's `toString`. So [of] only recognizes the
/// filters that [mode] and [matrix] created.
class RasterizerColorTransform._(
  /// Its filter, which [of] maps back to this transform.
  ///
  /// On a layer's paint, it gives the same pixels that this transform gives
  /// path by path.
  final ui.ColorFilter filter,

  /// The 4 x 4 matrix, row by row, that it applies to premultiplied colors.
  ///
  /// Its rows and columns are r, g, b and a. Each color channel is then
  /// clamped between 0 and the alpha. It's unmodifiable, like [filter].
  final Float32List values,
) {
  this {
    _known[filter] = this;
  }

  /// Returns the transform for [ui.ColorFilter.mode] with [color] and [mode],
  /// holding that filter.
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

  /// Returns the transform for [ui.ColorFilter.matrix] with [values], 20 of
  /// them row by row, holding that filter.
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

  /// Returns [color] after this transform, as [filter] would color a path of
  /// that color.
  ///
  /// It applies [values] to the premultiplied color, then clamps each color
  /// channel between 0 and the alpha.
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

  /// Returns the matrix of the mode filter for the source color (r, g, b) at
  /// alpha t over a destination pixel, both premultiplied.
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

  /// Returns [v] as a matrix on premultiplied colors, or null.
  ///
  /// [v] is a 5 x 4 matrix on unpremultiplied colors, with offsets from 0 to
  /// 255.
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
/// overlap in a chain, and that no other entry of the run overlaps. A mesh
/// run has one part, its target, and [page] is the target's index among the
/// frame's targets.
class const RasterizerRunPart(
  /// The index of the atlas page it's in.
  final int page,

  /// The atlas page it's in.
  ///
  /// It stays valid until [RasterizerRenderer.slots] frames later, and holds
  /// the run's pixels only after the frame has rendered.
  final ui.Image image,

  /// Its rectangle in [image], in device pixels.
  final ui.Rect source,

  /// A rectangle of the same size in the viewport, in device pixels.
  final ui.Rect destination,
);

/// A run of entries, drawn on its own.
///
/// A run is drawn as one unit, at one place in the app's paint order. The
/// GPU renderer draws it as images, from its parts' rectangles in the
/// frame's atlas. The mesh renderer draws its target. The canvas renderer
/// draws its entries' paths.
abstract class RasterizerRun() {
  /// Its position in the frame's runs.
  int get index;

  /// Its parts, for GPU runs, after [place] or [RasterizerFrame.render].
  ///
  /// The parts don't overlap in the viewport. So a run of entries scattered
  /// over the viewport takes up only their area of the atlas, not the whole
  /// viewport's. A mesh run has one part, its target. A run that has nothing
  /// to draw has no parts, and neither do canvas runs.
  List<RasterizerRunPart> get parts;

  /// Whether it has nothing to draw.
  ///
  /// That's when it has no entries, or, for a placed GPU run, no entries in
  /// the viewport.
  bool get isEmpty;

  /// Ends it, so it can be drawn before the frame renders.
  ///
  /// That lets an app draw it while painting, as long as the frame renders
  /// before the painting is rasterized. For GPU runs, it places the run in
  /// the frame's atlas at once rather than at [RasterizerFrame.render], which
  /// sets its [parts]. Placed runs go onto pages sized for what the previous
  /// frame's runs needed. So a run that doesn't fit on one page goes onto the
  /// next, which adds a page to render.
  void place();

  /// Adds an entry that draws [scene] with an affine transform from its
  /// coordinates to the viewport's.
  ///
  /// The transform maps (x, y) to (a * x + c * y + tx, b * x + d * y + ty), in
  /// device pixels with y down. Entries added later draw over earlier ones.
  /// [scene] must have been parsed for the renderer's backend.
  /// [addProjective] adds a scene with a perspective.
  ///
  /// [opacity], from 0 to 1, scales the alpha of each of the scene's paths,
  /// so overlapping paths show through each other, unlike with a layer.
  /// Entries with different opacities can share the run. It skips an entry
  /// whose opacity is 0.
  ///
  /// [colorTransform] filters the color of each of the scene's paths. That
  /// gives the same pixels as a layer with its filter around the entry.
  /// Entries with different color transforms can share the run.
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

  /// Adds [scene] as [add] does, with a projective transform such as a
  /// perspective.
  ///
  /// The transform maps (x, y) to ((a * x + c * y + tx) / w,
  /// (b * x + d * y + ty) / w), where w = g * x + h * y + i. Points where w
  /// isn't positive are behind the eye, and the mesh renderer clips them
  /// away.
  ///
  /// The mesh and canvas renderers draw any such transform. The GPU renderer
  /// only takes affine ones, where g and h are 0, and throws [ArgumentError]
  /// otherwise. It renders its entries without perspective. Instead, a
  /// perspective in the canvas's transform applies to the run's images,
  /// sampled with [RasterizerRun.draw]'s `filterQuality`.
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

  /// Draws it into [canvas], with its viewport's origin at the canvas's
  /// origin.
  ///
  /// Each of the canvas's units is [scale] device pixels, such as a device
  /// pixel ratio.
  ///
  /// [paint] applies to the run as a layer's paint would. A canvas run draws
  /// its paths into a layer with it. A GPU run draws its parts' images with
  /// it, which gives the same pixels. It draws them into a layer instead for
  /// an image or mask filter, and, when the run has several parts, for a
  /// blend mode that changes what's under transparent pixels. A color filter
  /// that colors transparent pixels colors each part's rectangle rather than
  /// the run's whole bounds. Both are the entries' bounds plus a margin.
  ///
  /// A canvas run draws its entries as they are when it's drawn, so draw it
  /// before the next [RasterizerRenderer.beginFrame].
  ///
  /// [filterQuality] sets how a GPU run's image is sampled. The default,
  /// [ui.FilterQuality.none], takes the nearest pixel, which suits drawing
  /// the image pixel for pixel. Use [ui.FilterQuality.low] for a canvas whose
  /// transform resamples it, such as one with perspective. A canvas run draws
  /// its paths and ignores it.
  void draw(
    ui.Canvas canvas, {
    double scale = 1,
    ui.Paint? paint,
    ui.FilterQuality filterQuality = ui.FilterQuality.none,
  });
}
