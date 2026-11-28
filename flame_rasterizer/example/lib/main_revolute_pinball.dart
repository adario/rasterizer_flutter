import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';

/// Runs Revolute Pinball on its own, outside the Widgetbook.
///
/// Start it with `flutter run -t lib/main_revolute_pinball.dart`.
void main() {
  runApp(const RevolutePinballApp());
}

/// Revolute Pinball's story without a status bar.
///
/// A settings dialog holds the story's Widgetbook knobs, except zoom and
/// speed, which stay at 1. The game starts with no pieces shown on its
/// bodies, mixed drops and flame_svg's default cache. On a desktop in
/// landscape, a Square setting narrows the table to the game's height.
class const RevolutePinballApp({
  /// Whether the game plays its sounds at the start.
  final bool sound = true,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StandaloneGame<RevolutePinballSettings>(
      title: 'Revolute Pinball',
      settings: RevolutePinballSettings(sound: sound),
      builder: (renderer, settings, _) => RevolutePinballStory(
        renderer: renderer,
        pieces: settings.pieces,
        drops: settings.drops,
        square: settings.square,
        sound: settings.sound,
        // Like the cache knobs, the cache settings apply only with Flame SVG.
        cache: renderer == SvgRenderer.flameSvg
            ? settings.cache
            : defaultSvgCache,
        statusLines: 0,
      ),
      settingsBuilder: (renderer, settings, onChanged) => [
        SettingSwitch(
          label: 'Pieces',
          value: settings.pieces,
          onChanged: (pieces) => onChanged(settings.copyWith(pieces: pieces)),
        ),
        SettingDropdown<PinballDrops>(
          label: 'Drops',
          value: settings.drops,
          options: PinballDrops.values,
          labelOf: (drops) => drops.label,
          onChanged: (drops) => onChanged(settings.copyWith(drops: drops)),
        ),
        // Shown only where the table fills the game: on a desktop in
        // landscape.
        Builder(
          builder: (context) {
            final size = MediaQuery.sizeOf(context);
            return RevolutePinballExample.fills(size.width, size.height)
                ? SettingSwitch(
                    label: 'Square',
                    value: settings.square,
                    onChanged: (square) =>
                        onChanged(settings.copyWith(square: square)),
                  )
                : const SizedBox.shrink();
          },
        ),
        SettingSwitch(
          label: 'Sound',
          value: settings.sound,
          onChanged: (sound) => onChanged(settings.copyWith(sound: sound)),
        ),
        if (renderer == SvgRenderer.flameSvg) ...[
          SettingDropdown<SvgCacheMode>(
            label: 'Cache mode',
            value: settings.cache.mode,
            options: SvgCacheMode.values,
            labelOf: (mode) => mode.name,
            onChanged: (mode) => onChanged(
              settings.copyWith(cache: (mode: mode, size: settings.cache.size)),
            ),
          ),
          SettingDropdown<SvgCacheSize>(
            label: 'Cache size',
            value: settings.cache.size,
            options: SvgCacheSize.values,
            labelOf: (size) => '${size.name} (${size.label})',
            onChanged: (size) => onChanged(
              settings.copyWith(cache: (mode: settings.cache.mode, size: size)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Revolute Pinball's settings, which stand in for its Widgetbook knobs
/// except zoom and speed.
class const RevolutePinballSettings({
  /// Whether the bodies show their convex pieces.
  final bool pieces = false,

  /// What drops onto the table.
  final PinballDrops drops = PinballDrops.mixed,

  /// Whether a table that fills the game is only as wide as it is high: see
  /// [RevolutePinballExample.square].
  final bool square = false,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
}) {
  /// Returns a copy of these settings with the given ones changed.
  RevolutePinballSettings copyWith({
    bool? pieces,
    PinballDrops? drops,
    bool? square,
    bool? sound,
    SvgCache? cache,
  }) => RevolutePinballSettings(
    pieces: pieces ?? this.pieces,
    drops: drops ?? this.drops,
    square: square ?? this.square,
    sound: sound ?? this.sound,
    cache: cache ?? this.cache,
  );
}
