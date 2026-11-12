import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
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
          final renderer = rendererKnob(context);
          return TubeShooterStory(
            renderer: renderer,
            firstLevel: context.knobs.object.dropdown(
              label: 'Level',
              options: [for (var i = 0; i < levels.length; i++) i],
              initialOption: 0,
              labelBuilder: (i) => '${i + 1} ${levels[i].tube.name}',
            ),
            driftingStars: context.knobs.boolean(
              label: 'Drifting stars',
              initialValue: true,
            ),
            // Only the mesh renderer draws a glow, so the knob shows only with
            // it. Widgetbook registers the knobs again on each build, so the
            // hidden knob keeps its value.
            glow:
                renderer == SvgRenderer.rasterizer &&
                context.knobs.boolean(label: 'Glow'),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
          );
        },
        codeLink: baseLink('games/tube_shooter'),
        info: TubeShooterExample.description,
      ),
    ],
  );
}

/// The Svg Shooter game for [renderer], over a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game, with new SVGs. A new
/// [zoom] or [speed] changes the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class SvgShooterStory({
  required final SvgRenderer renderer,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0, which stands still, to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
}) extends StatelessWidget {
  this : super(key: ValueKey((renderer, cache)));

  @override
  Widget build(BuildContext context) {
    return GameStory<SvgShooterExample>(
      create: (status) => SvgShooterExample.of(renderer, status, cache: cache),
      zoom: zoom,
      speed: speed,
    );
  }
}

/// The Tube Shooter game for [renderer], over a status bar.
///
/// A new renderer or [firstLevel] makes a new game. The other knobs change
/// the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class TubeShooterStory({
  required final SvgRenderer renderer,

  /// The level that a new game starts at.
  final int firstLevel = 0,

  /// Whether the stars stay, drifting, between the zoom and the drop.
  final bool driftingStars = true,

  /// Whether the lines glow. Only the mesh renderer draws glows.
  final bool glow = false,

  /// The camera's zoom.
  final double zoom = 1,

  /// The game's speed, from 0, which stands still, to 2.
  final double speed = 1,
}) extends StatelessWidget {
  this : super(key: ValueKey((renderer, firstLevel)));

  @override
  Widget build(BuildContext context) {
    return GameStory<TubeShooterExample>(
      create: (status) =>
          TubeShooterExample.of(renderer, status, firstLevel: firstLevel)
            ..driftingStars = driftingStars
            ..glow = glow,
      update: (game) => game
        ..driftingStars = driftingStars
        ..glow = glow,
      zoom: zoom,
      speed: speed,
    );
  }
}
