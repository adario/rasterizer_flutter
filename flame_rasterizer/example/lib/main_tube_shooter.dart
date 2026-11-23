import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';

/// Tube Shooter on its own, outside the Widgetbook: run it with
/// `flutter run -t lib/main_tube_shooter.dart`.
void main() {
  runApp(const TubeShooterApp());
}

/// Tube Shooter's story, with a renderer menu and no knobs: it starts at the
/// first level, with drifting stars, without glow, at a zoom and speed of 1,
/// over a one-line status bar.
class const TubeShooterApp({
  /// Whether the game plays its sounds.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame(
      title: 'Tube Shooter',
      // Its paths are drawn by Flame's own components with Flame SVG.
      svgs: false,
      builder: (renderer) =>
          TubeShooterStory(renderer: renderer, sound: sound, statusLines: 1),
    );
  }
}
