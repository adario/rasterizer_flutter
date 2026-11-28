import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookComponent gamesStories() {
  return WidgetbookComponent(
    name: 'Games',
    useCases: [
      ExampleUseCase(
        name: 'Svg Shooter',
        builder: (context) {
          final renderer = rendererKnob(context);
          return SvgShooterStory(
            renderer: renderer,
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            cache: cacheKnobs(context, shown: renderer == SvgRenderer.flameSvg),
          );
        },
        codeLink: baseLink('games/svg_shooter'),
        info: SvgShooterExample.description,
      ),
      ExampleUseCase(
        name: 'Tube Shooter',
        builder: (context) {
          // With Flame SVG, Flame's own components draw its paths.
          final renderer = rendererKnob(context, svgs: false);
          return TubeShooterStory(
            renderer: renderer,
            firstLevel: context.knobs.object.dropdown(
              label: _levelLabel,
              options: [for (var i = 0; i < levels.length; i++) i],
              initialOption: 0,
              labelBuilder: _levelName,
            ),
            onLevel: (level) {
              if (context.mounted) {
                WidgetbookState.of(context).updateQueryField(
                  group: 'knobs',
                  field: _levelLabel,
                  value: _levelName(level),
                );
              }
            },
            // Off: the game uses the default stars.
            // stars: starsKnob(context),
            glow: context.knobs.boolean(label: 'Glow'),
            sound: context.knobs.boolean(label: 'Sound', initialValue: true),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            // Off: the game uses the default flight speed.
            // flightSpeed: flightSpeedKnob(context),
          );
        },
        codeLink: baseLink('games/tube_shooter'),
        info: TubeShooterExample.description,
      ),
      ExampleUseCase(
        name: 'Revolute Pinball',
        builder: (context) {
          final renderer = rendererKnob(context);
          return RevolutePinballStory(
            renderer: renderer,
            pieces: context.knobs.boolean(label: 'Pieces'),
            drops: context.knobs.object.dropdown(
              label: 'Drops',
              options: PinballDrops.values,
              initialOption: PinballDrops.mixed,
              labelBuilder: (drops) => drops.label,
            ),
            sound: context.knobs.boolean(label: 'Sound', initialValue: true),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            cache: cacheKnobs(context, shown: renderer == SvgRenderer.flameSvg),
          );
        },
        codeLink: baseLink('games/revolute_pinball'),
        info: RevolutePinballExample.description,
      ),
      // Left out of the app: Tube Shooter already includes Tube Runner's
      // runs.
      // ExampleUseCase(
      //   name: 'Tube Runner',
      //   builder: (context) {
      //     // With Flame SVG, Flame's own components draw its paths.
      //     final renderer = rendererKnob(context, svgs: false);
      //     final tube = context.knobs.object.dropdown(
      //       label: 'Tube',
      //       options: TubeRunnerExample.tubes,
      //       initialOption: Tubes.hexagon,
      //       labelBuilder: (tube) => tube.name,
      //     );
      //     final sound = context.knobs.boolean(
      //       label: 'Sound',
      //       initialValue: true,
      //     );
      //     return TubeRunnerStory(
      //       renderer: renderer,
      //       tube: tube,
      //       // Off: the game uses the default stars.
      //       // stars: starsKnob(context),
      //       sound: sound,
      //       flightSpeed: flightSpeedKnob(context),
      //       zoom: zoomKnob(context),
      //       speed: speedKnob(context),
      //     );
      //   },
      //   codeLink: baseLink('games/tube_runner'),
      //   info: TubeRunnerExample.description,
      // ),
    ],
  );
}

/// The Svg Shooter game for [renderer], above a status bar.
///
/// A new renderer or flame_svg [cache] creates a new game that continues with
/// the same score, spaceship, enemies and missiles, where they were. A new
/// [zoom] or [speed] changes the running game.
class const SvgShooterStory({
  required final SvgRenderer renderer,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GameStory<SvgShooterExample, SvgShooterSnapshot>(
      renderer: renderer,
      cache: cache,
      create: (status, from) =>
          SvgShooterExample.of(renderer, status, cache: cache, from: from),
      snapshot: (game) => game.snapshot,
      zoom: zoom,
      speed: speed,
    );
  }
}

/// The Level knob's label, which also names its field in the URL.
const _levelLabel = 'Level';

/// Returns the Level knob's entry for the level at [index] in [levels]: the
/// name of its tube, which no other level's tube has.
String _levelName(int index) => levels[index].tube.name;

/// The Tube Shooter game for [renderer], above a status bar.
///
/// A new renderer creates a new game that continues with the same round,
/// ship, enemies and shots, where they were. A new [firstLevel] creates a new
/// game at that level, unless it's the round's current level, which the game
/// reports to [onLevel]. The other knobs change the running game.
class const TubeShooterStory({
  required final SvgRenderer renderer,

  /// The level that a new game starts at.
  final int firstLevel = 0,

  /// Called with the round's level each time it changes, so that the Level
  /// knob can show it.
  final void Function(int level)? onLevel,

  /// How many stars there are: see [TubeHost.starCount].
  final int stars = TubeHost.defaultStarCount,

  /// Whether the lines glow: see [TubeShooterExample.glow].
  final bool glow = false,

  /// Whether the ship keeps flying down a run after a round's drop: see
  /// [TubeShooterExample.runs].
  final bool runs = true,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// How fast Tube Runner's ship flies at first: see
  /// [TubeHost.flightSpeed].
  final double flightSpeed = TubeHost.defaultFlightSpeed,

  /// How many lines tall the status bar is.
  final int statusLines = 2,
  super.key,
}) extends StatefulWidget {
  @override
  State<TubeShooterStory> createState() => _TubeShooterStoryState();
}

class _TubeShooterStoryState() extends State<TubeShooterStory> {
  /// The key of the game's story: a new value replaces the game with a new
  /// one.
  int _game = 0;

  /// The round's level, as the game last reported it.
  late int _level = widget.firstLevel;

  @override
  void didUpdateWidget(TubeShooterStory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.firstLevel != _level) {
      _game++;
      _level = widget.firstLevel;
    }
  }

  void _onLevel(int level) {
    if (level != _level) {
      _level = level;
      widget.onLevel?.call(level);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameStory<TubeShooterExample, TubeShooterSnapshot>(
      key: ValueKey(_game),
      renderer: widget.renderer,
      create: (status, from) =>
          TubeShooterExample.of(
              widget.renderer,
              status,
              firstLevel: widget.firstLevel,
              from: from,
            )
            ..starCount = widget.stars
            ..glow = widget.glow
            ..runs = widget.runs
            ..sound = widget.sound
            ..flightSpeed = widget.flightSpeed
            ..onLevel = _onLevel,
      snapshot: (game) => game.snapshot,
      update: (game) => game
        ..starCount = widget.stars
        ..glow = widget.glow
        ..runs = widget.runs
        ..sound = widget.sound
        ..flightSpeed = widget.flightSpeed,
      zoom: widget.zoom,
      speed: widget.speed,
      statusLines: widget.statusLines,
    );
  }
}

class const RevolutePinballStory({
  required final SvgRenderer renderer,
  required final bool pieces,
  required final bool sound,
  final PinballDrops drops = PinballDrops.mixed,
  final bool square = false,
  final double zoom = 1,
  final double speed = 1,
  final SvgCache cache = defaultSvgCache,
  final int statusLines = 2,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GameStory<RevolutePinballExample, RevolutePinballSnapshot>(
      renderer: renderer,
      cache: cache,
      create: (status, from) =>
          RevolutePinballExample.of(
              renderer,
              status,
              pieces: pieces,
              cache: cache,
              from: from,
            )
            ..drops = drops
            ..square = square
            ..sound = sound,
      snapshot: (game) => game.snapshot,
      update: (game) => game
        ..pieces = pieces
        ..drops = drops
        ..square = square
        ..sound = sound,
      zoom: zoom,
      speed: speed,
      statusLines: statusLines,
    );
  }
}

/// The Tube Runner game for [renderer], above a status bar.
///
/// A new renderer creates a new game that continues with the same ship,
/// enemies, spikes and shots, where they were. The other knobs change the
/// running game: a new [tube] takes over where the ship is, without a stop.
class const TubeRunnerStory({
  required final SvgRenderer renderer,

  /// The tube that the ship flies down: one of [TubeRunnerExample.tubes], or
  /// the hexagon by default.
  final Tube? tube,

  /// How many stars there are: see [TubeHost.starCount].
  final int stars = TubeHost.defaultStarCount,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// How fast the ship flies at first: see [TubeHost.flightSpeed].
  final double flightSpeed = TubeHost.defaultFlightSpeed,

  /// How many lines tall the status bar is.
  final int statusLines = 2,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GameStory<TubeRunnerExample, TubeRunnerSnapshot>(
      renderer: renderer,
      create: (status, from) =>
          TubeRunnerExample.of(renderer, status, tube: tube, from: from)
            ..starCount = stars
            ..sound = sound
            ..flightSpeed = flightSpeed,
      snapshot: (game) => game.snapshot,
      update: (game) => game
        ..tube = tube ?? Tubes.hexagon
        ..starCount = stars
        ..sound = sound
        ..flightSpeed = flightSpeed,
      zoom: zoom,
      speed: speed,
      statusLines: statusLines,
    );
  }
}
