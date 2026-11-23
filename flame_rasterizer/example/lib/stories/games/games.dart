import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
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
          // Its paths are drawn by Flame's own components with Flame SVG.
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
            driftingStars: context.knobs.boolean(
              label: 'Drifting stars',
              initialValue: true,
            ),
            glow: context.knobs.boolean(label: 'Glow'),
            sound: context.knobs.boolean(label: 'Sound', initialValue: true),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
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
            sound: context.knobs.boolean(label: 'Sound', initialValue: true),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            cache: cacheKnobs(context, shown: renderer == SvgRenderer.flameSvg),
          );
        },
        codeLink: baseLink('games/revolute_pinball'),
        info: RevolutePinballExample.description,
      ),
    ],
  );
}

/// The Svg Shooter game for [renderer], over a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game, which goes on with
/// the same score, spaceship, enemies and missiles, from where they were. A
/// new [zoom] or [speed] changes the same game.
class const SvgShooterStory({
  required final SvgRenderer renderer,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0, which stands still, to 2.
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

/// Returns the Level knob's entry for the level at [index] in [levels]: its
/// tube's name, which no other level's tube has.
String _levelName(int index) => levels[index].tube.name;

/// The Tube Shooter game for [renderer], over a status bar.
///
/// A new renderer makes a new game, which goes on with the same round, ship,
/// enemies and shots, from where they were. A new [firstLevel] makes a new
/// game at that level, unless it's the round's level, which the game reports
/// to [onLevel]. The other knobs change the same game.
class const TubeShooterStory({
  required final SvgRenderer renderer,

  /// The level that a new game starts at.
  final int firstLevel = 0,

  /// Called with the round's level each time it changes, so that the Level
  /// knob can show it.
  final void Function(int level)? onLevel,

  /// Whether the stars stay, drifting, between the zoom and the drop.
  final bool driftingStars = true,

  /// Whether the lines glow: see [TubeShooterExample.glow].
  final bool glow = false,

  /// Whether the game plays its sounds.
  final bool sound = true,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0, which stands still, to 2.
  final double speed = 1,

  /// How many lines tall the status bar is.
  final int statusLines = 2,
  super.key,
}) extends StatefulWidget {
  @override
  State<TubeShooterStory> createState() => _TubeShooterStoryState();
}

class _TubeShooterStoryState() extends State<TubeShooterStory> {
  /// The key of the game's story, which a new value replaces with a new game.
  int _game = 0;

  /// The round's level, as the game reported it last.
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
            ..driftingStars = widget.driftingStars
            ..glow = widget.glow
            ..sound = widget.sound
            ..onLevel = _onLevel,
      snapshot: (game) => game.snapshot,
      update: (game) => game
        ..driftingStars = widget.driftingStars
        ..glow = widget.glow
        ..sound = widget.sound,
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
      create: (status, from) => RevolutePinballExample.of(
        renderer,
        status,
        pieces: pieces,
        cache: cache,
        from: from,
      )..sound = sound,
      snapshot: (game) => game.snapshot,
      update: (game) => game
        ..pieces = pieces
        ..sound = sound,
      zoom: zoom,
      speed: speed,
      statusLines: statusLines,
    );
  }
}
