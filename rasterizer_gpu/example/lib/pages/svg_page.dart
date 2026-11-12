import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import '../affine.dart';
import '../core_frames.dart';
import '../layout_size.dart';
import '../scenes.dart';

/// An SVG asset, fitted to the page, that rasterizer_gpu renders as one run.
///
/// Drag or pinch to pan and zoom, scroll to zoom, and double tap to reset.
/// The page renders at most once per frame, however many changes come
/// before it. It logs the first render with a `RASTERIZER_SVG` line.
///
/// For the mesh renderer, the page flattens the SVG's curves at load, for
/// the window's size zoomed in up to 20x, as far as the sweep zooms. Zoomed
/// in further, the curves show their segments.
///
/// With [sweep], it runs the fixed pan-and-zoom sweep of [sweepFrames]
/// frames instead, one render per frame: see [sweepView]. It then logs
/// `RASTERIZER_SWEEP` timing statistics. The golden tests render the
/// sweep's checkpoints.
class const SvgPage({
  super.key,
  required final String asset,

  /// The GPU renderer to use where it's supported, as
  /// [RasterizerRenderer.create] takes it.
  final RasterizerBackend gpu = RasterizerBackend.gpu,

  /// Whether the GPU renderer draws curves as quadratics, rather than as line
  /// segments.
  final bool useCurves = false,
  final bool sweep = false,

  /// The renderer's frames in flight.
  final int slots = 3,

  /// How many times it draws the asset across and down. The copies are
  /// offset by whole multiples of the asset's bounds, rounded up.
  final int grid = 1,
}) extends StatefulWidget {
  @override
  State<SvgPage> createState() => _SvgPageState();
}

class _SvgPageState()
    extends State<SvgPage>
    with SingleTickerProviderStateMixin {
  RasterizerRenderer? _renderer;
  RasterizerScene? _scene;

  /// The run that the last render drew, or null if it was empty.
  RasterizerRun? _drawn;

  /// The entry count and size in bytes of the core's last frame, with the
  /// GPU renderer: see [watchCoreFrames].
  (int, int)? _lastFrame;
  Size? _size;
  double _ratio = 1;

  /// How many renders there were.
  int _frames = 0;

  /// The atlas pages' sizes and memory, as last logged.
  String? _atlas;
  String _status = 'Loading…';
  bool _renderPending = false;

  /// The pan and zoom, in page points with y down, applied after the fit.
  Affine _view = const Affine.identity();

  /// The view, and the focal point, at the start of a pinch or drag.
  Affine _gestureView = const Affine.identity();
  Offset _gestureFocal = Offset.zero;

  /// The last 60 renders' timings, in microseconds: CPU, upload, encode.
  final List<List<int>> _recent = [];

  late final Ticker _ticker = createTicker(_sweepTick);
  int _sweepFrame = 0;
  Duration? _lastTick;

  /// Each sweep frame's timings, in microseconds: CPU, upload, encode, their
  /// total, and the interval since the last tick.
  final List<List<int>> _sweepTimings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Creates the renderer, loads the asset into a scene, and renders it.
  Future<void> _load() async {
    RasterizerRenderer? renderer;
    try {
      renderer = await RasterizerRenderer.create(
        slots: widget.slots,
        gpu: widget.gpu,
      );
      watchCoreFrames(
        renderer,
        (entries, bytes) => _lastFrame = (entries, bytes),
      );
      final bytes = await rootBundle.load(widget.asset);
      if (!mounted) {
        renderer.dispose();
        return;
      }
      final svg = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final scene = RasterizerScene.fromSvg(
        svg,
        gpu: widget.gpu,
        maxSize: widget.gpu == RasterizerBackend.mesh ? _maxSize(svg) : null,
      );
      setState(() {
        _renderer = renderer;
        _scene = scene;
      });
      _requestRender();
      if (widget.sweep) {
        _ticker.start();
      }
    } catch (e, stack) {
      // Once the page has the renderer, dispose disposes of it.
      if (_renderer == null) {
        renderer?.dispose();
      }
      debugPrint('RASTERIZER_SVG FAILED loading ${widget.asset}: $e\n$stack');
      if (mounted) {
        setState(() => _status = 'FAILED: $e');
      }
    }
  }

  /// The largest size that [svg]'s view box is drawn at, in device pixels:
  /// the SVG's bounds fitted to the window, then zoomed in 20x.
  double _maxSize(Uint8List svg) {
    final probe = RasterizerScene.fromSvg(
      svg,
      backend: RasterizerBackend.canvas,
    );
    final bounds = probe.bounds, viewBox = probe.viewBox;
    probe.dispose();
    final window = View.of(context).physicalSize;
    return 20 *
        math.min(window.width / bounds.width, window.height / bounds.height) *
        viewBox.longestSide;
  }

  /// Renders once at the next frame, however many changes come before it.
  void _requestRender() {
    if (_renderPending) {
      return;
    }
    _renderPending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _renderPending = false;
      _render();
    });
  }

  /// Renders the grid with the current view.
  ///
  /// Returns the render's timings in microseconds: CPU, upload, encode. Returns
  /// null if there's nothing to render yet, or the render failed.
  List<int>? _render() {
    final renderer = _renderer, scene = _scene, size = _size;
    if (renderer == null || scene == null || size == null || size.isEmpty) {
      return null;
    }
    try {
      final width = (size.width * _ratio).ceil(),
          height = (size.height * _ratio).ceil();
      final frame = renderer.beginFrame(
        width,
        height,
        curves: widget.useCurves,
      );
      final run = frame.addRun();
      for (final m in gridTransforms(
        scene.bounds,
        widget.grid,
        size,
        _view,
        _ratio,
      )) {
        run.add(scene, m.a, m.b, m.c, m.d, m.tx, m.ty);
      }
      frame.render();
      _frames++;
      final timings = [frame.cpuMicros, frame.uploadMicros, frame.encodeMicros];
      _recent.add(timings);
      if (_recent.length > 60) {
        _recent.removeAt(0);
      }
      final core = _lastFrame;
      // Log the atlas when it changes: its pages' sizes this frame, and the
      // memory that they take.
      final atlas = frame.pageSizes.isEmpty
          ? null
          : '${frame.pageSizes.map((s) => '${s.$1}×${s.$2}').join(', ')}, '
                '${_mb(renderer.atlasBytes)} MB';
      if (atlas != _atlas) {
        _atlas = atlas;
        if (atlas != null) {
          debugPrint(
            'RASTERIZER_PAGES $width×$height px: $atlas, '
            '${renderer.atlasResizes} resizes',
          );
        }
      }
      final status =
          '${widget.asset}'
          '${widget.grid > 1 ? ' ${widget.grid}×${widget.grid}' : ''}: '
          '${scene.pathCount * widget.grid * widget.grid} draws, '
          '${core == null ? '' : '${core.$1} entries, ${core.$2} bytes, '}'
          '$width×$height px, ${renderer.backend.name}, '
          '${atlas == null ? '' : 'atlas $atlas, '}'
          'useCurves ${widget.useCurves}. '
          'CPU frame ${_ms(timings[0])}, upload ${_ms(timings[1])}, encode '
          '${_ms(timings[2])} ms';
      if (_frames == 1) {
        debugPrint('RASTERIZER_SVG $status');
      }
      setState(() {
        _drawn = run.isEmpty ? null : run;
        _status =
            '$status. Mean of last ${_recent.length}: '
            '${[for (var k = 0; k < 3; k++) _ms(_mean(_recent, k))].join(', ')}'
            ' ms';
      });
      return timings;
    } catch (e, stack) {
      debugPrint(
        'RASTERIZER_SVG FAILED rendering at $size × $_ratio: $e\n$stack',
      );
      setState(() => _status = 'FAILED: $e');
      return null;
    }
  }

  static int _mean(List<List<int>> rows, int k) =>
      rows.isEmpty ? 0 : rows.fold(0, (s, r) => s + r[k]) ~/ rows.length;

  static String _mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);

  static String _ms(int micros) => (micros / 1000).toStringAsFixed(2);

  void _onScaleStart(ScaleStartDetails details) {
    _gestureView = _view;
    _gestureFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.localFocalPoint - _gestureFocal;
    _view = _gestureView
        .concat(about(_gestureFocal, details.scale))
        .concat(Affine.translation(delta.dx, delta.dy));
    _requestRender();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _view = _view.concat(
        about(event.localPosition, math.exp(-event.scrollDelta.dy / 300)),
      );
      _requestRender();
    }
  }

  void _reset() {
    _view = const Affine.identity();
    _requestRender();
  }

  /// Renders the sweep's next frame, records its timings, and logs the
  /// statistics after the last one.
  void _sweepTick(Duration elapsed) {
    final size = _size;
    if (size == null || _scene == null) {
      return;
    }
    final i = _sweepFrame++;
    _view = sweepView(i, size);
    final timings = _render();
    final interval = _lastTick == null
        ? 0
        : (elapsed - _lastTick!).inMicroseconds;
    _lastTick = elapsed;
    if (timings != null) {
      _sweepTimings.add([
        ...timings,
        timings[0] + timings[1] + timings[2],
        interval,
      ]);
    }
    if (_sweepFrame == sweepFrames) {
      _logSweep();
      _ticker.stop();
    }
  }

  /// Logs the sweep's timing statistics, but for its first frame's, which
  /// warms up.
  void _logSweep() {
    String stats(String name, int k) {
      final values = [for (final row in _sweepTimings.skip(1)) row[k]]..sort();
      int p(double q) => values[((values.length - 1) * q).round()];
      return '$name median ${_ms(p(0.5))} p95 ${_ms(p(0.95))} max '
          '${_ms(values.last)}';
    }

    final missed = _sweepTimings.skip(1).where((row) => row[4] > 17500).length;
    debugPrint(
      'RASTERIZER_SWEEP sweep ${_sweepTimings.length} frames, grid '
      '${widget.grid}, slots ${widget.slots}, '
      '${_renderer!.atlasResizes} atlas resizes, '
      'useCurves ${widget.useCurves}, ${_status.split('. CPU')[0]}: '
      '${stats('cpu', 0)}; ${stats('upload', 1)}; ${stats('encode', 2)}; '
      '${stats('total', 3)}; ${stats('interval', 4)}; '
      '$missed intervals over 17.5 ms',
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _renderer?.dispose();
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawn = _drawn;
    return Scaffold(
      backgroundColor: Colors.grey,
      body: Column(
        children: [
          Expanded(
            child: LayoutSize(
              ratio: MediaQuery.devicePixelRatioOf(context),
              onLayout: (size, ratio) {
                _size = size;
                _ratio = ratio;
                _requestRender();
              },
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onDoubleTap: _reset,
                  child: ClipRect(
                    child: CustomPaint(
                      painter: drawn == null
                          ? null
                          : _RunPainter(drawn, _frames, _ratio),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Draws a run, rendered in device pixels, scaled by the page's pixel ratio.
///
/// A GPU run draws as images of its parts, and a canvas run as its paths.
/// [render] counts renders, so that a new render repaints: the renderer
/// reuses its run objects.
class _RunPainter(final RasterizerRun run, final int render, final double ratio)
    extends CustomPainter {
  static final _paint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) =>
      run.draw(canvas, scale: ratio, paint: run.parts.isEmpty ? null : _paint);

  @override
  bool shouldRepaint(_RunPainter old) =>
      old.render != render || old.ratio != ratio;
}
