import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [renderer]'s GPU renderer has settled.
///
/// On OpenGL ES, that's once its self-test has passed and the game has
/// switched to it, or once the self-test has failed. Elsewhere it doesn't
/// wait. A status read a quarter of a second later names the renderer.
Future<void> settleRenderer(WidgetTester tester, SvgRenderer renderer) async {
  if (renderer == SvgRenderer.rasterizer ||
      renderer == SvgRenderer.rasterizerAtlas) {
    await tester.runAsync(() => RasterizerGpu.of(renderer.gpu).settledBackend);
  }
}

/// The start of the status of a game with [renderer].
///
/// With flame_rasterizer's GPU renderers, it names the renderer asked for
/// wherever that's supported, so that a fallback to the canvas renderer
/// fails the test. Elsewhere it names the canvas renderer, and why.
String rendererStatus(SvgRenderer renderer) => switch (renderer) {
  SvgRenderer.rasterizer || SvgRenderer.rasterizerAtlas =>
    renderer.supported
        ? 'flame_rasterizer, ${renderer.label} · '
        : 'flame_rasterizer, canvas '
              '(${RasterizerGpu.of(renderer.gpu).support.name}) · ',
  SvgRenderer.rasterizerCanvas => 'flame_rasterizer, canvas (forced) · ',
  SvgRenderer.flameSvg => 'flame_svg · ',
};
