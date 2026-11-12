// Checks RasterizerPathComponent, in flutter_tester, with rasterizer_gpu's
// canvas renderer. From this package's folder:
//   flutter test test/path_component_test.dart
//
// The component draws its path with its paint layers, or with its paint as a
// layer, into the game's runs. Its paint applies over them, as a
// RasterizerSvgComponent's does. So its opacity, tint and hue cost no new
// import, and it imports the path again only when a layer changes. Where the
// GPU renderers can't draw a layer, or into any other canvas, it draws with
// drawPath, its paint over its layers there too.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/rendering.dart' show hueRotationMatrix;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

const _red = Color(0xffff0000);
const _blue = Color(0xff0000ff);
const _green = Color(0xff00ff00);

// A green square filling its 10 × 10 SVG.
final _svg = RasterizerSvg.fromBytes(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"> '
      '<rect width="10" height="10" fill="#00ff00"/></svg>',
    ),
  ),
);

// A 10 × 10 square.
final _square = Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10));

class _Game() extends FlameGame with HasRasterizer;

/// A game [_size] wide whose world has [components].
///
/// With [ready], the game has HasRasterizer, and its renderer is ready.
/// Without, it's a plain FlameGame. The camera looks at the world's origin,
/// in the game's centre.
Future<FlameGame> _game(List<Component> components, {bool ready = true}) async {
  final game = (ready ? _Game() : FlameGame())
    ..onGameResize(Vector2.all(_size.toDouble()));
  await game.onLoad();
  // ignore: invalid_use_of_internal_member
  game.mount();
  game.world.addAll(components);
  await game.ready();
  if (game is HasRasterizer) {
    await game.rasterizerReady;
  }
  return game;
}

/// [game]'s frame, as RGBA.
Future<Uint8List> _render(FlameGame game) async {
  final recorder = PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// [draw]'s pixels, drawn into a picture of its own, as RGBA.
Future<Uint8List> _picture(void Function(Canvas canvas) draw) async {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The pixel at [x], [y] of [pixels], as RGBA.
List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = 4 * (y * _size + x);
  return pixels.sublist(i, i + 4);
}

/// Matches a pixel within 1 of [expected] in each channel.
Matcher _near(List<int> expected) =>
    pairwiseCompare(expected, (int e, int a) => (e - a).abs() <= 1, 'near');

/// The square's centre pixel, red, filled with [filter], as dart:ui draws it.
Future<List<int>> _filteredRed(ColorFilter filter) async {
  final pixels = await _picture(
    (canvas) => canvas.drawRect(
      const Rect.fromLTWH(15, 15, 10, 10),
      Paint()
        ..color = _red
        ..colorFilter = filter,
    ),
  );
  return _pixel(pixels, 20, 20);
}

/// [path], the square by default, centred at [x], 0, filled with [color].
RasterizerPathComponent _path({
  Path? path,
  double x = 0,
  Color color = _red,
  List<Paint>? paintLayers,
  double? maxSize,
  RasterizerGlow? glow,
}) => RasterizerPathComponent(
  path: path ?? _square,
  position: Vector2(x, 0),
  anchor: Anchor.center,
  paint: Paint()..color = color,
  paintLayers: paintLayers,
  maxSize: maxSize,
  glow: glow,
);

/// The SVG, centred at [x], 0.
RasterizerSvgComponent _svgAt(double x) => RasterizerSvgComponent(
  svg: _svg,
  position: Vector2(x, 0),
  size: Vector2.all(10),
  anchor: Anchor.center,
);

/// How many runs [game]'s last frame had.
int _runs(FlameGame game) =>
    (game as HasRasterizer).rasterizerFrame!.runs.length;

void main() {
  test("it draws its path into the game's runs, with SVGs", () async {
    final path = _path();
    final game = await _game([_svgAt(-12), path, _svgAt(12)]);
    final pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 8, 20), [0, 255, 0, 255]);
    expect(_pixel(pixels, 32, 20), [0, 255, 0, 255]);
    expect(_pixel(pixels, 20, 10), [0, 0, 0, 0]);
    expect(_runs(game), 1);
    expect(path.debugScene, isNotNull);
    expect(path.debugScene!.backend, RasterizerBackend.canvas);
    expect(path.debugScene!.pathCount, 1);
    game.onRemove();
  });

  test('it draws each of its paint layers, in order', () async {
    final path = _path(
      paintLayers: [
        Paint()..color = _red,
        Paint()
          ..color = _blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      ],
    );
    final game = await _game([path]);
    final pixels = await _render(game);
    // Inside is the fill. On the edge, from 13 to 17, the stroke is over it.
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 15, 20), [0, 0, 255, 255]);
    expect(_pixel(pixels, 13, 20), [0, 0, 255, 255]);
    expect(_pixel(pixels, 11, 20), [0, 0, 0, 0]);
    expect(path.debugScene!.pathCount, 2);
    game.onRemove();
  });

  test('its scene is made again only when what it draws as a layer '
      'changes', () async {
    final path = _path();
    final game = await _game([path]);
    await _render(game);
    final scene = path.debugScene;
    game.update(0);
    await _render(game);
    expect(path.debugScene, same(scene));
    // Without paint layers, its paint's color draws as a layer's. Changing
    // that color in place imports the path again.
    path.paint.color = _blue;
    var pixels = await _render(game);
    final blue = path.debugScene;
    expect(blue, isNot(same(scene)));
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    // Its alpha applies over that layer.
    path.opacity = 0.5;
    pixels = await _render(game);
    // Premultiplied.
    expect(_pixel(pixels, 20, 20), [0, 0, 128, 128]);
    expect(path.debugScene, same(blue));
    // A paint replaced by an equal one.
    path.paint = Paint()..color = _blue.withValues(alpha: 0.5);
    await _render(game);
    expect(path.debugScene, same(blue));
    // A layer changed in place.
    final layer = Paint()..color = _red;
    path.paintLayers = [layer];
    await _render(game);
    final layered = path.debugScene;
    expect(layered, isNot(same(blue)));
    layer.color = _red.withValues(alpha: 0.5);
    pixels = await _render(game);
    expect(path.debugScene, isNot(same(layered)));
    // Its alpha, then the paint's.
    expect(_pixel(pixels, 20, 20), _near([64, 0, 0, 64]));
    game.update(0);
    game.onRemove();
  });

  test('its opacity, tint and hue are drawn in its run, with its scene, as '
      "an SVG's", () async {
    final path = _path();
    final game = await _game([_svgAt(-12), path, _svgAt(12)]);
    await _render(game);
    final scene = path.debugScene;
    path.tint(_blue);
    var pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    expect(path.debugScene, same(scene));
    expect(_runs(game), 1);
    path.opacity = 0.5;
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 0, 128, 128]);
    expect(path.debugScene, same(scene));
    expect(_runs(game), 1);
    path
      ..paint.colorFilter = null
      ..opacity = 1
      ..hue = 1;
    pixels = await _render(game);
    expect(
      _pixel(pixels, 20, 20),
      _near(await _filteredRed(ColorFilter.matrix(hueRotationMatrix(1)))),
    );
    expect(RasterizerColorTransform.of(path.paint.colorFilter!), isNotNull);
    expect(path.debugScene, same(scene));
    expect(_runs(game), 1);
    game.onRemove();
  });

  test('its paint is drawn over each of its paint layers', () async {
    final path = _path(
      paintLayers: [
        Paint()..color = _red,
        Paint()
          ..color = _blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      ],
    );
    final game = await _game([path]);
    await _render(game);
    final scene = path.debugScene;
    path.opacity = 0.5;
    var pixels = await _render(game);
    // Each layer fades on its own, as an SVG's paths do. Checked on the fill,
    // on the stroke outside it, from 13 to 15, and on the stroke over it,
    // from 15 to 17.
    expect(_pixel(pixels, 20, 20), [128, 0, 0, 128]);
    expect(_pixel(pixels, 14, 20), [0, 0, 128, 128]);
    expect(_pixel(pixels, 16, 20), _near([64, 0, 128, 191]));
    expect(path.debugScene, same(scene));
    path
      ..opacity = 1
      ..tint(_green);
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 255, 0, 255]);
    expect(_pixel(pixels, 14, 20), [0, 255, 0, 255]);
    expect(path.debugScene, same(scene));
    // Flame's hue filters each layer too. Here the layers keep their own.
    path
      ..paint.colorFilter = null
      ..hue = 1;
    await _render(game);
    expect(path.paintLayers.map((p) => p.colorFilter), everyElement(isNull));
    expect(path.debugScene, same(scene));
    game.onRemove();
  });

  test("a layer's own RasterizerColorTransform filter is drawn into its "
      'color, in its run', () async {
    final layer = Paint()
      ..color = _red
      ..colorFilter = RasterizerColorTransform.mode(
        _blue,
        BlendMode.srcATop,
      )!.filter;
    final path = _path(paintLayers: [layer]);
    final game = await _game([_svgAt(-12), path, _svgAt(12)]);
    var pixels = await _render(game);
    final scene = path.debugScene;
    expect(scene, isNotNull);
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    expect(_runs(game), 1);
    // Half white over red.
    layer.colorFilter = RasterizerColorTransform.mode(
      const Color(0x80ffffff),
      BlendMode.srcATop,
    )!.filter;
    pixels = await _render(game);
    expect(path.debugScene, isNot(same(scene)));
    expect(_pixel(pixels, 20, 20), _near([255, 128, 128, 255]));
    // A matrix, its colors clamped.
    final hue = RasterizerColorTransform.matrix(hueRotationMatrix(1))!;
    layer.colorFilter = hue.filter;
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), _near(await _filteredRed(hue.filter)));
    expect(_runs(game), 1);
    game.update(0);
    game.onRemove();
  });

  test('another color filter or blend mode on its paint draws it as a run '
      'of its own, with its scene', () async {
    final path = _path();
    final game = await _game([_svgAt(-12), path, _svgAt(12)]);
    await _render(game);
    final scene = path.debugScene;
    path.paint.colorFilter = const ColorFilter.mode(_blue, BlendMode.srcATop);
    var pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    expect(_pixel(pixels, 8, 20), [0, 255, 0, 255]);
    expect(path.debugScene, same(scene));
    expect(_runs(game), 3);
    path
      ..paint.colorFilter = null
      ..paint.blendMode = BlendMode.plus;
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(path.debugScene, same(scene));
    expect(_runs(game), 3);
    game.onRemove();
  });

  test("a layer the GPU renderers can't draw draws with drawPath, its "
      'paint over it, ending the run', () async {
    final layer = Paint()
      ..color = _red
      ..colorFilter = const ColorFilter.mode(_blue, BlendMode.srcATop);
    final path = _path(paintLayers: [layer]);
    final game = await _game([_svgAt(-12), path, _svgAt(12)]);
    var pixels = await _render(game);
    expect(path.debugScene, isNull);
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    expect(_pixel(pixels, 8, 20), [0, 255, 0, 255]);
    // The first SVG's run, then the second's.
    expect(_runs(game), 2);
    // Its paint's tint, half white, over the blue of the layer's filter. Then
    // its opacity.
    path.tint(const Color(0x80ffffff));
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), _near([128, 128, 255, 255]));
    path
      ..paint.colorFilter = null
      ..opacity = 0.5;
    pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 0, 128, 128]);
    // Without the layer's filter, it's back in the run.
    path.opacity = 1;
    layer.colorFilter = null;
    pixels = await _render(game);
    expect(path.debugScene, isNotNull);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_runs(game), 1);
    // A hairline among its layers.
    path.paintLayers = [
      Paint()..color = _red,
      Paint()
        ..color = _blue
        ..style = PaintingStyle.stroke,
    ];
    pixels = await _render(game);
    expect(path.debugScene, isNull);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_runs(game), 2);
    game.update(0);
    game.onRemove();
  });

  test('into a picture of its own, it draws with drawPath, its paint over '
      'its layers', () async {
    final path = _path();
    final layered = _path(paintLayers: [Paint()..color = _red])..tint(_blue);
    final game = await _game([path, layered]);
    await _render(game);
    void draw(Canvas canvas, PositionComponent component) =>
        component.render(canvas..translate(15, 15));
    var pixels = await _picture((canvas) => draw(canvas, path));
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 10, 20), [0, 0, 0, 0]);
    pixels = await _picture((canvas) => draw(canvas, layered));
    expect(_pixel(pixels, 20, 20), [0, 0, 255, 255]);
    layered
      ..paint.colorFilter = null
      ..opacity = 0.5;
    pixels = await _picture((canvas) => draw(canvas, layered));
    expect(_pixel(pixels, 20, 20), [128, 0, 0, 128]);
    // A layer changed in place is drawn as it is now, not as it was copied:
    // stroked, its middle is clear.
    layered.paintLayers.first
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    pixels = await _picture((canvas) => draw(canvas, layered));
    expect(_pixel(pixels, 20, 20), [0, 0, 0, 0]);
    game.onRemove();
  });

  test("before the game's renderer is ready, it draws nothing", () async {
    final path = _path();
    final game = _Game()..onGameResize(Vector2.all(_size.toDouble()));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    game.world.add(path);
    await game.ready();
    expect(game.rasterizer, isNull);
    final pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [0, 0, 0, 0]);
    // Its import is ready.
    expect(path.debugScene, isNotNull);
    await game.rasterizerReady;
    expect(_pixel(await _render(game), 20, 20), [255, 0, 0, 255]);
    game.onRemove();
  });

  test('outside a game with HasRasterizer, it draws with drawPath, its '
      'paint over its layers', () async {
    final path = _path(x: -12);
    final layered = _path(paintLayers: [Paint()..color = _red])..opacity = 0.5;
    final game = await _game([path, layered], ready: false);
    final pixels = await _render(game);
    expect(_pixel(pixels, 8, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 20, 20), [128, 0, 0, 128]);
    expect(path.debugScene, isNull);
    expect(layered.debugScene, isNull);
    game.onRemove();
  });

  test("its scene is freed when it's removed, and made again when it's "
      'added back', () async {
    final path = _path();
    final game = await _game([path]);
    await _render(game);
    final scene = path.debugScene;
    path.removeFromParent();
    game.update(0);
    expect(path.debugScene, isNull);
    game.world.add(path);
    game.update(0);
    final pixels = await _render(game);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(path.debugScene, isNot(same(scene)));
    game.onRemove();
  });

  test('components made with the same path share a scene for the same '
      'paints', () async {
    final a = _path(x: -12);
    final b = _path(x: 12);
    // Its paint's alpha and tint apply over the import.
    final faded = _path(color: _red.withValues(alpha: 0.5))..tint(_blue);
    final blue = _path(color: _blue);
    final copy = _path(path: Path.from(_square));
    final larger = _path(maxSize: 4096);
    final game = await _game([a, b, faded, blue, copy, larger]);
    final pixels = await _render(game);
    expect(a.debugScene, isNotNull);
    expect(b.debugScene, same(a.debugScene));
    expect(faded.debugScene, same(a.debugScene));
    for (final other in [blue, copy, larger]) {
      expect(other.debugScene, isNotNull);
      expect(other.debugScene, isNot(same(a.debugScene)));
    }
    expect(_pixel(pixels, 8, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 32, 20), [255, 0, 0, 255]);
    game.onRemove();
  });

  test('components share a scene for the same glow, and another one makes '
      'its own', () async {
    double radius() => 4;
    final a = _path(glow: RasterizerGlow(radius()));
    final b = _path(glow: RasterizerGlow(radius()));
    final other = _path(glow: const RasterizerGlow(8));
    final plain = _path();
    final game = await _game([a, b, other, plain]);
    await _render(game);
    expect(a.debugScene, isNotNull);
    expect(b.debugScene, same(a.debugScene));
    for (final different in [other, plain]) {
      expect(different.debugScene, isNotNull);
      expect(different.debugScene, isNot(same(a.debugScene)));
    }
    game.onRemove();
  });

  test(
    'its scene is made again when its glow changes, and only then',
    () async {
      final path = _path(glow: const RasterizerGlow(4));
      final game = await _game([path]);
      await _render(game);
      final scene = path.debugScene;
      await _render(game);
      expect(path.debugScene, same(scene));
      // An equal glow.
      path.glow = const RasterizerGlow(2.0 * 2);
      await _render(game);
      expect(path.debugScene, same(scene));
      path.glow = const RasterizerGlow.widths(4);
      await _render(game);
      final widths = path.debugScene;
      expect(widths, isNot(same(scene)));
      path.glow = null;
      await _render(game);
      expect(path.debugScene, isNot(same(widths)));
      expect(path.debugScene, isNotNull);
      game.update(0);
      game.onRemove();
    },
  );

  test('without the mesh renderer, it draws without its glow', () async {
    final path = _path(glow: const RasterizerGlow(4));
    final game = await _game([path]);
    var pixels = await _render(game);
    expect(path.debugScene!.backend, RasterizerBackend.canvas);
    expect(path.debugScene!.pathCount, 1);
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 13, 20), [0, 0, 0, 0]);
    // Nor into a picture of its own.
    pixels = await _picture((canvas) => path.render(canvas..translate(15, 15)));
    expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 13, 20), [0, 0, 0, 0]);
    game.onRemove();
  });

  test('a path away from the origin is drawn where PathComponent draws '
      'it', () async {
    final away = Path()..addRect(const Rect.fromLTWH(5, 5, 10, 10));
    final a = _path(path: away);
    final b = _path(path: away, x: -12);
    final game = await _game([a, b]);
    final pixels = await _render(game);
    expect(b.debugScene, same(a.debugScene));
    // As _square's: from 15 to 25, and from 3 to 13.
    expect(_pixel(pixels, 15, 15), [255, 0, 0, 255]);
    expect(_pixel(pixels, 24, 24), [255, 0, 0, 255]);
    expect(_pixel(pixels, 14, 20), [0, 0, 0, 0]);
    expect(_pixel(pixels, 25, 20), [0, 0, 0, 0]);
    expect(_pixel(pixels, 3, 20), [255, 0, 0, 255]);
    expect(_pixel(pixels, 2, 20), [0, 0, 0, 0]);
    game.onRemove();
  });

  test(
    'a shared scene is kept while a component uses it, and found again',
    () async {
      final a = _path(x: -12);
      final b = _path(x: 12);
      final game = await _game([a, b]);
      await _render(game);
      final scene = a.debugScene;
      // With another color, a makes an import of its own, and b keeps the
      // first one. Back to the first color, a finds that import again.
      a.paint.color = _blue;
      await _render(game);
      expect(a.debugScene, isNot(same(scene)));
      expect(b.debugScene, same(scene));
      a.paint.color = _red;
      await _render(game);
      expect(a.debugScene, same(scene));
      // Once neither uses it, it's freed, so another component makes its own.
      b.removeFromParent();
      game.update(0);
      a.paint.color = _blue;
      await _render(game);
      game.update(0);
      final c = _path();
      game.world.add(c);
      game.update(0);
      final pixels = await _render(game);
      expect(c.debugScene, isNotNull);
      expect(c.debugScene, isNot(same(scene)));
      expect(_pixel(pixels, 20, 20), [255, 0, 0, 255]);
      game.onRemove();
    },
  );

  test("removing the game releases its components' scenes", () async {
    final a = _path();
    var game = await _game([a]);
    await _render(game);
    final scene = a.debugScene;
    game.onRemove();
    expect(a.debugScene, isNull);
    final b = _path();
    game = await _game([b]);
    await _render(game);
    expect(b.debugScene, isNotNull);
    expect(b.debugScene, isNot(same(scene)));
    game.onRemove();
  });

  test("maxSize is the view's longer side by default, and positive", () {
    expect(
      RasterizerPathComponent(path: _square).maxSize,
      RasterizerSvg.defaultMaxSize,
    );
    expect(RasterizerPathComponent(path: _square, maxSize: 64).maxSize, 64);
    for (final maxSize in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => RasterizerPathComponent(path: _square, maxSize: maxSize),
        throwsArgumentError,
      );
    }
  });

  test("its polygons are PathComponent's", () {
    final path = RasterizerPathComponent(
      path: Path()..addRect(const Rect.fromLTWH(5, 5, 10, 10)),
    );
    expect(path.size, Vector2.all(10));
    expect(path.polygons, hasLength(1));
    expect(path.containsLocalPoint(Vector2(5, 5)), isTrue);
    expect(path.containsLocalPoint(Vector2(12, 5)), isFalse);
  });
}
