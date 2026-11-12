// Checks RasterizerSvgComponents drawn with their paint, which their effects
// change, in flutter_tester, with the canvas renderer. From this package's
// folder:
//   flutter test test/paint_test.dart
//
// The paint's alpha fades each path. Its other fields apply to one image, as
// to a sprite (see rasterizer_gpu's rasterizer_canvas_test.dart). Tints and
// hues are filters that each path takes, so tinted components share a run.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 40;

RasterizerSvg _fromString(String svg) =>
    RasterizerSvg.fromBytes(Uint8List.fromList(utf8.encode(svg)));

// A red square filling its 10 × 10 SVG.
final _svg = _fromString(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"> '
  '<rect width="10" height="10" fill="#ff0000"/></svg>',
);

late RasterizerRenderer _renderer;

/// Draws [draw] into a [RasterizerCanvas] over a new frame.
///
/// Returns how many runs it made, and the frame's pixels, as RGBA.
Future<(int, Uint8List)> _frame(void Function(RasterizerCanvas) draw) async {
  final recorder = PictureRecorder();
  final frame = _renderer.beginFrame(_size, _size);
  final canvas = RasterizerCanvas()..begin(Canvas(recorder), frame, 1);
  draw(canvas);
  canvas.end();
  frame.render();
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return (canvas.runCount, data!.buffer.asUint8List());
}

/// The pixel at [x], [y] of [pixels], as RGBA.
List<int> _pixel(Uint8List pixels, int x, int y) {
  final i = 4 * (y * _size + x);
  return pixels.sublist(i, i + 4);
}

Paint _faded(double opacity, [Color color = const Color(0xffffffff)]) =>
    Paint()..color = color.withValues(alpha: opacity);

// Records its paint's filter each time onChanged is called.
class _Changes({super.svg}) extends RasterizerSvgComponent {
  ColorFilter? filter;

  @override
  void onChanged() {
    super.onChanged();
    filter = paint.colorFilter;
  }
}

void main() {
  setUpAll(() async {
    _renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.canvas,
    );
  });

  group('RasterizerSvgComponent', () {
    Future<(FlameGame, RasterizerSvgComponent)> mounted([Paint? paint]) async {
      final component = RasterizerSvgComponent(
        svg: _svg,
        size: Vector2.all(_size.toDouble()),
        paint: paint,
      );
      // As GameWidget mounts a game, and flame_test does, without a widget.
      final game = FlameGame()..onGameResize(Vector2.all(_size.toDouble()));
      // ignore: invalid_use_of_internal_member
      await game.load();
      // ignore: invalid_use_of_internal_member
      game.mount();
      game.update(0);
      game.world.add(component);
      await game.ready();
      return (game, component);
    }

    Future<List<int>> centre(RasterizerSvgComponent component) async {
      final (_, pixels) = await _frame(component.renderTree);
      return _pixel(pixels, 20, 20);
    }

    test('draws with its paint', () async {
      final (_, component) = await mounted(_faded(0.25));
      expect((await centre(component))[3], closeTo(64, 1));
    });

    test('an OpacityEffect fades it', () async {
      final (game, component) = await mounted();
      expect((await centre(component))[3], 255);
      component.add(OpacityEffect.to(0.5, EffectController(duration: 1)));
      await game.ready();
      game.update(1);
      expect(component.opacity, closeTo(0.5, 1e-6));
      expect((await centre(component))[3], closeTo(128, 1));
    });

    test('a ColorEffect tints it', () async {
      final (game, component) = await mounted();
      component.add(
        ColorEffect(
          const Color(0xff0000ff),
          EffectController(duration: 1),
        ),
      );
      await game.ready();
      game.update(1);
      expect(await centre(component), [0, 0, 255, 255]);
    });

    test('components tinted and hued by effects share a run', () async {
      final (game, a) = await mounted();
      final b = RasterizerSvgComponent(svg: _svg, size: Vector2.all(10));
      final c = RasterizerSvgComponent(svg: _svg, size: Vector2.all(10));
      game.world.addAll([b, c]);
      await game.ready();
      a.add(
        ColorEffect(
          const Color(0xff0000ff),
          EffectController(duration: 1),
          opacityTo: 0.8,
        ),
      );
      b.add(HueEffect.to(1, EffectController(duration: 1)));
      c.add(
        ColorEffect(
          const Color(0xff00ff00),
          EffectController(duration: 2),
          opacityTo: 0.5,
        ),
      );
      await game.ready();
      game.update(0.5);
      expect(c.paint.colorFilter, isNotNull);
      final (runs, _) = await _frame((canvas) {
        for (final component in [a, b, c]) {
          component.renderTree(canvas);
        }
      });
      expect(runs, 1);
    });

    test('a HueEffect shifts its hue', () async {
      final (game, component) = await mounted();
      component.add(HueEffect.to(2.0943951, EffectController(duration: 1)));
      await game.ready();
      game.update(1);
      // A third of a turn takes red near green.
      final [r, g, b, a] = await centre(component);
      expect(g, greaterThan(r));
      expect(g, greaterThan(b));
      expect(a, 255);
    });

    test("onChanged sees a hue's filter, which a run can read", () {
      final component = _Changes(svg: _svg)..hue = 1;
      expect(RasterizerColorTransform.of(component.filter!), isNotNull);
      component.hue = 0;
      expect(component.filter, isNull);
    });
  });
}
