import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_svg/flame_svg.dart';

/// The SVGs in `assets/svgs/` and its directories, by path without `.svg`.
/// Svg Renderers' SVG knob lists them all.
const svgNames = [
  'android',
  'flame',
  'setup',
  'setup_merge',
  'recycle',
  'recycle_merge',
  'invader_1',
  'invader_2',
  'invader_3',
  'clover',
  'abstract',
  'alien',
  'alien_symbol',
  'alien_symbol_alt',
  'prism',
  'spaceship',
  'spaceship_2',
  'robot',
  'rocket_ship',
  'missile',
  'spaceship_game',
  'wireframe/spaceship',
  'wireframe/spaceship_2',
  'wireframe/robot',
  'wireframe/rocket_ship',
  'wireframe/missile',
  'tiger',
];

/// The [svgNames] that the other examples don't pick at random.
///
/// - setup_merge and recycle_merge pair with setup and recycle, to show how
///   each renderer merges strokes.
/// - prism and spaceship_2 stay in Svg Renderers.
/// - rocket_ship, missile, spaceship_game and the wireframes are Svg
///   Shooter's.
/// - tiger stays out until the cost of its hitboxes, and of its pieces in
///   Box2D, is measured.
const notRandomSvgNames = {
  'setup_merge',
  'recycle_merge',
  'prism',
  'spaceship_2',
  'rocket_ship',
  'missile',
  'spaceship_game',
  'wireframe/spaceship',
  'wireframe/spaceship_2',
  'wireframe/robot',
  'wireframe/rocket_ship',
  'wireframe/missile',
  'tiger',
};

/// The SVGs that the examples other than Svg Renderers pick at random:
/// [svgNames] without [notRandomSvgNames].
final randomSvgNames = [
  for (final name in svgNames)
    if (!notRandomSvgNames.contains(name)) name,
];

/// What draws an example's SVGs: the Renderer knob's entries, each with its
/// [label].
enum SvgRenderer(final String label) {
  /// flame_rasterizer with rasterizer_gpu's mesh renderer, its default.
  ///
  /// Where the mesh renderer isn't [supported], flame_rasterizer draws with
  /// the canvas renderer, and the Renderer knob shows this entry inactive.
  rasterizer('GPU (mesh)'),

  /// flame_rasterizer with rasterizer_gpu's atlas renderer
  /// (`RasterizerBackend.gpu`), which rasterizes the SVGs into an atlas each
  /// frame.
  ///
  /// Where the atlas renderer isn't [supported], flame_rasterizer draws with
  /// the canvas renderer, and the Renderer knob shows this entry inactive.
  rasterizerAtlas('GPU (atlas)'),

  /// flame_rasterizer with rasterizer_gpu's canvas renderer, everywhere.
  rasterizerCanvas('Canvas'),

  /// flame_svg, which draws each SVG as images that it caches per size on
  /// screen.
  flameSvg('Flame SVG');

  /// The GPU renderer that flame_rasterizer tries for this entry, as
  /// [HasRasterizer.rasterizerGpu]: the atlas renderer for [rasterizerAtlas],
  /// else the mesh renderer.
  RasterizerBackend get gpu =>
      this == rasterizerAtlas ? RasterizerBackend.gpu : RasterizerBackend.mesh;

  /// Whether it draws as its label says, on this device.
  ///
  /// For [rasterizer] and [rasterizerAtlas], it's whether their GPU renderer
  /// runs. It doesn't on the web, nor without Impeller, nor on OpenGL ES
  /// until its self-test passes.
  bool get supported => switch (this) {
    rasterizer || rasterizerAtlas =>
      RasterizerGpu.of(gpu).support == RasterizerSupport.supported,
    rasterizerCanvas || flameSvg => true,
  };
}

/// How flame_svg's cache keys its images.
enum SvgCacheMode() {
  /// By their size on the device: zoomed, flame_svg rasterizes new images,
  /// which stay sharp.
  integral,

  /// By their size in the game, with a fixed ratio: zoomed, flame_svg scales
  /// the images it cached.
  fixed,
}

/// How many images flame_svg's cache keeps per SVG.
enum SvgCacheSize() {
  standard,
  medium,
  large,
  huge,
  unlimited;

  /// The number of images, as flame_svg takes it.
  int get quantity => switch (this) {
    standard => Svg.defaultCacheSize,
    medium => 50,
    large => 100,
    huge => 250,
    unlimited => Svg.unlimitedCacheSize,
  };

  /// The number of images as the Cache size knob shows it.
  String get label => this == unlimited ? '∞' : '$quantity';
}

/// flame_svg's cache settings, as the cache knobs set them.
typedef SvgCache = ({SvgCacheMode mode, SvgCacheSize size});

/// flame_svg's default cache settings, which are also the cache knobs' first
/// choices.
const SvgCache defaultSvgCache = (
  mode: SvgCacheMode.integral,
  size: SvgCacheSize.standard,
);

/// An SVG that a game loaded for its renderer.
abstract class ExampleSvg() {
  /// Its own size, as the SVG file gives it.
  Vector2 get size;

  /// Its outline, for an [SvgHitbox]. It's parsed the first time it's read.
  SvgOutline get outline;

  /// Creates a component that draws it, with [paint] if any.
  PositionComponent component({int priority = 0, ui.Paint? paint});
}

/// Loads and frees a game's SVGs, with [RasterizerSvgs] or [FlameSvgs],
/// whichever the game's class mixes in.
mixin ExampleSvgs<W extends World> on StoryGame<W> {
  /// Loads the SVG at [path], an asset's full path.
  Future<ExampleSvg> loadSvg(String path);

  /// Loads only the outline of the SVG at [path], for a game that draws the
  /// outline but not the SVG.
  Future<SvgOutline> loadOutline(String path);

  /// Frees [svg], which the game loaded and none of its components draws any
  /// more.
  ///
  /// The game frees the SVGs that it still has as it's removed. It frees any
  /// SVG that finishes loading after that at once.
  void unloadSvg(ExampleSvg svg);

  /// Creates a paint that fades an SVG to [opacity].
  ui.Paint fadePaint(double opacity) =>
      ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, opacity);
}

/// A game that flame_rasterizer draws, with [renderer]'s GPU renderer where
/// it's supported, else with the canvas renderer.
///
/// [forceCanvas] picks the canvas renderer everywhere. The game's class sets
/// `RasterizerGpu.forceCanvas` from it in its constructor, before the game's
/// renderer and its SVGs' imports exist, so that they all use one backend.
/// The status names the renderer that draws, and shows its numbers.
mixin ExampleRasterizer<W extends World> on StoryGame<W>, HasRasterizer<W> {
  /// What draws: [SvgRenderer.rasterizer], [SvgRenderer.rasterizerAtlas] or
  /// [SvgRenderer.rasterizerCanvas].
  SvgRenderer get renderer;

  /// Whether the canvas renderer draws even where a GPU renderer is
  /// supported.
  bool get forceCanvas => renderer == SvgRenderer.rasterizerCanvas;

  @override
  RasterizerBackend get rasterizerGpu => renderer.gpu;

  /// flame_rasterizer and the renderer's entry. With the canvas renderer, it
  /// says whether the knob forced it, or else why the GPU renderer doesn't
  /// run.
  @override
  String get rendererText {
    final gpu = RasterizerGpu.of(rasterizerGpu);
    final backend = rasterizer?.backend ?? gpu.backend;
    if (backend != RasterizerBackend.canvas) {
      return 'flame_rasterizer, ${renderer.label}';
    }
    return forceCanvas
        ? 'flame_rasterizer, canvas (forced)'
        : 'flame_rasterizer, canvas (${gpu.support.name})';
  }

  /// The frame's runs (see [RasterizerCanvas]) and entries.
  ///
  /// With a GPU renderer, it adds the atlas pages, or the mesh renderer's
  /// targets, with their memory. It also adds the frame's cpu, upload and
  /// encode times.
  @override
  Iterable<String> get rendererStats sync* {
    final frame = rasterizerFrame;
    final current = rasterizer;
    if (frame == null || current == null) {
      return;
    }
    final runs = frame.runs.length;
    yield '$runs run${runs == 1 ? '' : 's'}, ${frame.entryCount} entries';
    if (current.backend == RasterizerBackend.canvas) {
      return;
    }
    final pages = frame.pageSizes.length;
    final what = current.backend == RasterizerBackend.mesh
        ? 'target'
        : 'atlas page';
    yield '$pages $what${pages == 1 ? '' : 's'}, '
        '${(current.atlasBytes / (1 << 20)).toStringAsFixed(1)} MB';
    yield 'cpu ${StoryGame.ms(frame.cpuMicros)} upload '
        '${StoryGame.ms(frame.uploadMicros)} encode '
        '${StoryGame.ms(frame.encodeMicros)} ms';
  }
}

/// Loads SVGs that [RasterizerSvgComponent]s draw, with the game's renderer.
mixin RasterizerSvgs<W extends World> on ExampleSvgs<W>, ExampleRasterizer<W> {
  /// The game's own asset cache.
  ///
  /// `Flame.assets` would keep an SVG's file as the first game read it: as
  /// bytes for flame_rasterizer, or as a string for flame_svg. It would then
  /// fail when the other package reads the file.
  final _assets = AssetsCache();

  /// The SVGs that it loaded and hasn't freed.
  final _svgs = <RasterizerSvg>[];

  @override
  Future<ExampleSvg> loadSvg(String path) async {
    final svg = await RasterizerSvg.load(
      path,
      cache: _assets,
      gpu: rasterizerGpu,
    );
    if (isRemoved) {
      svg.dispose();
    } else {
      _svgs.add(svg);
    }
    return _RasterizerSvg(svg);
  }

  @override
  Future<SvgOutline> loadOutline(String path) async =>
      SvgOutline.fromSvg(await _assets.readBinaryFile(path));

  @override
  void unloadSvg(ExampleSvg svg) {
    final rasterizerSvg = (svg as _RasterizerSvg).svg;
    if (_svgs.remove(rasterizerSvg)) {
      rasterizerSvg.dispose();
    }
  }

  /// Frees the SVGs that it still has.
  @override
  void onRemove() {
    super.onRemove();
    for (final svg in _svgs) {
      svg.dispose();
    }
    _svgs.clear();
  }
}

class _RasterizerSvg(final RasterizerSvg svg) implements ExampleSvg {
  @override
  Vector2 get size => svg.size;

  @override
  SvgOutline get outline => svg.outline;

  @override
  PositionComponent component({int priority = 0, ui.Paint? paint}) =>
      RasterizerSvgComponent(svg: svg, priority: priority, paint: paint);
}

/// Loads SVGs that flame_svg's `SvgComponent`s draw, as images that it
/// caches as [cacheMode] and [cacheSize] say.
mixin FlameSvgs<W extends World> on ExampleSvgs<W> {
  /// The game's own asset cache, as with [RasterizerSvgs].
  final _assets = AssetsCache();

  /// The SVGs' files as bytes, for their outlines. [_assets] has them as
  /// strings, and an asset cache fails when it reads a file both ways.
  final _bytes = AssetsCache();

  /// The SVGs that it loaded and hasn't freed.
  final _svgs = <Svg>[];

  /// The Cache mode knob's value.
  SvgCacheMode get cacheMode;

  /// The Cache size knob's value.
  SvgCacheSize get cacheSize;

  @override
  Future<ExampleSvg> loadSvg(String path) async {
    final svg = await Svg.load(
      path,
      cache: _assets,
      fixedRatio: cacheMode == SvgCacheMode.fixed,
      cacheSize: cacheSize.quantity,
    );
    if (isRemoved) {
      svg.dispose();
    } else {
      _svgs.add(svg);
    }
    return _FlameSvg(svg, await _bytes.readBinaryFile(path));
  }

  @override
  Future<SvgOutline> loadOutline(String path) async =>
      SvgOutline.fromSvg(await _bytes.readBinaryFile(path));

  /// Frees the SVG's cached images. Its components also free them as they're
  /// removed.
  @override
  void unloadSvg(ExampleSvg svg) {
    final flameSvg = (svg as _FlameSvg).svg;
    if (_svgs.remove(flameSvg)) {
      flameSvg.dispose();
    }
  }

  /// Samples the images at medium quality, as flame_svg's own paint does.
  @override
  ui.Paint fadePaint(double opacity) =>
      super.fadePaint(opacity)..filterQuality = ui.FilterQuality.medium;

  @override
  String get rendererText => 'flame_svg';

  /// Frees the SVGs' cached images. Removing a game doesn't remove its
  /// components, so their own `onRemove` doesn't run.
  @override
  void onRemove() {
    super.onRemove();
    for (final svg in _svgs) {
      svg.dispose();
    }
    _svgs.clear();
  }

  /// How many images all the SVGs' caches hold, out of their total size, and
  /// the cache mode.
  @override
  Iterable<String> get rendererStats {
    final used = _svgs.fold<int>(0, (sum, svg) => sum + svg.cacheUsage);
    final total = cacheSize == SvgCacheSize.unlimited
        ? cacheSize.label
        : '${_svgs.length * cacheSize.quantity}';
    return ['cache $used/$total, ${cacheMode.name}'];
  }
}

class _FlameSvg(final Svg svg, final Uint8List bytes) implements ExampleSvg {
  @override
  Vector2 get size =>
      Vector2(svg.pictureInfo.size.width, svg.pictureInfo.size.height);

  @override
  late final SvgOutline outline = SvgOutline.fromSvg(bytes);

  @override
  PositionComponent component({int priority = 0, ui.Paint? paint}) =>
      SvgComponent(svg: svg, priority: priority, paint: paint);
}
