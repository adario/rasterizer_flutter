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

/// The Revolute Joint Svgs game for [settings], above a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game with a new physics
/// world, which resumes with the same bodies where they were. The other knobs
/// change the running game.
class const RevoluteJointSvgsStory({
  required final RevoluteJointSvgsSettings settings,

  /// The camera's zoom, on top of the world's scale of 10 pixels a meter.
  final double zoom = 1,

  /// The physics' speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GameStory<RevoluteJointSvgsExample, RevoluteJointSvgsSnapshot>(
      renderer: settings.renderer,
      cache: cache,
      create: (status, from) => RevoluteJointSvgsExample.of(
        settings,
        status,
        cache: cache,
        from: from,
      ),
      snapshot: (game) => game.snapshot,
      update: (game) => game.pieces = settings.pieces,
      zoom: zoom,
      speed: speed,
    );
  }
}
