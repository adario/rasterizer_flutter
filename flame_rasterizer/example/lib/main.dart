import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_app.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/collision_detection.dart';
import 'package:flame_rasterizer_example/stories/forge2d/forge2d.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/svg/svg.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

/// flame_rasterizer's examples, in a Widgetbook, as Flame's are.
void main() {
  // On OpenGL ES, the canvas renderer draws until the GPU renderers'
  // self-tests pass, each its own.
  RasterizerGpu.allowOpenGles = true;
  runApp(const FlameRasterizerExamples());
}

class const FlameRasterizerExamples({
  super.key,

  /// Widgetbook's first route, e.g. `/?path=svg/svg-renderers`.
  final String initialRoute = '/',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // In the safe area: Flutter's menus can be as tall as the app, but sit in
    // its safe area, so on a phone the knobs' longer menus end below the
    // screen, out of reach.
    return SafeArea(
      child: Widgetbook(
        appBuilder: (_, child) => ExampleApp(child: child),
        addons: [ViewportAddon(Viewports.all)],
        header: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'flame_rasterizer Examples',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        home: const ExampleApp(
          child: Center(
            child: Text('Select an example in the navigation to try it out.'),
          ),
        ),
        enableLeafComponents: false,
        initialRoute: initialRoute,
        directories: [
          svgStories(),
          collisionDetectionStories(),
          forge2dStories(),
          gamesStories(),
        ],
      ),
    );
  }
}
