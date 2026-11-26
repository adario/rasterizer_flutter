import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';

/// Tube Runner on its own, outside the Widgetbook: run it with
/// `flutter run -t lib/main_tube_runner.dart`.
void main() {
  runApp(const TubeRunnerApp());
}

/// Tube Runner's story, with a renderer menu and no knobs: it flies down the
/// hexagon at the default flight speed, at a zoom and speed of 1, over a
/// one-line status bar.
class const TubeRunnerApp({
  /// Whether the game plays its sounds.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame(
      title: 'Tube Runner',
      // Its paths are drawn by Flame's own components with Flame SVG.
      svgs: false,
      builder: (renderer) =>
          TubeRunnerStory(renderer: renderer, sound: sound, statusLines: 1),
    );
  }
}
