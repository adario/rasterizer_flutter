import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';

/// Revolute Pinball on its own, outside the Widgetbook: run it with
/// `flutter run -t lib/main_revolute_pinball.dart`.
void main() {
  runApp(const RevolutePinballApp());
}

/// Revolute Pinball's story, with a renderer menu and no knobs: its bodies
/// show no pieces, at a zoom and speed of 1, with flame_svg's default cache,
/// over a one-line status bar.
class const RevolutePinballApp({
  /// Whether the game plays its sounds.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame(
      title: 'Revolute Pinball',
      builder: (renderer) => RevolutePinballStory(
        renderer: renderer,
        pieces: false,
        sound: sound,
        statusLines: 1,
      ),
    );
  }
}
