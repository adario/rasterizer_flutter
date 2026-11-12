import 'dart:io';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/main.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/svg/svg.dart';
import 'package:flame_rasterizer_example/stories/svg/svg_renderers_example.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

/// The Svg Renderers story with [renderer] and [svg].
Widget story(
  SvgRenderer renderer,
  String svg, {
  int count = 20,
  bool fade = false,
  double zoom = 1,
  double speed = 1,
}) => MaterialApp(
  home: SvgRenderersStory(
    settings: (
      renderer: renderer,
      svg: svg,
      count: count,
      fade: fade,
      cacheMode: SvgCacheMode.integral,
      cacheSize: SvgCacheSize.standard,
    ),
    zoom: zoom,
    speed: speed,
  ),
);

/// Pumps the story with [renderer] and [svg], and waits for its game to load.
Future<SvgRenderersExample> pumpGame(
  WidgetTester tester,
  SvgRenderer renderer,
  String svg, {
  bool fade = false,
  double zoom = 1,
}) async {
  await tester.pumpWidget(story(renderer, svg, fade: fade, zoom: zoom));
  final game = tester
      .widget<GameWidget<SvgRenderersExample>>(
        find.byWidgetPredicate((w) => w is GameWidget),
      )
      .game!;
  // The game's assets load outside the test's fake time.
  await pumpWhileLoading(tester, () => !game.isLoaded);
  expect(game.isLoaded, isTrue);
  return game;
}

/// The paths of the use cases with the Renderer, Zoom and Speed knobs.
const paths = [
  'svg/svg-renderers',
  'svg/collidable-svgs',
  'collision-detection/multiple-shapes',
  'forge2d/revolute-joint-svgs',
  'games/svg-shooter',
  'games/tube-shooter',
];

void main() {
  test('the Svg knob lists every SVG in assets/svgs/', () {
    final files = [
      for (final file in Directory('assets/svgs').listSync(recursive: true))
        if (file.path.endsWith('.svg'))
          file.path.replaceFirst('assets/svgs/', '').replaceAll('.svg', ''),
    ];
    expect(svgNames, unorderedEquals(files));
    expect(svgNames.toSet().length, svgNames.length);
  });

  testWidgets('the Widgetbook builds', (tester) async {
    // A desktop window, wide enough for Widgetbook to show its navigation.
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FlameRasterizerExamples());
    await tester.pumpAndSettle();
    expect(find.text('flame_rasterizer Examples'), findsOneWidget);
    expect(find.text('Svg Renderers'), findsOneWidget);
    expect(find.text('Collidable Svgs'), findsOneWidget);
    expect(find.text('Multiple Shapes'), findsOneWidget);
    expect(find.text('Revolute Joint Svgs'), findsOneWidget);
    expect(find.text('Svg Shooter'), findsOneWidget);
    expect(find.text('Tube Shooter'), findsOneWidget);
  });

  // Below 840 wide, such as macOS's default window, Widgetbook shows the knobs
  // in a sheet. From 840 on, it shows them in a side panel a fifth of the
  // window wide.
  for (final (width, path) in [
    for (final path in paths)
      for (final width in [800.0, 840.0, 1280.0]) (width, path),
  ]) {
    testWidgets('the knobs of $path fit in a window $width wide', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FlameRasterizerExamples(initialRoute: '/?path=$path'),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (width < 840) {
        await tester.tap(find.text('Knobs'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(find.text('Renderer'), findsOneWidget);
      // The sheet builds the knobs below its fold only as it scrolls.
      if (width < 840) {
        await tester.scrollUntilVisible(
          find.text('Speed'),
          100,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        );
      }
      expect(find.text('Zoom'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets("flame_svg's knobs show only with flame_svg", (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=svg/svg-renderers'),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pick(SvgRenderer renderer) async {
      await tester.tap(find.byType(DropdownMenu<SvgRenderer>));
      await settle();
      await tester.tap(find.text(renderer.label).last);
      await settle();
    }

    await settle();
    expect(find.text('Renderer'), findsOneWidget);
    expect(find.text('Cache mode'), findsNothing);
    expect(find.text('Cache size'), findsNothing);
    await pick(SvgRenderer.flameSvg);
    expect(find.text('Cache mode'), findsOneWidget);
    expect(find.text('Cache size'), findsOneWidget);
    await pick(SvgRenderer.rasterizerCanvas);
    expect(find.text('Cache mode'), findsNothing);
    expect(find.text('Cache size'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // Tests run without Impeller, where GPU (mesh) is inactive.
  // integration_test/knobs_test.dart checks the Glow knob with it.
  testWidgets("Tube Shooter's Glow knob doesn't show, and no line glows, "
      'without GPU (mesh)', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=games/tube-shooter'),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    void expectNoGlow(SvgRenderer renderer) {
      final story = tester.widget<TubeShooterStory>(
        find.byType(TubeShooterStory),
      );
      expect(story.renderer, renderer);
      expect(story.glow, isFalse);
      expect(find.text('Glow'), findsNothing);
    }

    await settle();
    expect(find.text('Drifting stars'), findsOneWidget);
    expectNoGlow(SvgRenderer.rasterizerCanvas);
    await tester.tap(find.byType(DropdownMenu<SvgRenderer>));
    await settle();
    await tester.tap(find.text(SvgRenderer.flameSvg.label).last);
    await settle();
    expectNoGlow(SvgRenderer.flameSvg);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Zoom and Speed are continuous, to two decimals in tabular '
      'figures', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=svg/svg-renderers'),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final sliders = tester.widgetList<Slider>(find.byType(Slider));
    bool continuous(double min, double max) =>
        sliders.any((s) => s.min == min && s.max == max && s.divisions == null);
    expect(continuous(0.25, 5), isTrue);
    expect(continuous(0, 2), isTrue);
    // Both show 1.00, in tabular figures, so that every value has the same
    // width.
    final values = find.text('1.00');
    expect(values, findsNWidgets(2));
    for (final value in values.evaluate()) {
      expect(
        DefaultTextStyle.of(value).style.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  // Tests run without Impeller, where the GPU renderers aren't supported.
  for (final path in paths) {
    testWidgets('GPU entries are inactive in the Renderer knob of $path', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FlameRasterizerExamples(initialRoute: '/?path=$path'),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final menu = tester.widget<DropdownMenu<SvgRenderer>>(
        find.byType(DropdownMenu<SvgRenderer>),
      );
      expect(menu.initialSelection, SvgRenderer.rasterizerCanvas);
      expect(
        {
          for (final entry in menu.dropdownMenuEntries)
            entry.label: entry.enabled,
        },
        {
          'GPU (mesh)': false,
          'GPU (atlas)': false,
          'Canvas': true,
          'Flame SVG': true,
        },
      );
      expect(
        find.textContaining('flame_rasterizer, canvas (forced)'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer. Each test loads a different SVG:
  // vector_graphics, under flame_svg, shares its loads between tests, and a
  // test's fake time doesn't run another test's loads.
  var nextSvg = 0;
  for (final (renderer, status) in [
    (SvgRenderer.rasterizer, 'flame_rasterizer, canvas (noImpeller)'),
    (SvgRenderer.rasterizerAtlas, 'flame_rasterizer, canvas (noImpeller)'),
    (SvgRenderer.rasterizerCanvas, 'flame_rasterizer, canvas (forced)'),
    (SvgRenderer.flameSvg, 'flame_svg'),
  ]) {
    for (final fade in [false, true]) {
      final svg = svgNames[nextSvg++];
      testWidgets('the game loads with ${renderer.label}, '
          '${fade ? '' : 'not '}fading, $svg', (tester) async {
        final game = await pumpGame(tester, renderer, svg, fade: fade);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // The world holds the master and the ring of 20. The FPS text is in
        // the viewport, above the world.
        expect(game.world.children.whereType<PositionComponent>().length, 21);
        expect(
          game.camera.viewport.children.whereType<FpsTextComponent>().length,
          1,
        );
        expect(find.textContaining(status), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  // A new zoom keeps the same game, with its SVG and timings.
  for (final renderer in [SvgRenderer.rasterizer, SvgRenderer.flameSvg]) {
    testWidgets('the game zooms in place with ${renderer.label}', (
      tester,
    ) async {
      final svg = svgNames[nextSvg++];
      final game = await pumpGame(tester, renderer, svg, zoom: 0.5);
      expect(game.camera.viewfinder.zoom, 0.5);
      await tester.pumpWidget(story(renderer, svg, zoom: 4));
      await tester.pump(const Duration(milliseconds: 16));
      final zoomed = tester
          .widget<GameWidget<SvgRenderersExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      expect(zoomed, same(game));
      expect(game.camera.viewfinder.zoom, 4);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // A new speed keeps the same game. At 0, its SVGs stand still.
  for (final renderer in [SvgRenderer.rasterizer, SvgRenderer.flameSvg]) {
    testWidgets('the game slows down in place with ${renderer.label}', (
      tester,
    ) async {
      final svg = svgNames[nextSvg++];
      final game = await pumpGame(tester, renderer, svg);
      final master = game.world.children.whereType<PositionComponent>().first;
      Future<double> turned() async {
        final angle = master.angle;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        return master.angle - angle;
      }

      expect(await turned(), isNot(0));
      await tester.pumpWidget(story(renderer, svg, speed: 0));
      expect(game.speed, 0);
      expect(await turned(), 0);
      await tester.pumpWidget(story(renderer, svg, speed: 0.5));
      final slowed = tester
          .widget<GameWidget<SvgRenderersExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      expect(slowed, same(game));
      expect(game.speed, 0.5);
      expect(await turned(), isNot(0));
      await tester.pumpWidget(const SizedBox());
    });
  }

  // The other knobs keep the same game too. New components replace the old
  // ones, turned as far, and a new SVG loads into the same game. A missing
  // SVG shows its error until another loads.
  for (final renderer in [SvgRenderer.rasterizer, SvgRenderer.flameSvg]) {
    testWidgets('the other knobs change the game in place with '
        '${renderer.label}', (tester) async {
      final svg = svgNames[nextSvg++];
      final other = svgNames[nextSvg++];
      final game = await pumpGame(tester, renderer, svg);
      List<PositionComponent> components() =>
          game.world.children.whereType<PositionComponent>().toList();
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      // SVGs load outside the test's fake time.
      Future<void> loadUntil(bool Function() done) async {
        await pumpWhileLoading(tester, () => !done());
        expect(done(), isTrue);
      }

      SvgRenderersExample current() => tester
          .widget<GameWidget<SvgRenderersExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;
      int fps() =>
          game.camera.viewport.children.whereType<FpsTextComponent>().length;

      // The first component is the master, under the ring. A game starts
      // at the angles where the last one stopped, so it turns from there.
      await frames(1);
      final start = components().first.angle;
      await frames(30);
      final angle = components().first.angle;
      expect(angle, isNot(closeTo(start, 1)));
      await tester.pumpWidget(story(renderer, svg, count: 30, fade: true));
      await frames(1);
      expect(current(), same(game));
      expect(components(), hasLength(31));
      expect(components().first.angle, closeTo(angle, 0.1));
      // Next comes the ring's last SVG, which is the faintest.
      expect((components()[1] as HasPaint).paint.color.a, lessThan(0.5));

      final before = components().first;
      await tester.pumpWidget(story(renderer, other, count: 30, fade: true));
      await loadUntil(() => components().first != before);
      expect(current(), same(game));
      expect(components(), hasLength(31));

      // Not 'missing', the next test's SVG: flame_svg shares its loads
      // between tests, and a test's fake time doesn't run another test's
      // loads.
      await tester.pumpWidget(story(renderer, 'absent', count: 30, fade: true));
      await loadUntil(() => components().isEmpty);
      await frames(20);
      expect(find.textContaining("Couldn't load absent.svg"), findsOneWidget);
      expect(fps(), 0);

      await tester.pumpWidget(story(renderer, svg, count: 10));
      await loadUntil(() => components().length == 11);
      await frames(20);
      expect(current(), same(game));
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(fps(), 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // Like tiger.svg, which the pub.dev package leaves out.
  for (final renderer in [SvgRenderer.rasterizer, SvgRenderer.flameSvg]) {
    testWidgets('a missing SVG with ${renderer.label}', (tester) async {
      final game = await pumpGame(tester, renderer, 'missing');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.world.children, isEmpty);
      expect(game.children.whereType<PositionComponent>(), isEmpty);
      expect(find.textContaining("Couldn't load missing.svg"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
