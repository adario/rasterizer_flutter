import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';

/// Returns the start of the status of a game with [renderer].
///
/// With flame_rasterizer's GPU renderers, it names the renderer asked for,
/// with its graphics API, wherever that's supported, so that a fallback to
/// the canvas renderer fails the test. Elsewhere it names the canvas
/// renderer, and why.
String rendererStatus(SvgRenderer renderer) => switch (renderer) {
  SvgRenderer.rasterizer || SvgRenderer.rasterizerAtlas =>
    renderer.supported
        ? '${renderer.text} · '
        : 'canvas '
              '(${RasterizerGpu.of(renderer.gpu).support.name}) · ',
  SvgRenderer.rasterizerCanvas => 'canvas (forced) · ',
  SvgRenderer.flameSvg => 'flame_svg · ',
};
