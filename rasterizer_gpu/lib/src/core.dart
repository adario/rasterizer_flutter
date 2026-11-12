/// The Rasterizer core, through FFI: SVG and path scenes, scene lists, and the
/// frames that a GPU host draws.
///
/// rasterizer_gpu.dart renders them. This library is internal and native
/// only: it imports dart:ffi, so the package imports it behind
/// `dart.library.ffi`. The package's tests and example use it to check frames.
library;

import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' show StrokeCap, StrokeJoin;

import 'package:ffi/ffi.dart';

import 'geometry.dart';
import 'bindings.dart' as raw;
import 'paths/path_contours.dart';

export 'geometry.dart';
export 'atlas.dart' show AtlasFrame, AtlasRenderer, AtlasRun, AtlasScene;
export 'paths/path_contours.dart' show PathContours;
export 'self_test.dart' show selfTestSize, selfTestSvg;
export 'self_test_cache.dart' show SelfTestCache;

extension on Transform {
  raw.RaTransform _toNative() => Struct.create<raw.RaTransform>()
    ..a = a
    ..b = b
    ..c = c
    ..d = d
    ..tx = tx
    ..ty = ty;
}

extension on Bounds {
  raw.RaBounds _toNative() => Struct.create<raw.RaBounds>()
    ..lx = lx
    ..ly = ly
    ..ux = ux
    ..uy = uy;
}

Bounds _bounds(raw.RaBounds n) => Bounds(n.lx, n.ly, n.ux, n.uy);

/// Converts an ARGB color, as Flutter's, to NanoSVG's ABGR, with r in the low
/// byte.
int _abgr(int argb) =>
    (argb & 0xFF00FF00) | (argb >> 16 & 0xFF) | (argb & 0xFF) << 16;

/// One draw of a path in [Scene.fromPaths] and [Mesh.fromPaths].
///
/// Draws come in paint order. Each one either fills its path, which closes
/// the path's open contours, or strokes it.
class const PathDraw({
  /// The index of its path, counting the paths of the contours' lists one
  /// list after the other.
  required final int path,

  /// Its color, as Flutter's ARGB, unpremultiplied.
  required final int color,

  /// Its stroke's width, or 0 for a fill.
  final double strokeWidth = 0,

  /// Its stroke's miter limit. The GPU renderer uses a fixed one instead, as
  /// for SVGs.
  final double miterLimit = 4,

  /// Its stroke's cap.
  final StrokeCap cap = StrokeCap.butt,

  /// Its stroke's join. The GPU renderer draws bevel joins as miters, as for
  /// SVGs.
  final StrokeJoin join = StrokeJoin.miter,

  /// Whether a fill uses the even-odd rule, else the non-zero one.
  final bool evenOdd = false,

  /// Whether it's a hairline: a stroke of width 0, whatever [strokeWidth] is.
  ///
  /// Only [Mesh.fromPaths] imports hairlines. [Scene.fromPaths] skips them.
  final bool hairline = false,
});

/// A glow around the paths of a [Mesh.fromPaths], like a neon tube's.
///
/// A halo lies under all of a path's draws. If a draw strokes the path, the
/// halo spreads on both sides of the path's polylines. Otherwise it spreads
/// outward from each contour, closed, as the contour's winding tells. So a
/// hole's halo lies inside the fill, where it's hidden. A halo fades out from
/// the path's edge to its own edge, and halos that overlap add up. A halo is
/// light: it covers what's under it as much as its color's strongest channel.
/// So a black halo, or one tinted to black, leaves nothing.
///
/// Over each draw, a core turns near white down its middle and keeps the
/// draw's color at its edges. A core under about 2.7 pixels wide keeps the
/// draw's color throughout. A stroke's core runs along it. With [inWidths],
/// which makes a fill a line, a fill gets a core too, if no draw strokes its
/// path. That core reaches inward from each contour that's neither inside
/// another nor around one, by half the shorter edge at each point. A hairline
/// has no core. Drawn with an opacity, a core shows over its draw.
///
/// A glow whose [radius] or [strength] isn't positive doesn't show, and is the
/// same as no glow.
class const Glow({
  /// How far its halo reaches, from a stroke's centre line or from a fill's
  /// contour.
  required final double radius,

  /// Its halo's alpha at the path's edge, from 0 to 1, of its color. Just
  /// outside the path, the halo starts fading out from 0.6 of that.
  final double strength = 1,

  /// Its halo's color, as Flutter's ARGB, unpremultiplied, or null for the
  /// color of the path's last draw.
  final int? color,

  /// Whether [radius] is in line widths, else in the paths' units.
  ///
  /// A stroked path's line width is its widest stroke's. A fill's is its
  /// shorter edge at each point of a contour, which only measures a line's
  /// width in a thin shape. A hairline, of no width, gets no halo.
  final bool inWidths = false,
}) {
  Pointer<raw.RaGlow> _toNative(Arena arena) {
    final native = arena<raw.RaGlow>();
    native.ref
      ..radius = radius
      ..strength = strength
      ..color = _abgr(color ?? 0)
      ..hasColor = color == null ? 0 : 1
      ..inWidths = inWidths ? 1 : 0;
    return native;
  }
}

/// Calls [f] with [contours] and [draws] copied into native memory, the
/// contours' lists one after the other.
///
/// Throws an [ArgumentError] if a draw's path isn't among the contours' paths.
T _withPaths<T>(
  List<PathContours> contours,
  List<PathDraw> draws,
  T Function(Pointer<raw.RaContours>, Pointer<raw.RaPathDraw>) f,
) {
  var points = 0, contourCount = 0, pathCount = 0;
  for (final c in contours) {
    points += c.points.length;
    contourCount += c.pointCounts.length;
    pathCount += c.contourCounts.length;
  }
  for (final draw in draws) {
    if (draw.path < 0 || draw.path >= pathCount) {
      throw ArgumentError.value(draw.path, 'path', 'Not among the contours');
    }
  }
  // An allocation of 0 bytes may return null, so each allocates at least 1
  // item.
  return using((arena) {
    final xy = arena<Float>(points + 1);
    final counts = arena<Uint32>(contourCount + 1);
    final closed = arena<Uint8>(contourCount + 1);
    final contoursPerPath = arena<Uint32>(pathCount + 1);
    final xyList = xy.asTypedList(points);
    final countList = counts.asTypedList(contourCount);
    final closedList = closed.asTypedList(contourCount);
    final perPathList = contoursPerPath.asTypedList(pathCount);
    var p = 0, c = 0, n = 0;
    for (final contour in contours) {
      xyList.setAll(p, contour.points);
      countList.setAll(c, contour.pointCounts);
      closedList.setAll(c, contour.closed);
      perPathList.setAll(n, contour.contourCounts);
      p += contour.points.length;
      c += contour.pointCounts.length;
      n += contour.contourCounts.length;
    }
    final native = arena<raw.RaContours>();
    native.ref
      ..points = xy
      ..pointCounts = counts
      ..closed = closed
      ..contourCounts = contoursPerPath
      ..pathCount = pathCount;
    final nativeDraws = arena<raw.RaPathDraw>(draws.length + 1);
    for (final (i, draw) in draws.indexed) {
      nativeDraws[i]
        ..path = draw.path
        ..color = _abgr(draw.color)
        ..strokeWidth = draw.strokeWidth
        ..miterLimit = draw.miterLimit
        ..cap = draw.cap.index
        ..join = draw.join.index
        ..evenOdd = draw.evenOdd ? 1 : 0
        ..hairline = draw.hairline ? 1 : 0;
    }
    return f(native, nativeDraws);
  });
}

/// The core's Ra::Params, which tune how it writes a list's frames.
///
/// Its clear color is ARGB, as Flutter's. Clips are always on, as the
/// instances shader's clip coverage is undefined without them.
class const Params({
  final bool useCurves = true,
  final bool showOpaques = true,
  final bool showOutlines = false,
  final int clearColor = 0xFFFFFFFF,
}) {
  Params._fromNative(raw.RaParams n)
    : this(
        useCurves: n.useCurves,
        showOpaques: n.showOpaques,
        showOutlines: n.showOutlines,
        clearColor: n.clearA << 24 | n.clearR << 16 | n.clearG << 8 | n.clearB,
      );

  raw.RaParams _toNative() => Struct.create<raw.RaParams>()
    ..useClips = true
    ..useCurves = useCurves
    ..showOpaques = showOpaques
    ..showOutlines = showOutlines
    ..clearB = clearColor & 0xFF
    ..clearG = clearColor >> 8 & 0xFF
    ..clearR = clearColor >> 16 & 0xFF
    ..clearA = clearColor >> 24 & 0xFF;
}

/// The sizes of the frame's structs that the shaders read, and the constants
/// that the shaders depend on.
final Layout layout = Layout._(raw.ra_layout());

class Layout._(raw.RaLayout n) {
  this
    : color = n.color,
      pathData = n.pathData,
      opaque = n.opaque,
      instance = n.instance,
      edge = n.edge,
      segment = n.segment,
      point16 = n.point16,
      entry = n.entry,
      colorTextureWidth = n.colorTextureWidth,
      moleculesHeight = n.moleculesHeight,
      fastSegments = n.fastSegments,
      stripHeight = n.stripHeight;

  final int color, pathData, opaque, instance, edge, segment, point16, entry;
  final int colorTextureWidth, moleculesHeight, fastSegments, stripHeight;
}

/// A Ra::Scene: the draws of an SVG or of plain paths.
class Scene._(
  var Pointer<raw.RaSceneHandle> _handle,

  /// Maps the SVG's coordinates, y down, into a list's space, y up, flipped
  /// within its [svgBounds].
  final Transform svgTransform,
) implements Finalizable {
  this {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  /// Parses the SVG file at [path].
  ///
  /// Throws an [ArgumentError] if it can't be parsed.
  factory Scene.fromSvg(String path) {
    return using((arena) {
      final ctm = arena<raw.RaTransform>();
      final handle = raw.ra_scene_from_svg(
        path.toNativeUtf8(allocator: arena).cast(),
        ctm,
      );
      if (handle == nullptr) {
        throw ArgumentError.value(path, 'path', 'Not a parseable SVG file');
      }
      return Scene._(
        handle,
        Transform(
          ctm.ref.a,
          ctm.ref.b,
          ctm.ref.c,
          ctm.ref.d,
          ctm.ref.tx,
          ctm.ref.ty,
        ),
      );
    });
  }

  /// Parses an SVG's bytes, such as an asset's.
  ///
  /// Throws an [ArgumentError] if they can't be parsed.
  factory Scene.fromSvgBytes(Uint8List bytes) {
    return using((arena) {
      final ctm = arena<raw.RaTransform>();
      // An allocation of 0 bytes may return null, so allocate at least 1.
      final data = arena<Uint8>(bytes.length + 1)
        ..asTypedList(bytes.length).setAll(0, bytes);
      final handle = raw.ra_scene_from_svg_data(data.cast(), bytes.length, ctm);
      if (handle == nullptr) {
        throw ArgumentError('Not parseable SVG data');
      }
      return Scene._(
        handle,
        Transform(
          ctm.ref.a,
          ctm.ref.b,
          ctm.ref.c,
          ctm.ref.d,
          ctm.ref.tx,
          ctm.ref.ty,
        ),
      );
    });
  }

  /// Creates a scene of [draws] of [contours]' paths, the contours' lists one
  /// after the other.
  ///
  /// The paths' polylines draw as lines, in the paths' coordinates, y down.
  /// The scene's [svgBounds] are [viewBox]. Paths with points that aren't
  /// finite don't draw.
  ///
  /// Throws an [ArgumentError] if a draw's path isn't among the contours'
  /// paths.
  factory Scene.fromPaths(
    List<PathContours> contours,
    List<PathDraw> draws,
    Bounds viewBox,
  ) {
    final handle = _withPaths(
      contours,
      draws,
      (c, d) =>
          raw.ra_scene_from_paths(c, d, draws.length, viewBox._toNative()),
    );
    // The core returns null when it runs out of memory.
    if (handle == nullptr) {
      throw OutOfMemoryError();
    }
    // As for an SVG, flip the paths within their view box.
    return Scene._(handle, Transform(1, 0, 0, -1, 0, viewBox.ly + viewBox.uy));
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<raw.RaSceneHandle>)>>(
      raw.ra_scene_release,
    ).cast(),
  );

  /// The number of its draws.
  int get count => raw.ra_scene_count(_live);

  /// The bounds of its visible draws, strokes' widths included.
  Bounds get bounds => _bounds(raw.ra_scene_bounds(_live));

  /// The SVG's own rectangle in its paths' coordinates, y down: its viewBox, or
  /// else from 0, 0 to its width and height.
  Bounds get svgBounds => _bounds(raw.ra_scene_svg_bounds(_live));

  Pointer<raw.RaSceneHandle> get _live =>
      _handle == nullptr ? throw StateError('Scene disposed') : _handle;

  /// Its native address, for [SceneList.setEntries].
  int get address => _live.address;

  void dispose() {
    if (_handle == nullptr) {
      return;
    }
    _finalizer.detach(this);
    raw.ra_scene_release(_handle);
    _handle = nullptr;
  }
}

/// A path's paint in a [Mesh].
enum MeshPaint() {
  color,
  linearGradient,
  radialGradient,
}

/// One of a [Mesh]'s paths, in paint order: a shape's fill or stroke, or a
/// [Glow]'s halo or core.
class const MeshPath({
  /// Its paint: a color, or a gradient.
  required final MeshPaint paint,

  /// The index in [Mesh.indices] where its triangles begin, 3 indices each.
  required final int indexBegin,

  /// The number of its triangles' indices in [Mesh.indices], from
  /// [indexBegin].
  required final int indexCount,

  /// A color paint's r, g, b and a, premultiplied.
  required final Float32List color,

  /// A gradient's transform from the SVG's coordinates into the gradient's
  /// own.
  ///
  /// There, a linear gradient's offset is y, and a radial one's is the
  /// distance from 0, 0. Beyond the first and last stops, the color is
  /// theirs.
  required final Transform gradient,

  /// The index of a gradient's first stop in [Mesh.stops], 5 floats each.
  required final int stopBegin,

  /// The number of a gradient's stops in [Mesh.stops], from [stopBegin].
  required final int stopCount,

  /// A stroke's half width, 0 for a fill or a hairline.
  required final double halfWidth,

  /// Whether it's a [Glow]'s halo.
  required final bool isHalo,
});

/// An SVG, or plain paths' polylines, imported once into triangles.
///
/// The triangles are in the paths' coordinates, y down, as a [Scene]'s. Fills
/// are tessellated with their winding rule. Strokes are outlined with their
/// joins, caps and dashes. So each path's triangles in [indices] are its
/// coverage, and never overlap. Its arrays are copies, so it keeps nothing
/// native.
class Mesh._(raw.RaMeshData n) {
  this
    : vertices = _floats(n.vertices, n.vertexCount * n.vertexFloats),
      vertexFloats = n.vertexFloats,
      indices = _indices(n.indices, n.indexCount, n.indexSize),
      stripIndices = n.stripIndexCount == 0
          ? null
          : _indices(n.stripIndices, n.stripIndexCount, n.indexSize),
      paths = List.unmodifiable([
        for (var i = 0; i < n.pathCount; i++) _path(n.paths[i]),
      ]),
      stops = _floats(n.stops, n.stopCount * 5),
      bounds = _bounds(n.bounds),
      svgBounds = _bounds(n.svgBounds);

  /// Imports an SVG's bytes.
  ///
  /// It flattens the SVG's curves to within 1/4 of a device pixel when its
  /// longer side is [maxSize] device pixels, the largest size it's drawn at.
  ///
  /// Throws an [ArgumentError] if the bytes can't be parsed, or [maxSize]
  /// isn't a positive finite number.
  factory Mesh.fromSvgBytes(Uint8List bytes, {required double maxSize}) {
    if (!(maxSize > 0) || !maxSize.isFinite) {
      throw ArgumentError.value(
        maxSize,
        'maxSize',
        'Not a positive finite number',
      );
    }
    final handle = using((arena) {
      // An allocation of 0 bytes may return null, so allocate at least 1.
      final data = arena<Uint8>(bytes.length + 1)
        ..asTypedList(bytes.length).setAll(0, bytes);
      return raw.ra_mesh_from_svg_data(data.cast(), bytes.length, maxSize);
    });
    if (handle == nullptr) {
      throw ArgumentError('Not parseable SVG data');
    }
    return _copied(handle);
  }

  /// Imports [draws] of [contours]' paths, the contours' lists one after the
  /// other.
  ///
  /// It imports them as [Mesh.fromSvgBytes] imports an SVG's shapes. Round
  /// joins and caps stay within [tolerance] of their arcs, in the paths'
  /// units. The mesh's [svgBounds] are [viewBox]. Paths with points that
  /// aren't finite aren't imported.
  ///
  /// With [glow], each path drawn gets a halo, which comes in [paths] before
  /// all the draws' own paths. Each draw gets a core, which comes right after
  /// the draw's own path.
  ///
  /// Throws an [ArgumentError] if a draw's path isn't among the contours'
  /// paths, or [tolerance] isn't positive.
  factory Mesh.fromPaths(
    List<PathContours> contours,
    List<PathDraw> draws,
    Bounds viewBox, {
    required double tolerance,
    Glow? glow,
  }) {
    if (!(tolerance > 0) || !tolerance.isFinite) {
      throw ArgumentError.value(tolerance, 'tolerance', 'Not positive');
    }
    final handle = using((arena) {
      final nativeGlow = glow == null ? nullptr : glow._toNative(arena);
      return _withPaths(
        contours,
        draws,
        (c, d) => raw.ra_mesh_from_paths(
          c,
          d,
          draws.length,
          viewBox._toNative(),
          tolerance,
          nativeGlow,
        ),
      );
    });
    // The core returns null when it runs out of memory.
    if (handle == nullptr) {
      throw OutOfMemoryError();
    }
    return _copied(handle);
  }

  /// Copies [handle]'s arrays into a mesh, then releases [handle].
  static Mesh _copied(Pointer<raw.RaMeshHandle> handle) {
    try {
      return Mesh._(raw.ra_mesh_data(handle));
    } finally {
      raw.ra_mesh_release(handle);
    }
  }

  // An empty native vector's data may be null, which asTypedList rejects.
  static Float32List _floats(Pointer<Float> p, int length) => length == 0
      ? Float32List(0)
      : Float32List.fromList(p.asTypedList(length));

  static TypedData _indices(Pointer<Void> p, int count, int indexSize) =>
      count == 0
      ? Uint16List(0)
      : indexSize == 2
      ? Uint16List.fromList(p.cast<Uint16>().asTypedList(count))
      : Uint32List.fromList(p.cast<Uint32>().asTypedList(count));

  static MeshPath _path(raw.RaMeshPath p) {
    final t = p.gradient;
    return MeshPath(
      paint: MeshPaint.values[p.type],
      indexBegin: p.indexBegin,
      indexCount: p.indexCount,
      color: Float32List.fromList([p.r, p.g, p.b, p.a]),
      gradient: Transform(t.a, t.b, t.c, t.d, t.tx, t.ty),
      stopBegin: p.stopBegin,
      stopCount: p.stopCount,
      halfWidth: p.halfWidth,
      isHalo: p.halo != 0,
    );
  }

  /// The vertices, [vertexFloats] floats each.
  ///
  /// Each vertex holds x, y and its path's index, all floats, as OpenGL ES
  /// vertex attributes can't be integers. In a mesh with strokes, an offset
  /// follows: x and y in half widths, from the point of the stroke's polyline
  /// that the vertex is built around. The offset is 0 for the vertices of
  /// fills and of strokes' unions.
  ///
  /// In a mesh with a [Glow], the vertex's glow comes last. It's 1 for a
  /// draw's own vertices. It goes from 1 at a path's edge to 0 at its halo's
  /// edge, and from 1 up to 2 in the middle of a core.
  final Float32List vertices;

  /// The number of floats per vertex in [vertices]: 3, 5 in a mesh with
  /// strokes, or 6 in a mesh with a [Glow].
  final int vertexFloats;

  /// The triangles' indices, 3 each, in paint order.
  ///
  /// They're a [Uint16List] when each index is below 0xFFFF, which some APIs
  /// keep for primitive restart, else a [Uint32List]. A stroke that overlaps
  /// itself comes as its union, whose vertices have no offsets.
  final TypedData indices;

  /// The same as [indices], but with opaque strokes that overlap themselves
  /// as their strips, or null if there are none.
  ///
  /// Only those strokes differ. Their strips have offsets. They're for
  /// instances drawn without an opacity, where the overlaps can't show.
  final TypedData? stripIndices;

  /// Its paths, in paint order.
  final List<MeshPath> paths;

  /// The gradients' stops, 5 floats each: an offset, then r, g, b and a,
  /// unpremultiplied, as SVG interpolates them.
  ///
  /// Each offset is from 0 to 1, and never below the previous stop's.
  final Float32List stops;

  /// The vertices' bounds, and the SVG's own rectangle, as [Scene.svgBounds].
  final Bounds bounds, svgBounds;

  int get vertexCount => vertices.length ~/ vertexFloats;
  int get indexCount => indices.lengthInBytes ~/ indices.elementSizeInBytes;

  /// Whether every path is opaque: its color's alpha, or each of its
  /// gradient's stops' alpha, is 1.
  ///
  /// A mesh with a [Glow] never is, as its halos fade out whatever their
  /// alpha.
  bool get isOpaque {
    if (vertexFloats == 6) {
      return false;
    }
    for (final p in paths) {
      if (p.paint == MeshPaint.color) {
        if (p.color[3] != 1) {
          return false;
        }
        continue;
      }
      if (p.stopCount == 0) {
        return false;
      }
      for (var k = p.stopBegin; k < p.stopBegin + p.stopCount; k++) {
        if (stops[5 * k + 4] != 1) {
          return false;
        }
      }
    }
    return true;
  }
}

/// A Ra::SceneList: scenes, each with its own transform, under the list's
/// transform.
class SceneList() implements Finalizable {
  this : _handle = raw.ra_list_create() {
    // The core returns null when it runs out of memory.
    if (_handle == nullptr) {
      throw OutOfMemoryError();
    }
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<raw.RaListHandle>)>>(
      raw.ra_list_release,
    ).cast(),
  );

  Pointer<raw.RaListHandle> _handle;
  Transform _ctm = const Transform.identity();

  /// Adds [scene], with [ctm] as its transform.
  ///
  /// The list keeps its own reference to [scene], so [scene] can be disposed
  /// of afterwards. The list skips empty scenes.
  void addScene(Scene scene, [Transform ctm = const Transform.identity()]) =>
      raw.ra_list_add_scene(_live, scene._live, ctm._toNative());

  Transform get ctm => _ctm;
  set ctm(Transform ctm) {
    raw.ra_list_set_ctm(_live, ctm._toNative());
    _ctm = ctm;
  }

  Params get params => Params._fromNative(raw.ra_list_params(_live));
  set params(Params params) =>
      raw.ra_list_set_params(_live, params._toNative());

  /// The scenes' bounds, through their own transforms but not the list's.
  Bounds get bounds => _bounds(raw.ra_list_bounds(_live));

  /// Replaces the scenes with [count] entries at [entries], [entrySize] bytes
  /// each.
  ///
  /// Each entry holds:
  /// - its scene's [Scene.address], as a 64-bit integer;
  /// - its transform, as 6 floats at [entryCtm];
  /// - the rectangle in device pixels that clips its draws, as 4 floats at
  ///   [entryDeviceClip];
  /// - its opacity, from 0 to 1, which scales its draws' alpha, as a float at
  ///   [entryOpacity];
  /// - its color matrix, as a uint32 at [entryColorMatrix]: 0 for none, else
  ///   1 + the matrix's index in [setColorMatrices]' matrices.
  ///
  /// The scenes mustn't be disposed of before this call. The list then keeps
  /// its own references. It skips empty scenes. Its frames skip the scenes
  /// whose opacity is 0, or whose matrix makes them transparent.
  void setEntries(Pointer<Uint8> entries, int count) =>
      raw.ra_list_set_entries(_live, entries, count);

  /// Sets the color matrices that the next [setEntries]' entries refer to.
  ///
  /// [matrices] holds [count] 4 x 4 matrices on premultiplied RGBA, 16 floats
  /// each, row by row. Their rows and columns are r, g, b and a. Each color
  /// they transform is clamped from 0 to its alpha.
  void setColorMatrices(Pointer<Float> matrices, int count) =>
      raw.ra_list_set_color_matrices(_live, matrices, count);

  /// An entry's size in [setEntries], and its fields' offsets.
  static const entrySize = raw.listEntrySize,
      entryCtm = raw.listEntryCtm,
      entryDeviceClip = raw.listEntryDeviceClip,
      entryOpacity = raw.listEntryOpacity,
      entryColorMatrix = raw.listEntryColorMatrix;

  Pointer<raw.RaListHandle> get _live =>
      _handle == nullptr ? throw StateError('SceneList disposed') : _handle;

  void dispose() {
    if (_handle == nullptr) {
      return;
    }
    _finalizer.detach(this);
    raw.ra_list_release(_handle);
    _handle = nullptr;
  }
}

/// Holds one frame's bytes.
///
/// A host keeps one per frame in flight, as rendering into it invalidates its
/// last [Frame].
class FrameBuffer() implements Finalizable {
  this : _handle = raw.ra_frame_buffer_create() {
    // The core returns null when it runs out of memory.
    if (_handle == nullptr) {
      throw OutOfMemoryError();
    }
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<
          NativeFunction<Void Function(Pointer<raw.RaFrameBufferHandle>)>
        >(raw.ra_frame_buffer_release)
        .cast(),
  );

  Pointer<raw.RaFrameBufferHandle> _handle;

  /// Counts the renders into the buffer, and its dispose, so a [Frame] can
  /// tell that its bytes were overwritten.
  int _generation = 0;

  Pointer<raw.RaFrameBufferHandle> get _live =>
      _handle == nullptr ? throw StateError('FrameBuffer disposed') : _handle;

  void dispose() {
    if (_handle == nullptr) {
      return;
    }
    _finalizer.detach(this);
    raw.ra_frame_buffer_release(_handle);
    _handle = nullptr;
    _generation++;
  }
}

/// Writes frames.
///
/// It keeps the per-thread contexts that frames reuse.
class Renderer() implements Finalizable {
  this : _handle = raw.ra_renderer_create() {
    // The core returns null when it runs out of memory.
    if (_handle == nullptr) {
      throw OutOfMemoryError();
    }
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  static final _finalizer = NativeFinalizer(
    Native.addressOf<
          NativeFunction<Void Function(Pointer<raw.RaRendererHandle>)>
        >(raw.ra_renderer_release)
        .cast(),
  );

  Pointer<raw.RaRendererHandle> _handle;

  /// Writes [list]'s frame for a [width] x [height] view in points, at [scale]
  /// device pixels per point, into [buffer].
  Frame render(
    SceneList list,
    double width,
    double height,
    double scale,
    FrameBuffer buffer,
  ) {
    if (_handle == nullptr) {
      throw StateError('Renderer disposed');
    }
    final frame = raw.ra_render(
      _handle,
      list._live,
      width,
      height,
      scale,
      buffer._live,
    );
    // The buffer's last frame is overwritten either way.
    final generation = ++buffer._generation;
    // The frame is empty when the core runs out of memory.
    if (frame.base == nullptr) {
      throw OutOfMemoryError();
    }
    return Frame._(frame, buffer, generation);
  }

  void dispose() {
    if (_handle == nullptr) {
      return;
    }
    _finalizer.detach(this);
    raw.ra_renderer_release(_handle);
    _handle = nullptr;
  }
}

/// The types of a frame's entries: Ra::Buffer::Type, in its order.
enum EntryType() {
  quadEdges,
  fastEdges,
  fastMolecules,
  quadMolecules,
  opaques,
  instances,
  segmentsBase,
  instancesBase,
  disableClip,
  enableClip,
  clipMask,
  blendInstances;

  /// The size of each struct that an entry of this type spans, or 0 if the
  /// entry's begin and end aren't a byte range.
  int get itemSize => switch (this) {
    quadEdges || fastEdges || fastMolecules || quadMolecules => layout.edge,
    opaques => layout.opaque,
    instances || blendInstances => layout.instance,
    segmentsBase => layout.segment,
    instancesBase || disableClip || enableClip || clipMask => 0,
  };
}

/// One of a [Frame]'s entries: a Ra::Buffer::Entry.
///
/// For byte ranges, [begin] and [end] are offsets into [Frame.bytes]. An
/// [EntryType.instancesBase]'s begin is the offset of its pass's instances,
/// and its end tells the accumulation rows that its group uses. An
/// [EntryType.clipMask]'s begin packs its device bounds, and its end is the
/// mask's identity.
class const Entry(final EntryType type, final int begin, final int end) {
  /// Whether [begin] and [end] are a byte range.
  bool get isRange => type.itemSize != 0;

  /// The number of structs it spans: for a draw, its instance count.
  int get count => isRange ? (end - begin) ~/ type.itemSize : 0;

  @override
  String toString() => '${type.name}($begin, $end${isRange ? ', $count' : ''})';
}

/// One frame: the bytes to upload, the entries to draw them with, and where
/// their sections begin.
class Frame._(raw.RaFrame n, final FrameBuffer _buffer, final int _generation) {
  this
    : _bytes = n.base.asTypedList(n.size),
      entries = List.unmodifiable([
        for (var i = 0; i < n.entryCount; i++)
          Entry(
            EntryType.values[n.entries[i].type],
            n.entries[i].begin,
            n.entries[i].end,
          ),
      ]),
      colors = n.colors,
      paths = n.paths,
      texStrips = n.texStrips,
      p16s = n.p16s,
      pathsCount = n.pathsCount,
      texCount = n.texCount,
      headerSize = n.headerSize,
      params = Params._fromNative(n.params);

  final Uint8List _bytes;

  /// A view of the frame buffer's native memory.
  ///
  /// It's valid until the next render into the buffer, or the buffer's
  /// dispose. After that, this getter throws. Don't keep the view: a view
  /// read before then still points at that memory afterwards.
  Uint8List get bytes => _generation == _buffer._generation
      ? _bytes
      : throw StateError('Frame overwritten by a later render');

  /// The entries to draw [bytes] with, in order.
  final List<Entry> entries;

  /// Offsets into [bytes]. The header holds the colors, in whole rows of the
  /// color texture, then the paths. The gradient strips follow the opaques,
  /// and the 16-bit points follow the strips.
  final int colors, paths, texStrips, p16s;
  final int pathsCount, texCount, headerSize;
  final Params params;

  int get size => _bytes.length;
}
