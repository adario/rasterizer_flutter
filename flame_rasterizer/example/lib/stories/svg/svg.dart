import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/svg/collidable_svgs_example.dart';
import 'package:flame_rasterizer_example/stories/svg/svg_renderers_example.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookComponent svgStories() {
  return WidgetbookComponent(
    name: 'Svg',
    useCases: [
      ExampleUseCase(
        name: 'Svg Renderers',
        builder: (context) {
          final renderer = rendererKnob(context);
          final svg = context.knobs.object.dropdown(
            label: 'Svg',
            options: svgNames,
          );
          final count = intSliderKnob(
            context,
            label: 'SVG Number',
            initialValue: 100,
            min: 10,
            max: 500,
            divisions: 98,
          );
          final fade = context.knobs.boolean(label: 'Fade SVGs');
          final zoom = zoomKnob(context);
          final speed = speedKnob(context);
          final cache = cacheKnobs(
            context,
            shown: renderer == SvgRenderer.flameSvg,
          );
          return SvgRenderersStory(
            settings: (
              renderer: renderer,
              svg: svg,
              count: count,
              fade: fade,
              cacheMode: cache.mode,
              cacheSize: cache.size,
            ),
            zoom: zoom,
            speed: speed,
          );
        },
        codeLink: baseLink('svg/svg_renderers_example.dart'),
        info: SvgRenderersExample.description,
      ),
      ExampleUseCase(
        name: 'Collidable Svgs',
        builder: (context) {
          final renderer = rendererKnob(context);
          final count = intSliderKnob(
            context,
            label: 'SVG Number',
            initialValue: 4,
            min: 2,
            max: 50,
            divisions: 48,
          );
          return CollidableSvgsStory(
            settings: (renderer: renderer, count: count),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            cache: cacheKnobs(context, shown: renderer == SvgRenderer.flameSvg),
          );
        },
        codeLink: baseLink('svg/collidable_svgs_example.dart'),
        info: CollidableSvgsExample.description,
      ),
    ],
  );
}

/// The Svg Renderers game for [settings], over a status bar.
///
/// A new renderer makes a new game, as a game draws with one renderer. The
/// other knobs change the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class SvgRenderersStory({
  required final SvgRenderersSettings settings,

  /// The camera's zoom.
  final double zoom = 1,

  /// The rotation's speed, from 0, which stands still, to 2.
  final double speed = 1,
}) extends StatelessWidget {
  this : super(key: ValueKey(settings.renderer));

  @override
  Widget build(BuildContext context) {
    return GameStory<SvgRenderersExample>(
      create: (status) => SvgRenderersExample.of(settings, status),
      update: (game) => game.settings = settings,
      zoom: zoom,
      speed: speed,
    );
  }
}

/// The Collidable Svgs game for [settings], over a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game, with new SVGs. The
/// other knobs change the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class CollidableSvgsStory({
  required final CollidableSvgsSettings settings,

  /// The camera's zoom.
  final double zoom = 1,

  /// The SVGs' speed, from 0, which stands still, to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
}) extends StatelessWidget {
  this : super(key: ValueKey((settings.renderer, cache)));

  @override
  Widget build(BuildContext context) {
    return GameStory<CollidableSvgsExample>(
      create: (status) =>
          CollidableSvgsExample.of(settings, status, cache: cache),
      update: (game) => game.count = settings.count,
      zoom: zoom,
      speed: speed,
    );
  }
}
