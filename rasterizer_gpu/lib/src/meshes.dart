import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'core.dart' as ra;
import '../rasterizer_gpu.dart';
import 'atlas.dart' show maxPageSize, onMeshFrame;
import 'atlas_pages.dart';
import 'image_run.dart';
import 'mesh_gpu.dart';
import 'switching.dart';

// The mesh renderer. It imports SVGs and plain paths once into meshes, whose
// triangles stay in GPU buffers. Each frame, it draws them under their
// entries' transforms, each run into its own target.

/// A scene imported into a mesh, for the mesh renderer: an SVG or plain
/// paths.
///
/// Its triangles are in the scene's units. They stay in GPU buffers from the
/// first time a run adds the scene until it's disposed of. Made without a GPU,
/// as in unit tests, it still has the import's bounds and counts.
class MeshScene(ra.Mesh mesh) implements RasterizerScene {
  /// Keeps [mesh] until a run first adds the scene, which uploads it.
  this
    : _mesh = mesh,
      bounds = _rect(mesh.bounds),
      viewBox = ui.Rect.fromLTRB(
        mesh.svgBounds.lx,
        mesh.svgBounds.ly,
        mesh.svgBounds.ux,
        mesh.svgBounds.uy,
      ),
      pathCount = mesh.paths.length;

  @override
  RasterizerBackend get backend => RasterizerBackend.mesh;

  @override
  final ui.Rect bounds, viewBox;

  /// The number of the mesh's [ra.Mesh.paths], so a glow's halos and cores
  /// count.
  @override
  final int pathCount;

  /// The import, until it's uploaded.
  ra.Mesh? _mesh;
  MeshBuffers? _buffers;

  /// For tests: the import, until it's uploaded.
  @visibleForTesting
  ra.Mesh? get debugMesh => _mesh;

  /// The scene's buffers, uploaded when a run first adds the scene.
  ///
  /// Null once the scene is disposed of, or if it has no triangles.
  MeshBuffers? get _uploaded {
    final mesh = _mesh;
    if (mesh != null) {
      _buffers = MeshBuffers.upload(mesh);
      _mesh = null;
    }
    return _buffers;
  }

  @override
  void drawPaths(
    ui.Canvas canvas, {
    double opacity = 1,
    RasterizerColorTransform? colorTransform,
  }) => throw StateError('A mesh scene has no paths to draw with dart:ui');

  @override
  void dispose() {
    _mesh = null;
    _buffers = null;
  }

  // Bounds without an area, such as a straight hairline's, are kept.
  static ui.Rect _rect(ra.Bounds b) =>
      b.isNull || !(b.ux >= b.lx && b.uy >= b.ly)
      ? ui.Rect.zero
      : ui.Rect.fromLTRB(b.lx, b.ly, b.ux, b.uy);
}

/// The mesh renderer: it renders each run into its own target.
///
/// The targets come from a pool per frame in flight. So a frame's images stay
/// valid for [slots] frames, until its targets are rendered into again.
/// Targets have the samples per pixel asked for, 1 or 4, where offscreen MSAA
/// is supported, else 1.
///
/// A run's targets are one size in every frame in flight, so they share a
/// multisampled texture. They're sized as atlas pages are, one page per run
/// ([AtlasPages]). They grow at once. They shrink at the end of a window of
/// 120 frames that all needed below [shrinkBelow] of their area, or after a
/// viewport change. A run's targets that no frame needed for a window are
/// released.
class MeshRenderer(
  gpu.ShaderLibrary library,
  @override final int slots,
  int samples,
) implements RasterizerRenderer {
  this
    : _gpu = MeshGpu(library, samples),
      _targets = List.generate(slots, (_) => []),
      _instances = List.generate(slots, (_) => MeshInstances());

  /// A run's targets shrink at the end of a window whose frames all needed
  /// below this share of their area.
  ///
  /// It's more than atlas pages' half, so a run that covered the viewport,
  /// then much less of it, gives most of its target back.
  static const shrinkBelow = 0.75;

  @override
  RasterizerBackend get backend => RasterizerBackend.mesh;

  final MeshGpu _gpu;

  // Per frame in flight: its runs' targets, in the order the runs are placed,
  // and the buffer for its instance records.
  final List<List<MeshTarget>> _targets;
  final List<MeshInstances> _instances;

  // The sizes of the runs' targets, one page per run.
  final AtlasPages _sizes = AtlasPages(
    maxPageSize,
    step: MeshGpu.targetStep,
    shrinkBelow: shrinkBelow,
  );
  int _frames = 0, _resizes = 0;
  bool _disposed = false, _trimPending = false;

  /// The one frame, which each [beginFrame] reuses.
  late final MeshFrame _frame = MeshFrame._(this);

  /// Targets' samples per pixel: 1 unless offscreen MSAA is supported.
  int get samples => _gpu.samples;

  /// Whether targets are multisampled.
  bool get multisampled => _gpu.multisampled;

  @override
  int get maxViewportSize => maxPageSize;

  @override
  int get atlasResizes => _gpu.resizes;

  @override
  int get atlasBytes {
    var n = _gpu.multisampledBytes;
    for (final slot in _targets) {
      for (final target in slot) {
        n += target.texture?.getBaseMipLevelSizeInBytes() ?? 0;
      }
    }
    return n;
  }

  @override
  void trimAtlas() {
    if (_disposed) {
      return;
    }
    if (_frame._open) {
      _trimPending = true;
      return;
    }
    _sizes.trim();
    for (final slot in _targets) {
      slot.clear();
    }
    _gpu.releaseMultisampled(const []);
  }

  /// Ends a [width] x [height] frame whose runs needed targets of the [needs]
  /// sizes.
  ///
  /// At the end of a window, the targets' sizes shrink. It releases the
  /// targets of runs that no frame had for a window, and the multisampled
  /// textures of sizes that no target has any more.
  void _endFrame(int width, int height, List<(int, int)> needs) {
    _sizes.endFrame(width, height, needs);
    var released = _gpu.resizes != _resizes;
    _resizes = _gpu.resizes;
    for (final slot in _targets) {
      if (slot.length > _sizes.length) {
        slot.removeRange(_sizes.length, slot.length);
        released = true;
      }
    }
    if (released) {
      _gpu.releaseMultisampled([for (final s in _targets) ...s]);
    }
  }

  @override
  MeshFrame beginFrame(int width, int height, {bool curves = true}) {
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
    return _frame.._begin(width, height);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final slot in _targets) {
      for (final target in slot) {
        target.image?.dispose();
      }
      slot.clear();
    }
    _gpu.releaseMultisampled(const []);
  }
}

/// A mesh renderer's frame: its runs' entries, which [render] renders into
/// each run's own target.
///
/// [MeshRenderer.beginFrame]'s `curves` doesn't apply, as the import flattened
/// the meshes' curves.
class MeshFrame._(final MeshRenderer _renderer) implements RasterizerFrame {
  final List<MeshRun> _runs = [];
  int _runCount = 0, _width = 0, _height = 0, _slot = 0, _frame = 0;
  bool _rendered = false;

  // The margin around a run's entries' bounds, in pixels.
  static const _margin = 1;

  // How far past its bounds, in pixels, ra_mesh_stroked.vert can push a
  // stroke: the largest least half width, 0.5, times the longest offset it
  // counts, 4.
  static const _strokeReach = 2.0;

  // The runs placed with something to draw, which take the slot's targets in
  // that order.
  final List<MeshRun> _placed = [];

  // The sizes those runs needed, which their pages follow.
  List<(int, int)> _needs = [];

  // The entries, in the order they were added: their scenes, transforms (9
  // values each, a b c d tx ty g h i), opacities and color transforms.
  final List<MeshScene> _scenes = [];
  final List<RasterizerColorTransform?> _colorTransforms = [];
  Float64List _ctms = Float64List(9 * 256);
  Float32List _opacities = Float32List(256);

  // The instance records, run by run, as MeshGpu reads them.
  Float32List _records = Float32List(MeshGpu.instanceFloats * 256);

  @override
  int cpuMicros = 0, uploadMicros = 0, encodeMicros = 0;

  /// The sizes of the runs' targets.
  @override
  final List<(int, int)> pageSizes = [];

  @override
  RasterizerBackend get backend => RasterizerBackend.mesh;

  @override
  int get width => _width;
  @override
  int get height => _height;
  @override
  int get entryCount => _scenes.length;

  @override
  Iterable<MeshRun> get runs => _runs.take(_runCount);

  void _begin(int width, int height) {
    final renderer = _renderer;
    _width = width;
    _height = height;
    _rendered = false;
    _runCount = 0;
    _scenes.clear();
    _colorTransforms.clear();
    _placed.clear();
    // A new list, as the renderer's pages keep the last frame's.
    _needs = [];
    pageSizes.clear();
    _frame = ++renderer._frames;
    _slot = _frame % renderer.slots;
  }

  @override
  MeshRun addRun() {
    _checkOpen();
    if (_runCount == _runs.length) {
      _runs.add(MeshRun._(this, _runCount));
    }
    return _runs[_runCount++].._reset();
  }

  /// Adds an entry of [scene] to [run], unless it draws nothing in the
  /// viewport.
  void _add(
    MeshRun run,
    RasterizerScene scene,
    double a,
    double b,
    double c,
    double d,
    double tx,
    double ty,
    double g,
    double h,
    double w,
    double opacity,
    RasterizerColorTransform? colorTransform,
  ) {
    _checkOpen();
    if (run._placed) {
      throw StateError('RasterizerRun already placed');
    }
    scene = resolveScene(scene, RasterizerBackend.mesh);
    if (scene is! MeshScene) {
      throw ArgumentError.value(
        scene,
        'scene',
        'Not a scene for the mesh renderer',
      );
    }
    final buffers = scene._uploaded;
    if (!(opacity > 0) || buffers == null) {
      return;
    }
    final r = scene.bounds;
    // Empty bounds draw nothing, except a straight hairline's: its vertices
    // are its points, and the stroke shader widens them.
    if (r.isEmpty && !buffers.stroked) {
      return;
    }
    double minX, minY, maxX, maxY;
    if (g == 0 && h == 0 && w == 1) {
      // The bounds' corners through the transform, in the viewport.
      final x0 = a * r.left + c * r.top + tx, y0 = b * r.left + d * r.top + ty;
      final dxw = a * r.width,
          dyw = b * r.width,
          dxh = c * r.height,
          dyh = d * r.height;
      minX = x0 + (dxw < 0 ? dxw : 0) + (dxh < 0 ? dxh : 0);
      maxX = x0 + (dxw > 0 ? dxw : 0) + (dxh > 0 ? dxh : 0);
      minY = y0 + (dyw < 0 ? dyw : 0) + (dyh < 0 ? dyh : 0);
      maxY = y0 + (dyw > 0 ? dyw : 0) + (dyh > 0 ? dyh : 0);
    } else {
      // Projected, the bounds are the corners' if all are in front of the
      // eye. If only some are, or one is so close to the eye's plane that it
      // projects to infinity, they're the viewport. If none are, the entry is
      // clipped away.
      minX = minY = double.infinity;
      maxX = maxY = double.negativeInfinity;
      var behind = 0;
      for (final (x, y) in [
        (r.left, r.top),
        (r.right, r.top),
        (r.left, r.bottom),
        (r.right, r.bottom),
      ]) {
        final q = g * x + h * y + w;
        if (!(q > 0)) {
          behind++;
          continue;
        }
        final px = (a * x + c * y + tx) / q, py = (b * x + d * y + ty) / q;
        if (px < minX) {
          minX = px;
        }
        if (px > maxX) {
          maxX = px;
        }
        if (py < minY) {
          minY = py;
        }
        if (py > maxY) {
          maxY = py;
        }
      }
      if (behind == 4) {
        return;
      }
      if (behind > 0 ||
          minX.isInfinite ||
          minY.isInfinite ||
          maxX.isInfinite ||
          maxY.isInfinite) {
        minX = minY = 0;
        maxX = _width.toDouble();
        maxY = _height.toDouble();
      }
    }
    if (buffers.stroked) {
      minX -= _strokeReach;
      minY -= _strokeReach;
      maxX += _strokeReach;
      maxY += _strokeReach;
    }
    // Off the viewport, or NaN.
    if (!(maxX > 0 && maxY > 0 && minX < _width && minY < _height)) {
      return;
    }
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

    final i = _scenes.length;
    if (i == _opacities.length) {
      _ctms = Float64List(_ctms.length * 2)..setAll(0, _ctms);
      _opacities = Float32List(_opacities.length * 2)..setAll(0, _opacities);
    }
    _scenes.add(scene);
    _colorTransforms.add(colorTransform);
    _opacities[i] = opacity < 1 ? opacity : 1;
    _ctms
      ..[9 * i] = a
      ..[9 * i + 1] = b
      ..[9 * i + 2] = c
      ..[9 * i + 3] = d
      ..[9 * i + 4] = tx
      ..[9 * i + 5] = ty
      ..[9 * i + 6] = g
      ..[9 * i + 7] = h
      ..[9 * i + 8] = w;
    run._entries.add(i);
  }

  /// Places [run] in the slot's next target.
  ///
  /// The run covers its entries' bounds with the margin, rounded out and
  /// clipped to the viewport. Its target is the size of its page, which fits
  /// that.
  void _place(MeshRun run) {
    run._placed = true;
    if (run._entries.isEmpty) {
      return;
    }
    final lx = (run._lx.floor() - _margin).clamp(0, _width),
        ly = (run._ly.floor() - _margin).clamp(0, _height);
    final ux = (run._ux.ceil() + _margin).clamp(0, _width),
        uy = (run._uy.ceil() + _margin).clamp(0, _height);
    final w = ux - lx, h = uy - ly;
    if (w <= 0 || h <= 0) {
      return;
    }
    final renderer = _renderer, targets = renderer._targets[_slot];
    final index = _placed.length;
    if (index == targets.length) {
      targets.add(MeshTarget());
    }
    final target = run._target = targets[index];
    final (pageWidth, pageHeight) = renderer._sizes.fit(index, w, h);
    renderer._gpu.fit(target, pageWidth, pageHeight);
    _needs.add((w, h));
    _placed.add(run);
    run
      .._x = lx
      .._y = ly
      ..parts = [
        RasterizerRunPart(
          index,
          target.image!,
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Rect.fromLTWH(
            lx.toDouble(),
            ly.toDouble(),
            w.toDouble(),
            h.toDouble(),
          ),
        ),
      ];
  }

  @override
  void render() {
    _checkOpen();
    _rendered = true;
    final renderer = _renderer, gpu = renderer._gpu;
    final watch = Stopwatch()..start();
    for (final run in runs) {
      if (!run._placed) {
        _place(run);
      }
    }
    var count = 0;
    for (final run in _placed) {
      count += run._entries.length;
    }
    if (MeshGpu.instanceFloats * count > _records.length) {
      _records = Float32List(MeshGpu.instanceFloats * count * 2);
    }
    var k = 0;
    for (final run in _placed) {
      final texture = run._target!.texture!;
      pageSizes.add((texture.width, texture.height));
      for (final i in run._entries) {
        _write(k++, i, run._x.toDouble(), run._y.toDouble());
      }
    }
    cpuMicros = watch.elapsedMicroseconds;
    watch.reset();

    uploadMicros = encodeMicros = 0;
    if (count > 0) {
      gpu.beginFrame();
      final instances = renderer._instances[_slot];
      final buffer = gpu.upload(instances, _records, count);
      uploadMicros = watch.elapsedMicroseconds;
      watch.reset();
      // Consecutive entries that show the same scene make one draw. For an
      // opaque mesh, or one with strips, the draw splits where entries start
      // or stop keeping the scene's alpha. An opaque mesh's entries that keep
      // it draw without blending. A mesh's entries that keep it draw its
      // strips, which keep the least width, and the others its strokes'
      // unions, as a strip would blend twice where it overlaps itself. For a
      // mesh with gradients, the draw also splits where entries start or stop
      // having a color transform, or change it. Only entries with one read it
      // for each fragment, as their draw's uniform.
      var first = 0;
      for (final (r, run) in _placed.indexed) {
        gpu.beginPass(run._target!, buffer);
        final entries = run._entries;
        for (var j = 0; j < entries.length;) {
          final scene = _scenes[entries[j]], buffers = scene._buffers;
          final opaque = buffers?.opaque ?? false,
              strips = buffers?.stripIndices != null,
              gradients = buffers?.gradients ?? false;
          final splits = opaque || strips,
              keeps = splits && _keepsAlpha(entries[j]),
              transformed = gradients && _colorTransforms[entries[j]] != null;
          var n = 1;
          while (j + n < entries.length &&
              identical(_scenes[entries[j + n]], scene) &&
              (!splits || _keepsAlpha(entries[j + n]) == keeps) &&
              (!gradients ||
                  (transformed
                      ? _sameRows(first + j, first + j + n)
                      : _colorTransforms[entries[j + n]] == null))) {
            n++;
          }
          if (buffers != null) {
            final o = MeshGpu.instanceFloats * (first + j) + 12;
            gpu.draw(
              buffers,
              first + j,
              n,
              blend: !(opaque && keeps),
              strips: strips && keeps,
              colorTransform: transformed
                  ? Float32List.sublistView(_records, o, o + 16)
                  : null,
            );
          }
          j += n;
        }
        first += entries.length;
        gpu.endPass(instances, last: r == _placed.length - 1);
      }
      encodeMicros = watch.elapsedMicroseconds;
    }
    renderer._endFrame(_width, _height, _needs);
    if (renderer._trimPending) {
      renderer._trimPending = false;
      renderer.trimAtlas();
    }
    onMeshFrame?.call();
  }

  /// Writes entry [i]'s instance record at [k], its transform moved from the
  /// viewport to its run's target at [ox], [oy].
  ///
  /// x - ox is ((a - ox g) x + (c - ox h) y + tx - ox w) over w's row, and
  /// the same goes for y.
  void _write(int k, int i, double ox, double oy) {
    final o = MeshGpu.instanceFloats * k, t = 9 * i, r = _records, m = _ctms;
    final g = m[t + 6], h = m[t + 7], w = m[t + 8];
    r
      ..[o] = m[t] - ox * g
      ..[o + 1] = m[t + 2] - ox * h
      ..[o + 2] = m[t + 4] - ox * w
      ..[o + 4] = m[t + 1] - oy * g
      ..[o + 5] = m[t + 3] - oy * h
      ..[o + 6] = m[t + 5] - oy * w
      ..[o + 8] = g
      ..[o + 9] = h
      ..[o + 10] = w;
    final s = _opacities[i], c = _colorTransforms[i]?.values;
    for (var j = 0; j < 16; j++) {
      r[o + 12 + j] = (c == null ? (j % 5 == 0 ? 1.0 : 0.0) : c[j]) * s;
    }
  }

  /// Whether the instance records at [a] and [b] have the same color
  /// transform rows, scaled by their opacity.
  bool _sameRows(int a, int b) {
    final r = _records,
        i = MeshGpu.instanceFloats * a + 12,
        k = MeshGpu.instanceFloats * b + 12;
    for (var j = 0; j < 16; j++) {
      if (r[i + j] != r[k + j]) {
        return false;
      }
    }
    return true;
  }

  /// Whether entry [i] keeps its scene's alpha: its opacity is 1, and its
  /// color transform's alpha row, if any, is 0, 0, 0, 1.
  bool _keepsAlpha(int i) {
    final c = _colorTransforms[i]?.values;
    return _opacities[i] == 1 &&
        (c == null || (c[12] == 0 && c[13] == 0 && c[14] == 0 && c[15] == 1));
  }

  /// Whether the frame has begun and isn't rendered yet.
  bool get _open => _width > 0 && !_rendered;

  void _checkOpen() {
    if (_renderer._disposed) {
      throw StateError('RasterizerRenderer disposed');
    }
    if (_rendered) {
      throw StateError('RasterizerFrame already rendered: begin a new one');
    }
  }
}

/// A mesh renderer's run, drawn as an image from its target.
class MeshRun._(final MeshFrame _frame, @override final int index)
    extends ImageRun {
  // The run's entries and their bounds in the viewport. Once placed, its
  // target and its place in the viewport.
  final List<int> _entries = [];
  double _lx = double.infinity,
      _ly = double.infinity,
      _ux = double.negativeInfinity,
      _uy = double.negativeInfinity;
  MeshTarget? _target;
  int _x = 0, _y = 0;
  bool _placed = false;

  @override
  List<RasterizerRunPart> parts = const [];

  @override
  bool get isEmpty => _placed ? parts.isEmpty : _entries.isEmpty;

  void _reset() {
    _entries.clear();
    _lx = _ly = double.infinity;
    _ux = _uy = double.negativeInfinity;
    _target = null;
    _placed = false;
    parts = const [];
  }

  @override
  void place() {
    _frame._checkOpen();
    if (!_placed) {
      _frame._place(this);
    }
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
  }) => _frame._add(
    this,
    scene,
    a,
    b,
    c,
    d,
    tx,
    ty,
    0,
    0,
    1,
    opacity,
    colorTransform,
  );

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
  }) => _frame._add(
    this,
    scene,
    a,
    b,
    c,
    d,
    tx,
    ty,
    g,
    h,
    i,
    opacity,
    colorTransform,
  );
}
