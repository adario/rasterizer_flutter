import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// An example's world, which runs at its game's [ExampleGame.speed].
class ExampleWorld() extends World with CustomTraversal, HasTimeScale;

/// An example's game, whose [ExampleWorld] runs at its [speed].
abstract class ExampleGame({
  @override required final ValueNotifier<String> status,
}) extends FlameGame<ExampleWorld> with StoryGame {
  this : super(world: ExampleWorld());

  @override
  double get speed => world.timeScale;

  @override
  set speed(double value) => world.timeScale = value;
}

/// A game that a story shows, with a world of any type, which runs at
/// [speed].
///
/// Once the game calls [startStatus], it shows the FPS at its top left
/// corner. Then, every quarter of a second, [status] gets [rendererText],
/// the frame times, [rendererStats] and [exampleStats].
///
/// The frame times are the mean and the 90th percentile of the last 60
/// frames, in milliseconds. "render" times the game's own [render], "build"
/// Flutter's build phase, and "raster" Flutter's raster phase.
mixin StoryGame<W extends World> on FlameGame<W> {
  /// How many of the last frames the frame times cover.
  static const _window = 60;

  /// The style of the texts over the world, such as the FPS.
  static final hudTextRenderer = TextPaint(
    style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16),
  );

  /// The distance of the texts over the world from the game's edges.
  static const hudMargin = 10.0;

  final _renderWatch = Stopwatch();
  final _renderMicros = <int>[];
  final _buildMicros = <int>[];
  final _rasterMicros = <int>[];

  /// Seconds since the status last changed.
  double _statusTime = 0;

  /// Whether [startStatus] started the status, and [stopStatus] hasn't
  /// stopped it.
  bool _timed = false;
  FpsTextComponent? _fps;

  /// The status that the bar under the game shows.
  ValueNotifier<String> get status;

  /// The world's speed, from 0, which stands still, to 2: its `HasTimeScale`
  /// scale.
  double get speed;
  set speed(double value);

  /// The name of what draws the game, for the status.
  String get rendererText;

  /// The renderer's own numbers, for the status.
  Iterable<String> get rendererStats;

  /// The example's own numbers, for the status, after the renderer's.
  Iterable<String> get exampleStats => const [];

  /// Shows the FPS and starts timing frames for the status.
  ///
  /// Call it once the game has something to show. It does nothing once the
  /// game is removed, as a game can be while it loads.
  @protected
  void startStatus() {
    if (_timed || isRemoved) {
      return;
    }
    // The viewport draws the FPS above the world and doesn't zoom it, as the
    // camera draws after the game's other children.
    camera.viewport.add(
      _fps = FpsTextComponent(
        decimalPlaces: 1,
        windowSize: 30,
        position: Vector2.all(hudMargin),
        textRenderer: hudTextRenderer,
      ),
    );
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _timed = true;
  }

  /// Hides the FPS and stops updating the status.
  ///
  /// The status then keeps what it's set to, such as an error, while the
  /// game has nothing to show.
  @protected
  void stopStatus() {
    if (!_timed) {
      return;
    }
    _fps?.removeFromParent();
    _fps = null;
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _timed = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_timed) {
      return;
    }
    _statusTime += dt;
    if (_statusTime >= 0.25) {
      _statusTime = 0;
      status.value = [
        rendererText,
        'render ${_stats(_renderMicros)}',
        'build ${_stats(_buildMicros)}',
        'raster ${_stats(_rasterMicros)}',
        ...rendererStats,
        ...exampleStats,
      ].join(' · ');
    }
  }

  /// Times the components' render for the status.
  ///
  /// With flame_rasterizer, the time leaves out its frame, which
  /// `HasRasterizer` renders afterwards. The frame's cpu, upload and encode
  /// times show among the renderer's own numbers instead.
  @override
  void render(ui.Canvas canvas) {
    _renderWatch
      ..reset()
      ..start();
    super.render(canvas);
    _renderWatch.stop();
    _add(_renderMicros, _renderWatch.elapsedMicroseconds);
  }

  /// Records the build and raster times of the frames that Flutter reports.
  void _timings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _add(_buildMicros, t.buildDuration.inMicroseconds);
      _add(_rasterMicros, t.rasterDuration.inMicroseconds);
    }
  }

  /// Adds [value] to [values], keeping only the last [_window].
  static void _add(List<int> values, int value) {
    values.add(value);
    if (values.length > _window) {
      values.removeAt(0);
    }
  }

  /// The mean and the 90th percentile of [micros], in milliseconds, or blank
  /// before the first frame.
  static String _stats(List<int> micros) {
    if (micros.isEmpty) {
      return '';
    }
    final sorted = [...micros]..sort();
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    final p90 =
        sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    return '${ms(mean)} / ${ms(p90)} ms';
  }

  /// Formats [micros] as milliseconds, with two decimals.
  static String ms(num micros) => (micros / 1000).toStringAsFixed(2);

  @override
  void onRemove() {
    stopStatus();
    super.onRemove();
  }
}
