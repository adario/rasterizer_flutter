import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import '../layout_size.dart';
import '../scenes.dart';

/// The atlas benchmark: [entries] entries of [count] generated SVGs, each
/// moving and spinning.
///
/// It splits the entries into [runs] runs in paint order, and paints grey
/// bars between the runs, as stand-ins for sprites. After [frames] frames, it
/// logs `RASTERIZER_ATLAS` timing statistics, and keeps animating. The golden
/// tests render one of its frames.
class const AtlasPage({
  super.key,

  /// How many different SVGs it generates.
  final int count = 50,

  /// How many SVGs it draws.
  final int entries = 1000,
  final int runs = 4,
  final int frames = 300,

  /// The GPU renderer to use where it's supported, as
  /// [RasterizerRenderer.create] takes it.
  final RasterizerBackend gpu = RasterizerBackend.gpu,
}) extends StatefulWidget {
  @override
  State<AtlasPage> createState() => _AtlasPageState();
}

class _AtlasPageState()
    extends State<AtlasPage>
    with SingleTickerProviderStateMixin {
  RasterizerRenderer? _renderer;
  final List<RasterizerScene> _scenes = [];

  /// The runs that the last render drew, but the empty ones.
  List<RasterizerRun> _drawn = const [];
  Size? _size;
  double _ratio = 1;
  String _status = 'Loading…';
  late final Ticker _ticker = createTicker(_tick);
  late final AtlasMotion _motion = AtlasMotion(
    svgCount: widget.count,
    entries: widget.entries,
  );
  int _frame = 0;
  Duration? _lastTick;

  /// Each frame's timings, in microseconds: CPU, upload, encode, their total,
  /// and the interval since the last tick.
  final List<List<int>> _timings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Creates the renderer and the scenes, then starts the animation.
  Future<void> _load() async {
    RasterizerRenderer? renderer;
    try {
      if (widget.runs < 1) {
        throw ArgumentError.value(widget.runs, 'runs', 'At least 1');
      }
      renderer = await RasterizerRenderer.create(gpu: widget.gpu);
      if (!mounted) {
        renderer.dispose();
        return;
      }
      // The largest size that an SVG is drawn at, for the mesh renderer's
      // curves: its view box at 1.6 / 12 of the viewport's shorter side, and
      // the viewport at most the window.
      final maxSize = 1.6 * View.of(context).physicalSize.shortestSide / 12;
      _scenes.addAll([
        for (final svg in generatedSvgs(widget.count))
          RasterizerScene.fromSvg(
            utf8.encode(svg),
            gpu: widget.gpu,
            maxSize: maxSize,
          ),
      ]);
      setState(() => _renderer = renderer);
      _ticker.start();
    } catch (e, stack) {
      // Once the page has the renderer, dispose disposes of it.
      if (_renderer == null) {
        renderer?.dispose();
      }
      debugPrint('RASTERIZER_ATLAS FAILED loading: $e\n$stack');
      if (mounted) {
        setState(() => _status = 'FAILED: $e');
      }
    }
  }

  /// Renders the entries at [t] seconds, split in order into the runs.
  RasterizerFrame _render(double t) {
    final size = _size!,
        px = Size(
          (size.width * _ratio).ceilToDouble(),
          (size.height * _ratio).ceilToDouble(),
        );
    final frame = _renderer!.beginFrame(px.width.toInt(), px.height.toInt());
    final n = widget.entries,
        runs = [for (var k = 0; k < widget.runs; k++) frame.addRun()];
    for (var i = 0; i < n; i++) {
      final (a, b, c, d, tx, ty) = _motion.transform(i, t, px);
      runs[i * widget.runs ~/ n].add(
        _scenes[_motion.svg(i)],
        a,
        b,
        c,
        d,
        tx,
        ty,
      );
    }
    frame.render();
    setState(
      () => _drawn = [
        for (final run in frame.runs)
          if (!run.isEmpty) run,
      ],
    );
    return frame;
  }

  /// Renders a frame, records its timings, and logs the statistics after
  /// [AtlasPage.frames] frames.
  void _tick(Duration elapsed) {
    // Skip a page that isn't laid out yet, or is 0 x 0, as a release build's
    // first frames on Android can be. There, beginFrame would throw, and the
    // ticker would skip its next tick and stop.
    if (_size == null || _size!.isEmpty || _renderer == null) {
      return;
    }
    final frame = _render(elapsed.inMicroseconds / 1e6);
    final interval = _lastTick == null
        ? 0
        : (elapsed - _lastTick!).inMicroseconds;
    _lastTick = elapsed;
    final t = [frame.cpuMicros, frame.uploadMicros, frame.encodeMicros];
    _timings.add([...t, t[0] + t[1] + t[2], interval]);
    if (++_frame != widget.frames) {
      return;
    }
    // The first 5 frames warm up, unless they're all there is.
    final warmUp = _timings.length > 5 ? 5 : 0;
    String stats(String name, int k) {
      final values = [for (final row in _timings.skip(warmUp)) row[k]]..sort();
      int p(double q) => values[((values.length - 1) * q).round()];
      String ms(int v) => (v / 1000).toStringAsFixed(2);
      return '$name median ${ms(p(0.5))} p95 ${ms(p(0.95))} max '
          '${ms(values.last)}';
    }

    final missed = _timings.skip(warmUp).where((row) => row[4] > 17500).length;
    final paths = [
      for (var i = 0; i < widget.entries; i++)
        _scenes[_motion.svg(i)].pathCount,
    ].fold(0, (a, b) => a + b);
    final status =
        'RASTERIZER_ATLAS bench ${_timings.length} frames ($warmUp warming '
        'up), ${widget.entries} entries of ${widget.count} SVGs ($paths '
        'paths), ${widget.runs} runs, ${frame.width}×${frame.height} px, '
        '${_renderer!.backend.name}, pages '
        '${frame.pageSizes.map((s) => '${s.$1}×${s.$2}').join(', ')}: '
        '${stats('cpu', 0)}; ${stats('upload', 1)}; ${stats('encode', 2)}; '
        '${stats('total', 3)}; ${stats('interval', 4)}; '
        '$missed intervals over 17.5 ms';
    debugPrint(status);
    setState(() => _status = status);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _renderer?.dispose();
    for (final scene in _scenes) {
      scene.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: LayoutSize(
              ratio: MediaQuery.devicePixelRatioOf(context),
              onLayout: (size, ratio) {
                _size = size;
                _ratio = ratio;
              },
              child: ClipRect(
                child: CustomPaint(
                  painter: _RunsPainter(_drawn, _frame, _ratio),
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

/// Draws each run, and a grey bar after each but the last, standing in for a
/// sprite between runs.
///
/// A GPU run draws as images of its parts, and a canvas run as its paths.
/// [render] counts renders, so that a new render repaints: the renderer
/// reuses its run objects.
class _RunsPainter(
  final List<RasterizerRun> drawn,
  final int render,
  final double ratio,
) extends CustomPainter {
  static final _paint = Paint()..filterQuality = FilterQuality.none;
  static final _bar = Paint()..color = const Color(0x80808080);

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = 0; k < drawn.length; k++) {
      final run = drawn[k];
      run.draw(canvas, scale: ratio, paint: run.parts.isEmpty ? null : _paint);
      if (k < drawn.length - 1) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            size.height * (k + 1) / (drawn.length + 1),
            size.width,
            12,
          ),
          _bar,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RunsPainter old) =>
      old.render != render || old.ratio != ratio;
}
