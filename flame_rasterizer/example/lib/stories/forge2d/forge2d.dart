import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/forge2d/revolute_joint_svgs_example.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookComponent forge2dStories() {
  return WidgetbookComponent(
    name: 'Forge2D',
    useCases: [
      ExampleUseCase(
        name: 'Revolute Joint Svgs',
        builder: (context) {
          final renderer = rendererKnob(context);
          final pieces = context.knobs.boolean(label: 'Pieces');
          return RevoluteJointSvgsStory(
            settings: (renderer: renderer, pieces: pieces),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            cache: cacheKnobs(context, shown: renderer == SvgRenderer.flameSvg),
          );
        },
        codeLink: baseLink('forge2d/revolute_joint_svgs_example.dart'),
        info: RevoluteJointSvgsExample.description,
      ),
    ],
  );
}

/// The Revolute Joint Svgs game for [settings], over a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game, with a new physics
/// world. The other knobs change the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class RevoluteJointSvgsStory({
  required final RevoluteJointSvgsSettings settings,

  /// The camera's zoom, on top of the world's 10 pixels a meter.
  final double zoom = 1,

  /// The physics' speed, from 0, which stands still, to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
}) extends StatelessWidget {
  this : super(key: ValueKey((settings.renderer, cache)));

  @override
  Widget build(BuildContext context) {
    return GameStory<RevoluteJointSvgsExample, Never>(
      renderer: settings.renderer,
      create: (status, _) =>
          RevoluteJointSvgsExample.of(settings, status, cache: cache),
      update: (game) => game.pieces = settings.pieces,
      zoom: zoom,
      speed: speed,
    );
  }
}
