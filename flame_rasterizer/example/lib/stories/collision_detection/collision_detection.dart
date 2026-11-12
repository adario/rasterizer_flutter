import 'package:flame_rasterizer_example/commons/commons.dart';
import 'package:flame_rasterizer_example/commons/example_use_case.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/multiple_shapes_example.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookComponent collisionDetectionStories() {
  return WidgetbookComponent(
    name: 'Collision Detection',
    useCases: [
      ExampleUseCase(
        name: 'Multiple Shapes',
        builder: (context) {
          final renderer = rendererKnob(context);
          final shapes = context.knobs.object.segmented(
            label: 'Shapes',
            options: Shapes.values,
            initialOption: Shapes.paths,
            labelBuilder: (value) => value.label,
          );
          final count = intSliderKnob(
            context,
            label: 'Shape Number',
            initialValue: 15,
            min: 2,
            max: 50,
            divisions: 48,
          );
          return MultipleShapesStory(
            settings: (renderer: renderer, shapes: shapes, count: count),
            zoom: zoomKnob(context),
            speed: speedKnob(context),
            // Paths have no flame_svg cache, so the cache knobs show only
            // with SVGs.
            cache: cacheKnobs(
              context,
              shown: renderer == SvgRenderer.flameSvg && shapes == Shapes.svgs,
            ),
          );
        },
        codeLink: baseLink('collision_detection/multiple_shapes_example.dart'),
        info: MultipleShapesExample.description,
      ),
    ],
  );
}

/// The Multiple Shapes game for [settings], over a status bar.
///
/// A new renderer, new shapes or a new flame_svg [cache] makes a new game,
/// with new shapes. The other knobs change the same game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class MultipleShapesStory({
  required final MultipleShapesSettings settings,

  /// The camera's zoom.
  final double zoom = 1,

  /// The components' speed, from 0, which stands still, to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG with SVGs.
  final SvgCache cache = defaultSvgCache,
}) extends StatelessWidget {
  this : super(key: ValueKey((settings.renderer, settings.shapes, cache)));

  @override
  Widget build(BuildContext context) {
    return GameStory<MultipleShapesExample>(
      create: (status) =>
          MultipleShapesExample.of(settings, status, cache: cache),
      update: (game) => game.count = settings.count,
      zoom: zoom,
      speed: speed,
    );
  }
}
