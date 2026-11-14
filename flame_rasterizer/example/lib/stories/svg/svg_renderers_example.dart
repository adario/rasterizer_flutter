import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/widgets.dart';

export '../../commons/svg_renderers.dart'
    show SvgCacheMode, SvgCacheSize, SvgRenderer, svgNames;

/// The values of the example's knobs, except Zoom and Speed.
typedef SvgRenderersSettings = ({
  SvgRenderer renderer,
  String svg,
  int count,
  bool fade,
  SvgCacheMode cacheMode,
  SvgCacheSize cacheSize,
});

/// What a game for another renderer goes on from: the world's time, which
/// the rotations follow.
typedef SvgRenderersSnapshot = ({double time});

/// The same SVG drawn many times: see [description].
///
/// A master SVG rotates at the world's origin, which the camera looks at,
/// and a ring of more SVGs rotates around it, as many as [settings] say.
/// Each SVG in the ring is smaller and starts later than the one before.
/// Subclasses pick what loads and draws the SVG: see [ExampleSvgs].
///
/// Given the [snapshot] of a game with another renderer, it goes on from
/// there, so that it turns on from the same angles.
abstract class SvgRenderersExample(
  var SvgRenderersSettings _settings, {
  required super.status,
  SvgRenderersSnapshot? from,
}) extends ExampleGame with ExampleSvgs {
  /// Creates the game for [settings]' renderer, which goes on from [from], if
  /// any.
  factory SvgRenderersExample.of(
    SvgRenderersSettings settings,
    ValueNotifier<String> status, {
    SvgRenderersSnapshot? from,
  }) => settings.renderer == SvgRenderer.flameSvg
      ? FlameSvgRenderersExample(settings, status: status, from: from)
      : RasterizerRenderersExample(settings, status: status, from: from);

  static const description = '''
    The same SVG drawn many times, by flame_rasterizer or by flame_svg: one in
    the centre, and a ring of 10 to 500 around it, all rotating.

    GPU (mesh), GPU (atlas) and Canvas draw with flame_rasterizer, through one
    of rasterizer_gpu's renderers. The mesh renderer, the default, imports
    each SVG once into triangles that stay on the GPU. The atlas renderer
    rasterizes the SVGs into an atlas each frame. The canvas renderer draws
    their paths into Flutter's canvas. A GPU entry is inactive where its
    renderer can't run, as on the web. Flame SVG draws with flame_svg, which
    caches each SVG as an image per size on screen. Zoomed in,
    flame_rasterizer stays sharp, while flame_svg makes new images or scales
    the ones it cached, as the cache knobs say.

    The other knobs pick the SVG and the SVG number, fade the ring's SVGs,
    zoom the camera and change the rotation's speed. Only a new renderer makes
    a new game, which turns on from the same angles. The bar under the game
    shows the renderer, the frame times and the renderer's own numbers.

    flame_rasterizer doesn't support clip paths, so alien, invader_1,
    invader_2, recycle, recycle_merge, setup and setup_merge draw unclipped
    with it.
  ''';

  static const _turn = 2 * math.pi;

  /// Seconds per turn.
  static const _turnTime = 2.0;

  /// The settings that its components were built for, or null before the
  /// first build.
  SvgRenderersSettings? _built;

  /// The SVG that its components draw, or null if it couldn't load.
  ExampleSvg? _svg;

  /// What [_svg] was loaded for: its name and flame_svg's cache settings.
  (String, SvgCacheMode, SvgCacheSize)? _svgKey;

  /// Old SVGs to free once the components that drew them are removed.
  final _retired = <ExampleSvg>[];

  /// The SVG in the centre.
  PositionComponent? _master;
  final _ring = <PositionComponent>[];

  /// Seconds of the world's time, scaled by [speed], since the story's first
  /// game started. The rotations follow it, so that new components turn as
  /// far as those they replace.
  double _time = from?.time ?? 0;

  /// Whether [onLoad] has run.
  bool _started = false;

  /// Whether [_apply] is running, so that another call leaves the work to it.
  bool _applying = false;

  /// The knobs' values. New values change the running game, except for the
  /// renderer, which is the one that the game was made for.
  ///
  /// Any change replaces the components with new ones, turned as far. A new
  /// SVG or flame_svg cache loads the SVG again first.
  SvgRenderersSettings get settings => _settings;
  set settings(SvgRenderersSettings value) {
    assert(value.renderer == _settings.renderer, 'A game has one renderer');
    if (value == _settings) {
      return;
    }
    _settings = value;
    if (_started) {
      _apply();
    }
  }

  /// What a game for another renderer goes on from.
  SvgRenderersSnapshot get snapshot => (time: _time);

  /// Whether its components match its settings. They don't while it loads a
  /// new SVG.
  @visibleForTesting
  bool get settled => _built == _settings;

  @override
  Future<void> onLoad() async {
    _started = true;
    await _apply();
  }

  /// Builds its components for its settings, loading the SVG first if it
  /// changed.
  ///
  /// It goes on until they match, as the settings can change while an SVG
  /// loads.
  Future<void> _apply() async {
    if (_applying) {
      return;
    }
    _applying = true;
    try {
      while (!isRemoved && _built != _settings) {
        final target = _settings;
        final key = (target.svg, target.cacheMode, target.cacheSize);
        if (key != _svgKey) {
          ExampleSvg? svg;
          String? error;
          try {
            svg = await loadSvg('assets/svgs/${target.svg}.svg');
          } on Object catch (e) {
            // For example tiger.svg, which the pub.dev package leaves out: see
            // assets/.pubignore.
            error = "Couldn't load ${target.svg}.svg: $e";
          }
          final settled =
              (_settings.svg, _settings.cacheMode, _settings.cacheSize) == key;
          if (isRemoved || !settled) {
            // The game was removed, or the knobs picked another SVG, while
            // this one loaded.
            if (svg != null) {
              unloadSvg(svg);
            }
            continue;
          }
          if (_svg case final old?) {
            _retired.add(old);
          }
          _svg = svg;
          _svgKey = key;
          if (error != null) {
            status.value = error;
          }
        }
        _build();
      }
    } finally {
      _applying = false;
    }
  }

  /// Replaces its components with new ones for its settings, turned as far
  /// as those they replace.
  ///
  /// Without an SVG, it adds none, and the status keeps showing the error.
  void _build() {
    final settings = _settings;
    world.removeAll([?_master, ..._ring]);
    _master = null;
    _ring.clear();
    _built = settings;
    final svg = _svg;
    if (svg == null) {
      stopStatus();
      return;
    }
    final (angle, rotation) = _rotation();
    final master = svg.component(priority: 1)
      ..anchor = Anchor.center
      ..angle = angle
      ..add(rotation);
    _master = master;
    world.add(master);
    // As in flame_extended_svg, each one is smaller and starts later than the
    // one before, and with Fade SVGs, it's fainter. All draw above the master.
    final count = settings.count;
    for (var i = 0; i < count; i++) {
      final f = i / count;
      final (angle, rotation) = _rotation(delay: _turnTime * 0.5 * f);
      final component =
          svg.component(
              priority: count + 1 - i,
              paint: settings.fade && i > 0 ? fadePaint(1 - 0.75 * f) : null,
            )
            ..anchor = Anchor.center
            ..scale = Vector2.all(1 - 0.75 * f)
            ..angle = _turn * (i + 1) / count + math.pi / 2 + angle
            ..add(rotation);
      _ring.add(component);
    }
    world.addAll(_ring);
    _layout();
    startStatus();
  }

  /// A turn every [_turnTime], starting [delay] after the game did.
  ///
  /// Returns the angle turned by at the world's [_time], and the effect that
  /// goes on turning from there.
  (double, Effect) _rotation({double delay = 0}) => (
    _turn * (math.max(0.0, _time - delay) / _turnTime % 1),
    RotateEffect.by(
      _turn,
      EffectController(
        duration: _turnTime,
        startDelay: math.max(0.0, delay - _time),
        infinite: true,
      ),
    ),
  );

  @override
  void update(double dt) {
    // The world removes the old components, and adds the new ones, before
    // the old SVGs are freed below.
    super.update(dt);
    _time += dt * speed;
    for (final svg in _retired) {
      unloadSvg(svg);
    }
    _retired.clear();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_master != null) {
      _layout();
    }
  }

  /// Sizes the SVGs to fit a quarter of the game's width and height, keeping
  /// the SVG's aspect ratio.
  ///
  /// It places the master at the world's origin, which the camera looks at,
  /// and the ring around it.
  void _layout() {
    final svg = _svg!;
    final center = size / 2;
    final fit = math.min(
      center.x * 0.5 / svg.size.x,
      center.y * 0.5 / svg.size.y,
    );
    final componentSize = svg.size * fit;
    _master!
      ..position = Vector2.zero()
      ..size = componentSize;
    final radius = (center.x + center.y) * 0.25;
    for (var i = 0; i < _ring.length; i++) {
      final angle = _turn * (i + 1) / _ring.length;
      _ring[i]
        ..position = Vector2(math.cos(angle), math.sin(angle)) * radius
        ..size = componentSize;
    }
  }
}

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVG, with the renderer that the Renderer knob picks.
class RasterizerRenderersExample(
  super._settings, {
  required super.status,
  super.from,
}) extends SvgRenderersExample
    with HasRasterizer, ExampleRasterizer, RasterizerSvgs {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  @override
  SvgRenderer get renderer => settings.renderer;
}

/// The example with flame_svg: its `SvgComponent`s draw its SVG as images,
/// cached as its settings say when the SVG loads.
class FlameSvgRenderersExample(
  super._settings, {
  required super.status,
  super.from,
}) extends SvgRenderersExample with FlameSvgs {
  @override
  SvgCacheMode get cacheMode => settings.cacheMode;

  @override
  SvgCacheSize get cacheSize => settings.cacheSize;
}
