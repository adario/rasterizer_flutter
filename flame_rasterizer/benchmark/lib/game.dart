import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_benchmark/layout.dart';
import 'package:flame_svg/flame_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

/// The GPU renderer that flame_rasterizer draws with where it's supported.
///
/// `--dart-define=BACKEND=atlas` picks rasterizer_gpu's GPU renderer, which
/// rasterizes the SVGs into an atlas each frame. Otherwise it's the mesh
/// renderer, flame_rasterizer's default.
const demoGpu = String.fromEnvironment('BACKEND') == 'atlas'
    ? RasterizerBackend.gpu
    : RasterizerBackend.mesh;

/// What the game draws between groups of vector components.
///
/// Each separator ends a run: a batch of vector components that
/// flame_rasterizer draws together.
enum Separators() {
  rectangles,
  sprites,
  spritesAndText,
}

/// The benchmark's game, built from a [DemoLayout] the same way for each
/// engine.
///
/// It moves the vector components by its [time], unless [fixedTime] holds
/// it. With [benchFrames], it logs the frame times once that many frames
/// have passed after a warm-up. Until then, it logs its progress every 60
/// frames, so that tool/bench.py can tell a stalled run.
///
/// With [fadeAll], each of the layout's items fades in and out at its own
/// rate, so each has its own opacity. With [tintAll], each has a
/// [ColorEffect] of its own color and rate, so a color filter of its own,
/// new each frame. Neither splits a run, as flame_rasterizer fades and
/// filters each component's paths.
mixin DemoContent on FlameGame {
  DemoLayout get layout;
  Separators get separatorKind;

  /// The time to hold the world at, or null to let it move.
  double? get fixedTime;

  /// Whether the camera's zoom changes with time.
  bool get animateZoom;

  /// How many frames to time after the warm-up, or 0 to time none.
  int get benchFrames;

  /// Whether to show the HUD: the frame rate, the render time, the number of
  /// vectors and the engine's stats.
  bool get hud;
  bool get fadeAll;
  bool get tintAll;

  /// The engine that draws the vectors, as `ENGINE` names it.
  String get engine;

  /// The world's time, in seconds, which moves the vector components.
  double time = 0;

  /// Creates the vector component that draws [item], at [priority]. Its
  /// update sets its position and angle.
  HasPaint vectorComponent(VectorItem item, int priority);

  /// Loads the layout's SVGs for the engine.
  Future<void> loadSvgs();

  final List<int> _renderMicros = [];
  final List<int> _buildMicros = [];
  final List<int> _rasterMicros = [];
  final List<int> _intervalMicros = [];
  int? _lastVsync;
  int _frames = 0;

  /// The frames whose timings came, warm-up included. They're the same frames
  /// as the renders, as both are counted from the game's load on.
  int _timedFrames = 0;
  bool _reported = false;

  /// The frames left out of the timings at the start.
  static const _warmUp = 60;
  TextComponent? _hud;
  double _hudTime = 0;
  int _hudFrames = 0;

  /// Times the game's own `render`.
  final Stopwatch _renderWatch = Stopwatch();

  @override
  Future<void> onLoad() async {
    await loadSvgs();
    time = fixedTime ?? 0;
    final sprite = Sprite(await _spriteImage());
    final groups = layout.groups;
    for (final item in layout.items) {
      final component = vectorComponent(item, 2 * item.group);
      if (fadeAll) {
        component.add(
          OpacityEffect.to(
            0.2,
            EffectController(
              duration: 0.5 + item.phase / math.pi,
              alternate: true,
              infinite: true,
            ),
          ),
        );
      }
      if (tintAll) {
        component.add(
          ColorEffect(
            HSVColor.fromAHSV(1, 180 * item.phase / math.pi, 1, 1).toColor(),
            EffectController(
              duration: 0.5 + item.phase / math.pi,
              alternate: true,
              infinite: true,
            ),
            opacityTo: 0.8,
          ),
        );
      }
      world.add(component);
    }
    for (final s in layout.separators) {
      final priority = 2 * s.group + 1;
      final position = Vector2(s.x, s.y);
      final size = Vector2(s.width, s.height);
      final text = separatorKind == Separators.spritesAndText && s.group.isOdd;
      world.add(switch (separatorKind) {
        Separators.rectangles => RectangleComponent(
          position: position,
          size: size,
          angle: s.angle,
          anchor: Anchor.center,
          priority: priority,
          paint: Paint()..color = s.color,
        ),
        _ when text => TextComponent(
          text: 'Text between runs ${s.group}',
          position: position,
          angle: s.angle,
          anchor: Anchor.center,
          priority: priority,
          textRenderer: TextPaint(
            style: TextStyle(
              color: s.color.withAlpha(255),
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        _ => SpriteComponent(
          sprite: sprite,
          position: position,
          size: size,
          angle: s.angle,
          anchor: Anchor.center,
          priority: priority,
        ),
      });
    }
    if (layout.clippedItems.isNotEmpty) {
      const r = DemoLayout.clipRect;
      world.add(
        ClipComponent.rectangle(
          position: Vector2(r.left, r.top),
          size: Vector2(r.width, r.height),
          priority: 2 * groups,
          children: [
            for (final item in layout.clippedItems) vectorComponent(item, 0),
          ],
        ),
      );
    }
    // Painted items, set up with HasPaint's API, except the one with the
    // shared paint. Unless the time is fixed, the faded one fades in and out
    // and the hued one's hue turns.
    final shared = DemoLayout.paintOf(PaintKind.shared);
    for (final (item, kind) in layout.paintedItems) {
      final component = vectorComponent(item, 2 * groups + 1);
      switch (kind) {
        case PaintKind.faded:
          component.opacity = DemoLayout.fadedOpacity;
        case PaintKind.tinted:
          component.tint(DemoLayout.tintColor);
        case PaintKind.hued:
          component.hue = DemoLayout.hue;
        case PaintKind.blurred:
          component.paint.imageFilter = ui.ImageFilter.blur(
            sigmaX: DemoLayout.blurSigma,
            sigmaY: DemoLayout.blurSigma,
          );
        case PaintKind.shared:
          component.paint = shared;
      }
      if (fixedTime == null) {
        if (kind == PaintKind.faded) {
          component.add(
            OpacityEffect.to(
              0.05,
              EffectController(duration: 1.5, alternate: true, infinite: true),
            ),
          );
        } else if (kind == PaintKind.hued) {
          component.add(
            HueEffect.by(
              2 * math.pi,
              EffectController(duration: 6, infinite: true),
            ),
          );
        }
      }
      world.add(component);
    }
    if (hud) {
      camera.viewport.add(
        _hud = TextComponent(
          text: '',
          position: Vector2.all(8),
          textRenderer: TextPaint(
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
          ),
        ),
      );
    }
    if (benchFrames > 0) {
      SchedulerBinding.instance.addTimingsCallback(_timings);
    }
  }

  @override
  void update(double dt) {
    if (fixedTime == null) {
      time += dt;
    }
    final (x, y, zoom) = DemoLayout.camera(
      animateZoom ? time : 0,
      canvasSize.x,
      canvasSize.y,
    );
    // The zoom is zero before the game's first layout, as happens on Android.
    if (zoom > 0) {
      camera.viewfinder
        ..position = Vector2(x, y)
        ..zoom = zoom;
    }
    super.update(dt);
    final hud = _hud;
    if (hud != null) {
      _hudTime += dt;
      _hudFrames++;
      if (_hudTime >= 0.5) {
        hud.text =
            '${(_hudFrames / _hudTime).toStringAsFixed(0)} fps, render '
            '${(_renderWatch.elapsedMicroseconds / 1000).toStringAsFixed(2)} '
            'ms, ${layout.items.length + layout.clippedItems.length} '
            'vectors${statsText()}';
        _hudTime = 0;
        _hudFrames = 0;
      }
    }
  }

  /// The engine's own stats for the HUD and the benchmark's log, each after a
  /// comma, or nothing.
  String statsText() => '';

  @override
  void render(ui.Canvas canvas) {
    _renderWatch
      ..reset()
      ..start();
    super.render(canvas);
    _renderWatch.stop();
    if (benchFrames == 0 || _renderMicros.length >= benchFrames) {
      return;
    }
    if (++_frames % 60 == 0) {
      debugPrint('FLAME_RASTERIZER progress $_frames');
    }
    if (_frames > _warmUp) {
      _renderMicros.add(_renderWatch.elapsedMicroseconds);
      if (_renderMicros.length == benchFrames) {
        _reportOnce();
      }
    }
  }

  /// Collects the frames' timings, which Flutter reports in batches after
  /// their frames.
  ///
  /// The timings come later than the renders, so it skips the warm-up by its
  /// own count. It keeps [benchFrames] of them, as many as the renders.
  void _timings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      final last = _lastVsync;
      _lastVsync = vsync;
      if (++_timedFrames <= _warmUp || _rasterMicros.length >= benchFrames) {
        continue;
      }
      if (last != null) {
        _intervalMicros.add(vsync - last);
      }
      _buildMicros.add(t.buildDuration.inMicroseconds);
      _rasterMicros.add(t.rasterDuration.inMicroseconds);
    }
    if (_rasterMicros.length >= benchFrames) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      _reportOnce();
    }
  }

  /// Reports once both the renders and their frames' timings are in.
  void _reportOnce() {
    if (_reported ||
        _renderMicros.length < benchFrames ||
        _rasterMicros.length < benchFrames) {
      return;
    }
    _reported = true;
    _report();
  }

  /// Logs the `FLAME_RASTERIZER` result line, with the median and the 95th
  /// percentile of each timing.
  void _report() {
    String stats(List<int> values) {
      if (values.isEmpty) {
        return 'n/a';
      }
      final v = [...values]..sort();
      String ms(int us) => (us / 1000).toStringAsFixed(2);
      return 'median ${ms(v[v.length ~/ 2])} p95 '
          '${ms(v[(v.length * 0.95).floor().clamp(0, v.length - 1)])} ms';
    }

    debugPrint(
      'FLAME_RASTERIZER '
      // Only the demo has text between its vectors.
      '${separatorKind == Separators.spritesAndText ? 'demo' : 'bench'} '
      '$engine '
      '${layout.svgName == 'generated' ? '' : 'svg ${layout.svgName} '}'
      'vectors ${layout.items.length} separators ${layout.separators.length} '
      'zoom ${animateZoom ? 'animated' : 'fixed'} '
      '${fadeAll ? 'paints own ' : ''}'
      '${tintAll ? 'tints own ' : ''}'
      'frames ${_renderMicros.length}: render ${stats(_renderMicros)}; build '
      '${stats(_buildMicros)}; '
      'raster ${stats(_rasterMicros)}; interval '
      '${stats(_intervalMicros)}${statsText()}',
    );
  }

  /// Creates the separators' sprite image: a rounded, outlined gradient.
  static Future<ui.Image> _spriteImage() {
    const w = 256;
    const h = 96;
    final recorder = ui.PictureRecorder();
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    ui.Canvas(recorder)
      ..drawRRect(
        RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(24)),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(w.toDouble(), h.toDouble()),
            [const Color(0xFFFFC107), const Color(0xFF3F51B5)],
          ),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(24)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0xFFFFFFFF),
      );
    return recorder.endRecording().toImage(w, h);
  }
}

/// Moves a vector component as its [item] says, at the game's time.
mixin Moves on PositionComponent {
  /// The layout's item that it draws.
  late final VectorItem item;

  /// The game, whose time it follows.
  late final DemoContent demo;

  @override
  void update(double dt) {
    final (x, y, a) = item.at(demo.time);
    position.setValues(x, y);
    angle = a;
  }
}

/// A flame_rasterizer SVG component that [Moves].
class MovingSvg({super.svg, super.size, super.anchor, super.priority})
    extends RasterizerSvgComponent
    with Moves;

/// A flame_svg SVG component that [Moves].
class MovingFlameSvg({super.svg, super.size, super.anchor, super.priority})
    extends SvgComponent
    with Moves;

/// The benchmark with flame_rasterizer, which draws with [demoGpu] where
/// it's supported.
class RasterizerDemoGame({
  @override required final DemoLayout layout,
  @override required final Separators separatorKind,
  @override final double? fixedTime,
  @override final bool animateZoom = true,
  @override final int benchFrames = 0,
  @override final bool hud = true,
  @override final bool fadeAll = false,
  @override final bool tintAll = false,
}) extends FlameGame with HasRasterizer, DemoContent {
  /// The layout's SVGs, imported once.
  late final List<RasterizerSvg> svgs;

  /// The atlas line logged last, so that only changes are logged.
  String? _atlas;

  @override
  String get engine => 'rasterizer';

  @override
  RasterizerBackend get rasterizerGpu => demoGpu;

  @override
  Future<void> loadSvgs() async {
    svgs = [
      for (final s in layout.svgs)
        RasterizerSvg.fromBytes(utf8.encode(s), gpu: rasterizerGpu),
    ];
    await rasterizerReady;
  }

  @override
  HasPaint vectorComponent(VectorItem item, int priority) =>
      MovingSvg(
          svg: svgs[item.svg],
          size: Vector2.all(item.size),
          anchor: Anchor.center,
          priority: priority,
        )
        ..item = item
        ..demo = this
        ..update(0);

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    // Log the atlas when it changes: its pages' sizes and the bytes they hold.
    // With the mesh renderer, the pages are its runs' targets.
    final frame = rasterizerFrame;
    final renderer = rasterizer;
    if (frame == null || renderer == null || frame.pageSizes.isEmpty) {
      return;
    }
    final atlas =
        '${frame.pageSizes.map((s) => '${s.$1}x${s.$2}').join(' ')}, '
        '${_mb(renderer.atlasBytes)} MB';
    if (atlas == _atlas) {
      return;
    }
    _atlas = atlas;
    debugPrint(
      'RASTERIZER_PAGES ${frame.width}x${frame.height} px: $atlas, '
      '${renderer.atlasResizes} resizes',
    );
  }

  static String _mb(int bytes) => (bytes / (1 << 20)).toStringAsFixed(1);

  @override
  String statsText() {
    final frame = rasterizerFrame;
    if (frame == null) {
      return '';
    }
    final backend = rasterizer!.backend;
    final name = backend == RasterizerBackend.canvas
        ? 'canvas ${RasterizerGpu.canvasPictures ? 'pictures' : 'paths'}'
        : backend.name;
    return ', $name, ${frame.runs.length} runs, ${frame.entryCount} '
        'entries, ${backend == RasterizerBackend.mesh ? 'targets' : 'pages'} '
        '${frame.pageSizes.map((s) => '${s.$1}x${s.$2}').join(' ')}'
        ' (${_mb(rasterizer!.atlasBytes)} MB), '
        'cpu ${(frame.cpuMicros / 1000).toStringAsFixed(2)} upload '
        '${(frame.uploadMicros / 1000).toStringAsFixed(2)} '
        'encode ${(frame.encodeMicros / 1000).toStringAsFixed(2)} ms';
  }
}

/// The benchmark with flame_svg, the baseline. Its time always moves.
class FlameSvgDemoGame({
  @override required final DemoLayout layout,
  @override required final Separators separatorKind,
  @override final bool animateZoom = true,
  @override final int benchFrames = 0,
  @override final bool hud = true,
  @override final bool fadeAll = false,
  @override final bool tintAll = false,
}) extends FlameGame with DemoContent {
  @override
  double? get fixedTime => null;

  @override
  String get engine => 'flame_svg';

  /// The layout's SVGs, loaded once.
  late final List<Svg> svgs;

  @override
  Future<void> loadSvgs() async {
    // flame_svg caches an image per size on screen. With a fixed zoom, an
    // unlimited cache holds them all. An animated zoom keeps making new
    // sizes, so it keeps the default cache.
    svgs = [
      for (final s in layout.svgs)
        await Svg.loadFromString(
          s,
          cacheSize: animateZoom
              ? Svg.defaultCacheSize
              : Svg.unlimitedCacheSize,
        ),
    ];
  }

  @override
  HasPaint vectorComponent(VectorItem item, int priority) =>
      MovingFlameSvg(
          svg: svgs[item.svg],
          size: Vector2.all(item.size),
          anchor: Anchor.center,
          priority: priority,
        )
        ..item = item
        ..demo = this
        ..update(0);
}
