/// Flame components drawn with rasterizer_gpu.
///
/// A game with [HasRasterizer] draws its [RasterizerSvg]s, such as those of
/// [RasterizerSvgComponent]s, with rasterizer_gpu's mesh renderer. The mesh
/// renderer imports each SVG once, at load, into triangles that stay in GPU
/// buffers. Each frame draws those triangles under the components'
/// transforms. [RasterizerPathComponent]s, which are Flame `PathComponent`s,
/// draw their paths the same way.
///
/// Vector content drawn one item after another makes a run (see
/// [RasterizerCanvas]). Each run is drawn as one image, at its place in the
/// paint order. That image is rendered at the device's resolution, under the
/// camera, perspective included.
///
/// [HasRasterizer.rasterizerGpu] can pick rasterizer_gpu's atlas renderer
/// instead ([RasterizerBackend.gpu]), which rasterizes the SVGs into an atlas
/// each frame. Where the chosen GPU renderer isn't supported
/// ([RasterizerGpu.of]), or with [RasterizerGpu.forceCanvas], rasterizer_gpu's
/// canvas renderer draws instead. It draws each run's paths straight into the
/// game's canvas.
///
/// ```dart
/// class MyGame extends FlameGame with HasRasterizer {
///   @override
///   Future<void> onLoad() async {
///     final coin = await RasterizerSvg.load('assets/coin.svg');
///     world.addAll([
///       for (final p in positions)
///         RasterizerSvgComponent(
///           svg: coin,
///           position: p,
///           size: Vector2.all(64),
///         ),
///     ]);
///   }
/// }
/// ```
///
/// @docImport 'package:flame_rasterizer/src/has_rasterizer.dart';
/// @docImport 'package:flame_rasterizer/src/rasterizer_path_component.dart';
/// @docImport 'package:flame_rasterizer/src/rasterizer_svg.dart';
/// @docImport 'package:flame_rasterizer/src/rasterizer_svg_component.dart';
/// @docImport 'package:rasterizer_gpu/rasterizer_gpu.dart';
library;

export 'package:rasterizer_gpu/rasterizer_gpu.dart'
    show
        RasterizerBackend,
        RasterizerCanvas,
        RasterizerColorTransform,
        RasterizerFrame,
        RasterizerGlow,
        RasterizerGpu,
        RasterizerGpuBackend,
        RasterizerRenderer,
        RasterizerRun,
        RasterizerScene,
        RasterizerSceneRect,
        RasterizerSupport,
        SvgOutline;

export 'src/has_rasterizer.dart';
export 'src/rasterizer_path_component.dart' show RasterizerPathComponent;
export 'src/rasterizer_svg.dart';
export 'src/rasterizer_svg_component.dart';
export 'src/svg_hitbox.dart';
