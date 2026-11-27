import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';

/// Tube Shooter on its own, outside the Widgetbook: run it with
/// `flutter run -t lib/main_tube_shooter.dart`.
void main() {
  runApp(const TubeShooterApp());
}

/// Tube Shooter's story, without a status bar, with a settings dialog for
/// its knobs in the Widgetbook but zoom and speed, which stay at 1: it starts
/// at the first level, with 400 stars, without glow.
class const TubeShooterApp({
  /// Whether the game plays its sounds at the start.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame<TubeShooterSettings>(
      title: 'Tube Shooter',
      // Its paths are drawn by Flame's own components with Flame SVG.
      svgs: false,
      settings: TubeShooterSettings(sound: sound),
      builder: (renderer, settings, onChanged) => TubeShooterStory(
        renderer: renderer,
        firstLevel: settings.level,
        // The Level setting shows the round's level, as the knob does.
        onLevel: (level) => onChanged(settings.copyWith(level: level)),
        glow: settings.glow,
        sound: settings.sound,
        statusLines: 0,
      ),
      settingsBuilder: (renderer, settings, onChanged) => [
        SettingDropdown<int>(
          label: 'Level',
          value: settings.level,
          options: [for (var i = 0; i < levels.length; i++) i],
          labelOf: (level) => levels[level].tube.name,
          onChanged: (level) => onChanged(settings.copyWith(level: level)),
        ),
        SettingSwitch(
          label: 'Glow',
          value: settings.glow,
          onChanged: (glow) => onChanged(settings.copyWith(glow: glow)),
        ),
        SettingSwitch(
          label: 'Sound',
          value: settings.sound,
          onChanged: (sound) => onChanged(settings.copyWith(sound: sound)),
        ),
      ],
    );
  }
}

/// Tube Shooter's settings, which stand for its knobs in the Widgetbook but
/// zoom and speed.
class const TubeShooterSettings({
  /// The level that a new game starts at, and then the round's level.
  final int level = 0,

  /// Whether the lines glow.
  final bool glow = false,

  /// Whether the game plays its sounds.
  final bool sound = true,
}) {
  /// Returns these settings, with those given changed.
  TubeShooterSettings copyWith({
    int? level,
    bool? glow,
    bool? sound,
  }) => TubeShooterSettings(
    level: level ?? this.level,
    glow: glow ?? this.glow,
    sound: sound ?? this.sound,
  );
}
