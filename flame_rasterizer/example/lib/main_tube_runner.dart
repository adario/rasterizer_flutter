import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// Tube Runner on its own, outside the Widgetbook: run it with
/// `flutter run -t lib/main_tube_runner.dart`.
void main() {
  runApp(const TubeRunnerApp());
}

/// Tube Runner's story, without a status bar, with a settings dialog for its
/// knobs in the Widgetbook: it flies down the hexagon at the default flight
/// speed, with 400 stars, at a zoom and speed of 1.
class const TubeRunnerApp({
  /// Whether the game plays its sounds at the start.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame<TubeRunnerSettings>(
      title: 'Tube Runner',
      // Its paths are drawn by Flame's own components with Flame SVG.
      svgs: false,
      settings: TubeRunnerSettings(sound: sound),
      builder: (renderer, settings, _) => TubeRunnerStory(
        renderer: renderer,
        tube: settings.tube,
        sound: settings.sound,
        flightSpeed: settings.flightSpeed,
        zoom: settings.zoom,
        speed: settings.speed,
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
        SettingSlider(
          label: 'Zoom',
          value: settings.zoom,
          range: zoomRange,
          onChanged: (zoom) => onChanged(settings.copyWith(zoom: zoom)),
        ),
        SettingSlider(
          label: 'Speed',
          value: settings.speed,
          range: speedRange,
          onChanged: (speed) => onChanged(settings.copyWith(speed: speed)),
        ),
      ],
    );
  }
}

/// Tube Runner's settings, which stand for its knobs in the Widgetbook.
class TubeRunnerSettings({
  /// The tube it flies down, one of [TubeRunnerExample.tubes], or the
  /// hexagon.
  Tube? tube,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// How fast the ship flies at first: see [TubeHost.flightSpeed].
  final double flightSpeed = TubeHost.defaultFlightSpeed,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0, which stands still, to 2.
  final double speed = 1,
}) {
  /// The tube it flies down.
  final Tube tube = tube ?? Tubes.hexagon;

  /// Returns these settings, with those given changed.
  TubeRunnerSettings copyWith({
    Tube? tube,
    bool? sound,
    double? flightSpeed,
    double? zoom,
    double? speed,
  }) => TubeRunnerSettings(
    tube: tube ?? this.tube,
    sound: sound ?? this.sound,
    flightSpeed: flightSpeed ?? this.flightSpeed,
    zoom: zoom ?? this.zoom,
    speed: speed ?? this.speed,
  );
}
