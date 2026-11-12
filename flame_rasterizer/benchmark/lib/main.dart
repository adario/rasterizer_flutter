import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_benchmark/check.dart';
import 'package:flame_rasterizer_benchmark/game.dart';
import 'package:flame_rasterizer_benchmark/layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The app's settings, picked with `--dart-define`:
/// - MODE: `demo` (the default), `bench` or `check`. `bench` logs a
///   `FLAME_RASTERIZER bench` line after FRAMES frames (600 by default).
///   `check` logs a `FLAME_RASTERIZER check` line at CHECK_TIME seconds (3.7
///   by default).
/// - ENGINE: `rasterizer` (the default), or `flame_svg` as the baseline.
/// - COUNT: the number of vector components (300 by default).
/// - SEPARATORS: the sprites between groups of vector components (2 by
///   default, so 3 runs).
/// - ZOOM: 1 (the default) animates the camera's zoom, and 0 fixes it.
/// - PAINTS: 1 has each vector component fade in and out at its own rate,
///   so each has its own opacity. 2 tints each with a `ColorEffect` of its
///   own, a new color filter each frame. 0 (the default) does neither.
/// - BACKEND: `mesh` (the default) or `atlas` picks [demoGpu], the GPU
///   renderer that draws where it's supported. `canvas` uses the canvas
///   renderer even where a GPU renderer is supported.
/// - CANVAS_PICTURES: `false` has the canvas renderer draw each SVG's paths,
///   rather than a picture of them.
/// - SVG: `generated` (the default) draws 50 small seeded SVGs. `tiger`
///   draws the tiger, 301 paths, for every vector component.
const mode = String.fromEnvironment('MODE', defaultValue: 'demo');
const svg = String.fromEnvironment('SVG', defaultValue: 'generated');
const engine = String.fromEnvironment('ENGINE', defaultValue: 'rasterizer');
const count = int.fromEnvironment('COUNT', defaultValue: 300);
const separators = int.fromEnvironment('SEPARATORS', defaultValue: 2);
const frames = int.fromEnvironment('FRAMES', defaultValue: 600);
const zoom = int.fromEnvironment('ZOOM', defaultValue: 1);
const paints = int.fromEnvironment('PAINTS');
const checkTime = String.fromEnvironment('CHECK_TIME', defaultValue: '3.7');

/// Returns the first define above whose value isn't valid, as `NAME=value`,
/// or null.
///
/// It checks the numbers as strings, as `int.fromEnvironment` silently reads
/// a number it can't parse as its default.
String? _badDefine() {
  const backend = String.fromEnvironment('BACKEND');
  const numbers = {
    'COUNT': String.fromEnvironment('COUNT'),
    'SEPARATORS': String.fromEnvironment('SEPARATORS'),
    'FRAMES': String.fromEnvironment('FRAMES'),
    'ZOOM': String.fromEnvironment('ZOOM'),
    'PAINTS': String.fromEnvironment('PAINTS'),
  };
  if (!const {'demo', 'bench', 'check'}.contains(mode)) {
    return 'MODE=$mode';
  }
  if (!const {'rasterizer', 'flame_svg'}.contains(engine)) {
    return 'ENGINE=$engine';
  }
  if (!const {'generated', 'tiger'}.contains(svg)) {
    return 'SVG=$svg';
  }
  if (!const {'', 'mesh', 'atlas', 'canvas'}.contains(backend)) {
    return 'BACKEND=$backend';
  }
  for (final MapEntry(key: name, :value) in numbers.entries) {
    if (value.isNotEmpty && int.tryParse(value) == null) {
      return '$name=$value';
    }
  }
  if (paints < 0 || paints > 2) {
    return 'PAINTS=$paints';
  }
  if (double.tryParse(checkTime) == null) {
    return 'CHECK_TIME=$checkTime';
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bad = _badDefine();
  if (bad != null) {
    // Log a failed result line, which tool/bench.py and tool/web_check.py
    // read, so that neither waits for a run that measures something else.
    debugPrint(
      'FLAME_RASTERIZER ${mode == 'check' ? 'check' : 'bench'} FAILED: '
      'unknown $bad',
    );
    throw ArgumentError('unknown $bad');
  }
  RasterizerGpu.forceCanvas =
      const String.fromEnvironment('BACKEND') == 'canvas';
  RasterizerGpu.canvasPictures = const bool.fromEnvironment(
    'CANVAS_PICTURES',
    defaultValue: true,
  );
  // On OpenGL ES, the canvas renderer draws until demoGpu's self-test passes.
  RasterizerGpu.allowOpenGles = true;
  if (mode == 'check') {
    return runApp(
      CheckPage(time: double.parse(checkTime)),
    );
  }
  final layout = DemoLayout(
    count: count,
    separators: separators,
    clipped: mode == 'demo' ? 12 : 0,
    painted: mode == 'demo',
    svgs: svg == 'tiger'
        ? [await rootBundle.loadString('assets/tiger.svg')]
        : null,
    svgName: svg,
  );
  const kind = mode == 'demo' ? Separators.spritesAndText : Separators.sprites;
  // The demo logs its timings once, after 120 frames.
  const benchFrames = mode == 'bench' ? frames : 120;
  final game = engine == 'flame_svg'
      ? FlameSvgDemoGame(
          layout: layout,
          separatorKind: kind,
          animateZoom: zoom != 0,
          benchFrames: benchFrames,
          fadeAll: paints == 1,
          tintAll: paints == 2,
        )
      : RasterizerDemoGame(
          layout: layout,
          separatorKind: kind,
          animateZoom: zoom != 0,
          benchFrames: benchFrames,
          fadeAll: paints == 1,
          tintAll: paints == 2,
        );
  runApp(GameWidget(game: game));
}
