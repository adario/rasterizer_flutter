// Checks the Svg Renderers game with each renderer and each SVG, then changes
// its other knobs in place and switches between renderers, on a device:
//   flutter test integration_test/renderers_test.dart -d <macos|emulator-5554>
//
// Each game must load, draw and name its renderer in the status bar: the GPU
// renderer it's for wherever that's supported, else the canvas one. With
// flame_rasterizer, the ring and the master, faded or not, must draw in one
// run: a batch of entries, each an SVG placed in the frame, that the renderer
// draws together. A new SVG, SVG number or fade replaces the game's
// components, but must keep the same game.
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/stories/svg/svg.dart';
import 'package:flame_rasterizer_example/stories/svg/svg_renderers_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'renderer_status.dart';

// A game loads and runs in seconds, or in half a minute with the canvas
// renderer on the emulator. With the mesh renderer and the tiger on Linux's
// llvmpipe, which renders in software, it takes over a minute: 100 tigers
// take 2 s a frame. A test that takes longer than twice that is stuck. The
// switching test runs 9 games, 3 of them with the mesh renderer and the
// tiger.
const _timeout = Timeout(Duration(minutes: 2));
const _switchingTimeout = Timeout(Duration(minutes: 8));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  /// Runs [settings]' game for about half a second, and returns its status.
  Future<String> run(WidgetTester tester, SvgRenderersSettings settings) async {
    await tester.pumpWidget(
      MaterialApp(home: SvgRenderersStory(settings: settings)),
    );
    final game = tester
        .widget<GameWidget<SvgRenderersExample>>(
          find.byWidgetPredicate((w) => w is GameWidget),
        )
        .game!;
    // Wait for a new game to load, or for the running one to load its new
    // SVG.
    for (var i = 0; i < 600 && !(game.isLoaded && game.settled); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(game.isLoaded, isTrue, reason: '${settings.svg} not loaded');
    expect(game.settled, isTrue, reason: '${settings.svg} not loaded');
    await settleRenderer(tester, settings.renderer);
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
    final status = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .firstWhere((text) => text.contains(' · '), orElse: () => '');
    final line =
        '${settings.renderer.name} ${settings.svg}'
        '${settings.count == 100 ? '' : ' ${settings.count}'}'
        '${settings.fade ? ' faded' : ''}: $status';
    // ignore: avoid_print
    print('  RASTERIZER_EXAMPLE $line');
    // On the web, prints go to the browser's console: flutter drive gets the
    // status from the response data instead.
    (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] = status;
    return status;
  }

  SvgRenderersSettings settings(
    SvgRenderer renderer,
    String svg, {
    int count = 100,
    bool fade = false,
  }) => (
    renderer: renderer,
    svg: svg,
    count: count,
    fade: fade,
    cacheMode: SvgCacheMode.integral,
    cacheSize: SvgCacheSize.standard,
  );

  /// Expects [status] to name [renderer], and with flame_rasterizer, one run
  /// of the ring's [count] SVGs and the master.
  void expectRenderer(String status, SvgRenderer renderer, {int count = 100}) {
    expect(status, startsWith(rendererStatus(renderer)));
    if (renderer != SvgRenderer.flameSvg) {
      expect(status, contains('1 run, ${count + 1} entries'));
    }
  }

  // A test for each renderer and SVG, with every other SVG faded.
  for (final renderer in SvgRenderer.values) {
    for (final (i, svg) in svgNames.indexed) {
      testWidgets('${renderer.label}, $svg${i.isOdd ? ', faded' : ''}', (
        tester,
      ) async {
        final status = await run(
          tester,
          settings(renderer, svg, fade: i.isOdd),
        );
        expectRenderer(status, renderer);
        await tester.pumpWidget(const SizedBox());
      }, timeout: _timeout);
    }
  }

  // The other knobs change the running game. It frees the SVGs that it no
  // longer draws, while its renderer goes on drawing.
  for (final renderer in SvgRenderer.values) {
    testWidgets('${renderer.label}, other knobs in place', (tester) async {
      SvgRenderersExample? first;
      for (final (svg, count, fade) in [
        ('android', 100, false),
        ('robot', 100, true),
        ('robot', 30, true),
        ('tiger', 30, false),
        ('android', 100, false),
      ]) {
        final status = await run(
          tester,
          settings(renderer, svg, count: count, fade: fade),
        );
        expectRenderer(status, renderer, count: count);
        final game = tester
            .widget<GameWidget<SvgRenderersExample>>(
              find.byWidgetPredicate((w) => w is GameWidget),
            )
            .game!;
        expect(game, same(first ??= game));
      }
      await tester.pumpWidget(const SizedBox());
    }, timeout: _timeout);
  }

  testWidgets('switching renderers back and forth', (tester) async {
    for (final renderer in [
      SvgRenderer.rasterizer,
      SvgRenderer.flameSvg,
      SvgRenderer.rasterizerAtlas,
      SvgRenderer.rasterizerCanvas,
      SvgRenderer.rasterizer,
      SvgRenderer.rasterizerAtlas,
      SvgRenderer.rasterizerCanvas,
      SvgRenderer.flameSvg,
      SvgRenderer.rasterizer,
    ]) {
      expectRenderer(await run(tester, settings(renderer, 'tiger')), renderer);
    }
    await tester.pumpWidget(const SizedBox());
  }, timeout: _switchingTimeout);
}
