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

/// The Multiple Shapes game for [settings], above a status bar.
///
/// A new renderer or flame_svg [cache] makes a new game, which resumes with the
/// same shapes where they were. A new Shapes choice makes a new game with new
/// shapes. The other knobs change the running game.
// The lint misses that its key isn't constant.
// ignore: prefer_const_constructors_in_immutables
class MultipleShapesStory({
  required final MultipleShapesSettings settings,

  /// The camera's zoom.
  final double zoom = 1,

  /// The components' speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// flame_svg's cache settings, for Flame SVG when the shapes are SVGs.
  final SvgCache cache = defaultSvgCache,
}) extends StatelessWidget {
  this : super(key: ValueKey(settings.shapes));

  @override
  Widget build(BuildContext context) {
    return GameStory<MultipleShapesExample, MultipleShapesSnapshot>(
      renderer: settings.renderer,
      cache: cache,
      create: (status, from) =>
          MultipleShapesExample.of(settings, status, cache: cache, from: from),
      snapshot: (game) => game.snapshot,
      update: (game) => game.count = settings.count,
      zoom: zoom,
      speed: speed,
    );
  }
}
