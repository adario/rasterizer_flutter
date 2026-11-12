import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/svg/svg.dart';
import 'package:flame_rasterizer_example/stories/svg/svg_renderers_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A game whose status the test starts and stops by hand, without a widget.
class _StatusGame({required super.status}) extends ExampleGame {
  @override
  String get rendererText => 'renderer';

  @override
  Iterable<String> get rendererStats => const [];

  void beginStatus() => startStatus();

  void endStatus() => stopStatus();
}

/// A game that draws the SVGs called [names] with flame_svg.
class _CacheGame({
  required super.status,
  @override final SvgCacheSize cacheSize = SvgCacheSize.standard,
  final List<String> names = const [],
}) extends ExampleGame with ExampleSvgs, FlameSvgs {
  @override
  SvgCacheMode get cacheMode => SvgCacheMode.integral;

  @override
  Future<void> onLoad() async {
    for (final name in names) {
      final svg = await loadSvg('assets/svgs/$name.svg');
      world.add(svg.component()..size = Vector2.all(64));
    }
  }
}

void main() {
  for (final width in [360.0, 1600.0]) {
    testWidgets('the game keeps its size in a window $width wide', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SvgRenderersStory(
            settings: (
              renderer: SvgRenderer.rasterizerCanvas,
              svg: 'android',
              count: 20,
              fade: false,
              cacheMode: SvgCacheMode.integral,
              cacheSize: SvgCacheSize.standard,
            ),
          ),
        ),
      );
      final finder = find.byWidgetPredicate((w) => w is GameWidget);
      final first = tester.getRect(finder);
      final game = tester.widget<GameWidget<SvgRenderersExample>>(finder).game!;
      expect(game.status.value, isEmpty);
      for (var i = 0; i < 100 && game.status.value.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(finder), first, reason: 'at frame $i');
      }
      expect(game.status.value, contains('flame_rasterizer'));
      for (final text in ['', 'short', 'a long status · ' * 50]) {
        game.status.value = text;
        await tester.pump();
        expect(tester.getRect(finder), first, reason: text);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the status leaves blank the times it has no frames for', (
    tester,
  ) async {
    final status = ValueNotifier('');
    addTearDown(status.dispose);
    final game = _StatusGame(status: status)..beginStatus();
    addTearDown(game.endStatus);
    game.update(0.25);
    expect(status.value, 'renderer · render  · build  · raster ');
  });

  test('without its SVGs, an unlimited cache has no total', () {
    final status = ValueNotifier('');
    addTearDown(status.dispose);
    expect(
      _CacheGame(
        status: status,
        cacheSize: SvgCacheSize.unlimited,
      ).rendererStats,
      ['cache 0/∞, integral'],
    );
  });

  // The file's only test that loads SVGs with flame_svg. flame_svg shares its
  // loads between tests, and a test's fake time doesn't run another test's
  // loads.
  testWidgets('flame_svg shows one total for all its SVGs', (tester) async {
    final status = ValueNotifier('');
    addTearDown(status.dispose);
    final game = _CacheGame(
      status: status,
      names: const ['android', 'clover', 'robot'],
    );
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    final size = SvgCacheSize.standard.quantity * 3;
    // Each SVG rasterizes its image outside the test's fake time.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      if (game.rendererStats.single == 'cache 3/$size, integral') {
        break;
      }
    }
    expect(game.rendererStats.single, 'cache 3/$size, integral');
    await tester.pumpWidget(const SizedBox());
  });
}
