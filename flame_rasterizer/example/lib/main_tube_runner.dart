import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// Runs Tube Runner on its own, outside the Widgetbook.
///
/// Start it with `flutter run -t lib/main_tube_runner.dart`.
void main() {
  runApp(const TubeRunnerApp());
}

/// Tube Runner's story without a status bar.
///
/// A settings dialog holds the story's Widgetbook knobs, except zoom and
/// speed, which stay at 1. The ship starts flying down the hexagon at the
/// default flight speed, with 400 stars.
class const TubeRunnerApp({
  /// Whether the game plays its sounds at the start.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame<TubeRunnerSettings>(
      title: 'Tube Runner',
      // With Flame SVG, Flame's own components draw its paths.
      svgs: false,
      settings: TubeRunnerSettings(sound: sound),
      builder: (renderer, settings, _) => TubeRunnerStory(
        renderer: renderer,
        tube: settings.tube,
        sound: settings.sound,
        flightSpeed: settings.flightSpeed,
        statusLines: 0,
      ),
      settingsBuilder: (renderer, settings, onChanged) => [
        SettingDropdown<Tube>(
          label: 'Tube',
          value: settings.tube,
          options: TubeRunnerExample.tubes,
          labelOf: (tube) => tube.name,
          onChanged: (tube) => onChanged(settings.copyWith(tube: tube)),
        ),
        SettingSwitch(
          label: 'Sound',
          value: settings.sound,
          onChanged: (sound) => onChanged(settings.copyWith(sound: sound)),
        ),
        SettingSlider(
          label: 'Flight speed',
          value: settings.flightSpeed,
          range: flightSpeedRange,
          onChanged: (flightSpeed) =>
              onChanged(settings.copyWith(flightSpeed: flightSpeed)),
        ),
      ],
    );
  }
}

/// Tube Runner's settings, which stand in for its Widgetbook knobs except
/// zoom and speed.
class TubeRunnerSettings({
  /// The tube that the ship flies down: one of [TubeRunnerExample.tubes], or
  /// the hexagon by default.
  Tube? tube,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// How fast the ship flies at first: see [TubeHost.flightSpeed].
  final double flightSpeed = TubeHost.defaultFlightSpeed,
}) {
  /// The tube that the ship flies down.
  final Tube tube = tube ?? Tubes.hexagon;

  /// Returns a copy of these settings with the given ones changed.
  TubeRunnerSettings copyWith({
    Tube? tube,
    bool? sound,
    double? flightSpeed,
  }) => TubeRunnerSettings(
    tube: tube ?? this.tube,
    sound: sound ?? this.sound,
    flightSpeed: flightSpeed ?? this.flightSpeed,
  );
}
