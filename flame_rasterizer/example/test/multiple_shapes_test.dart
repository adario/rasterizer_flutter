// Checks the Multiple Shapes example in widget tests: it loads with each
// renderer and kind of shape, tints shapes while they collide, follows its
// knobs, and wraps shapes around the arena.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/collision_detection.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/multiple_shapes_example.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

/// The Multiple Shapes story with [renderer] and [count] shapes of the kind
/// [shapes], at [speed]. A seeded random picks the shapes.
///
/// The story keeps the same game for a new [count]. A new renderer makes a new
/// game, which goes on from the old one's snapshot.
Widget story(
  SvgRenderer renderer, {
  Shapes shapes = Shapes.svgs,
  int count = 15,
  double speed = 1,
}) => MaterialApp(
  home: GameStory<MultipleShapesExample, MultipleShapesSnapshot>(
    renderer: renderer,
    create: (status, from) => MultipleShapesExample.of(
      (renderer: renderer, shapes: shapes, count: count),
      status,
      random: math.Random(1),
      from: from,
    ),
    snapshot: (game) => game.snapshot,
    update: (game) => game.count = count,
    speed: speed,
  ),
);

/// The game the pumped story shows.
MultipleShapesExample currentGame(WidgetTester tester) => tester
    .widget<GameWidget<MultipleShapesExample>>(
      find.byWidgetPredicate((w) => w is GameWidget),
    )
    .game!;

/// Waits for the shown game to load, and draws a frame.
Future<MultipleShapesExample> loadGame(WidgetTester tester) async {
  final game = currentGame(tester);
  // Its assets load in real time, outside the test's fake time.
  await pumpWhileLoading(tester, () => !game.isLoaded);
  expect(game.isLoaded, isTrue);
  await tester.pump(const Duration(milliseconds: 16));
  return game;
}

/// Pumps [story], and waits for its game to load.
Future<MultipleShapesExample> pumpGame(
  WidgetTester tester,
  SvgRenderer renderer, {
  Shapes shapes = Shapes.svgs,
  double speed = 1,
}) async {
  await tester.pumpWidget(story(renderer, shapes: shapes, speed: speed));
  return await loadGame(tester);
}

/// The color filter that Flame's `tint` sets for [color].
ui.ColorFilter tinted(Color color) =>
    ui.ColorFilter.mode(color, ui.BlendMode.srcATop);

/// The component that draws [shape]'s path.
RasterizerPathComponent pathOf(TintedShape shape) =>
    shape.children.whereType<RasterizerPathComponent>().single;

void main() {
  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer. Only one test loads SVGs with
  // flame_svg: vector_graphics shares its loads between tests, and one
  // test's fake time doesn't run another test's loads. Paths only read the
  // SVGs' files, so they load nothing with flame_svg.
  for (final (renderer, shapes, status) in [
    (
      SvgRenderer.rasterizer,
      Shapes.svgs,
      'flame_rasterizer, canvas (noImpeller)',
    ),
    (SvgRenderer.flameSvg, Shapes.svgs, 'flame_svg'),
    (
      SvgRenderer.rasterizer,
      Shapes.paths,
      'flame_rasterizer, canvas (noImpeller)',
    ),
    (SvgRenderer.flameSvg, Shapes.paths, "Flame's PathComponent"),
  ]) {
    testWidgets('the game loads with ${renderer.label} and ${shapes.label}', (
      tester,
    ) async {
      final game = await pumpGame(tester, renderer, shapes: shapes);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final tintedShapes = game.tintedShapes;
      // All 15, as the rows shrink to fit the test's 800 by 600 window.
      expect(tintedShapes, hasLength(15));
      for (final shape in tintedShapes) {
        expect(shape.children.whereType<SvgHitbox>(), hasLength(1));
        final images = shape.children.where(
          (child) => child is! SvgHitbox && child is PositionComponent,
        );
        final image = images.single;
        switch (shapes) {
          case Shapes.svgs:
            expect(shape, isA<TintedSvg>());
            expect(image, isNot(isA<PathComponent>()));
          case Shapes.paths:
            expect(shape, isA<TintedPath>());
            expect(image, isA<PathComponent>());
            expect(
              image is RasterizerPathComponent,
              renderer != SvgRenderer.flameSvg,
            );
        }
      }
      final [snowman] = game.collidables
          .whereType<CollidableSnowman>()
          .toList();
      expect(snowman.children.whereType<SnowmanPart>(), hasLength(3));
      expect(find.textContaining(status), findsOneWidget);
      final what = shapes == Shapes.svgs ? 'SVGs' : 'paths';
      expect(
        find.textContaining('${tintedShapes.length} $what and a snowman'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  // The shapes of one SVG get equal paints, but each its own, so that each
  // is tinted on its own. Their components still share one import, the
  // scene that `debugScene` returns, tinted or not.
  testWidgets("an SVG's paths share its path and scene", (tester) async {
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizer,
      shapes: Shapes.paths,
      speed: 0,
    );
    final paths = game.tintedShapes.cast<TintedPath>();
    final byOutline = <SvgOutline, List<TintedPath>>{};
    for (final path in paths) {
      (byOutline[path.outline] ??= []).add(path);
    }
    // The seeded random picks some SVGs more than once.
    expect(byOutline.length, lessThan(paths.length));
    final scenes = <Object>{};
    for (final group in byOutline.values) {
      final drawn = [for (final path in group) pathOf(path)];
      final scene = drawn.first.debugScene;
      expect(scene, isNotNull);
      for (final component in drawn) {
        expect(component.debugScene, same(scene));
      }
      expect(scenes.add(scene!), isTrue);
      final paints = {for (final component in drawn) ...component.paintLayers};
      expect(paints, hasLength(2 * drawn.length));
    }
    expect(scenes, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  for (final shapes in Shapes.values) {
    testWidgets('a shape is tinted while it collides, with ${shapes.label}', (
      tester,
    ) async {
      final game = await pumpGame(
        tester,
        SvgRenderer.rasterizer,
        shapes: shapes,
        speed: 0,
      );
      final [a, b, c, ...] = game.tintedShapes;
      // Keep only three shapes: remove the others and the snowman.
      for (final other in game.collidables) {
        if (other != a && other != b && other != c) {
          other.removeFromParent();
          game.tintedShapes.remove(other);
        }
      }
      final rect = game.arena.toRect();
      // Puts a shape at (x, y), upright and still.
      void place(TintedShape shape, double x, double y) {
        shape
          ..position = Vector2(x, y)
          ..angle = 0
          ..velocity.setZero();
      }

      Future<void> step() async {
        game.update(0);
        await tester.pump(const Duration(milliseconds: 16));
      }

      RasterizerFrame frame() =>
          (game as RasterizerMultipleShapesExample).rasterizerFrame!;
      // A tint folds into the shape's entry in the frame, for SVGs and paths
      // alike. So the three shapes still draw in one run, and the paths keep
      // their imports.
      void expectDrawn() {
        expect(frame().entryCount, 3);
        expect(frame().runs, hasLength(1));
        if (shapes == Shapes.paths) {
          for (final shape in [a, b, c]) {
            expect(pathOf(shape).debugScene, isNotNull);
          }
        }
      }

      // Each shape apart from the others and from the walls.
      place(a, rect.center.dx - rect.width / 4, rect.center.dy);
      place(b, rect.center.dx + rect.width / 4, rect.center.dy);
      place(c, rect.center.dx, rect.center.dy - rect.height / 4);
      await step();
      expect([a.tintFilter, b.tintFilter, c.tintFilter], [null, null, null]);
      expectDrawn();

      // b half over a, so that their outlines cross: a hitbox wholly inside
      // another doesn't collide.
      place(b, a.position.x + (a.size.x + b.size.x) / 4, a.position.y);
      await step();
      expect(a.tintFilter, tinted(TintedShape.collisionTint));
      expect(b.tintFilter, tinted(TintedShape.collisionTint));
      expect(c.tintFilter, isNull);
      expectDrawn();
      if (shapes == Shapes.paths) {
        // The tint is on the component's paint. Its fill and stroke paints
        // keep no filter.
        expect(pathOf(a).paint.colorFilter, tinted(TintedShape.collisionTint));
        expect(
          pathOf(a).paintLayers.map((paint) => paint.colorFilter),
          everyElement(isNull),
        );
      }

      // Put c on the right wall.
      place(c, rect.right, rect.center.dy);
      await step();
      expect(c.tintFilter, tinted(TintedShape.wallTint));
      expectDrawn();

      // Move them apart again.
      place(b, rect.center.dx + rect.width / 4, rect.center.dy);
      place(c, rect.center.dx, rect.center.dy - rect.height / 4);
      await step();
      expect([a.tintFilter, b.tintFilter, c.tintFilter], [null, null, null]);
      expectDrawn();
      await tester.pumpWidget(const SizedBox());
    });
  }

  // The shapes that stay go on moving, resized to the new scale, with their
  // images and hitboxes.
  for (final shapes in Shapes.values) {
    testWidgets('a new shape number adds shapes to the game, or removes '
        'some, with ${shapes.label}', (tester) async {
      final game = await pumpGame(
        tester,
        SvgRenderer.rasterizer,
        shapes: shapes,
      );
      final kept = [...game.tintedShapes];
      final width = kept.first.size.x;
      await tester.pumpWidget(
        story(SvgRenderer.rasterizer, shapes: shapes, count: 50),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(currentGame(tester), same(game));
      expect(game.tintedShapes, hasLength(50));
      expect(game.tintedShapes.take(15), kept);
      expect(game.world.children.whereType<TintedShape>(), hasLength(50));
      final first = kept.first;
      expect(first.size.x, lessThan(width));
      final rect = first.outline.rect;
      switch (shapes) {
        case Shapes.svgs:
          expect(
            first.children.whereType<RasterizerSvgComponent>().single.size,
            first.size,
          );
        case Shapes.paths:
          // The path's scale stretches the outline's rect to the shape's
          // size, as its hitbox's scale does.
          final image = pathOf(first);
          expect(image.scale.x, closeTo(first.size.x / rect.width, 1e-6));
          expect(image.scale.y, closeTo(first.size.y / rect.height, 1e-6));
      }
      final hitbox = first.children.whereType<SvgHitbox>().single;
      expect(hitbox.scale.x, closeTo(first.size.x / rect.width, 1e-6));

      await tester.pumpWidget(
        story(SvgRenderer.rasterizer, shapes: shapes, count: 2),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.tintedShapes, kept.take(2));
      expect(game.world.children.whereType<TintedShape>(), hasLength(2));
      expect(first.size.x, greaterThan(width));
      await tester.pumpWidget(const SizedBox());
    });
  }

  // At speed 0, a new renderer's game shows the same shapes, where the old
  // game's were, and hands the same snapshot on to the next game. Paths load
  // nothing with flame_svg, so they can switch to Flame SVG: see the comment
  // at the top of main.
  for (final (shapes, renderers) in [
    (
      Shapes.svgs,
      [SvgRenderer.rasterizerCanvas, SvgRenderer.rasterizer],
    ),
    (
      Shapes.paths,
      [SvgRenderer.flameSvg, SvgRenderer.rasterizerCanvas],
    ),
  ]) {
    testWidgets('a new renderer goes on from where the ${shapes.label} were', (
      tester,
    ) async {
      var game = await pumpGame(tester, SvgRenderer.rasterizer, shapes: shapes);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpWidget(
        story(SvgRenderer.rasterizer, shapes: shapes, speed: 0),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final snapshot = game.snapshot;
      expect(snapshot.shapes, hasLength(15));
      for (final renderer in renderers) {
        final next = await pumpGame(tester, renderer, shapes: shapes, speed: 0);
        expect(next, isNot(same(game)));
        expect(game.isAttached, isFalse);
        await tester.pump(const Duration(milliseconds: 16));
        final nextSnapshot = next.snapshot;
        expect(nextSnapshot.picks, snapshot.picks);
        expect(nextSnapshot.snowman, snapshot.snowman);
        expect(nextSnapshot.shapes, snapshot.shapes);
        expect(
          [for (final shape in next.tintedShapes) shape.size],
          [for (final shape in game.tintedShapes) shape.size],
        );
        game = next;
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('new shapes make a new game', (
    tester,
  ) async {
    Widget shapesStory(Shapes shapes, {int count = 4}) => MaterialApp(
      home: MultipleShapesStory(
        settings: (
          renderer: SvgRenderer.rasterizerCanvas,
          shapes: shapes,
          count: count,
        ),
      ),
    );

    await tester.pumpWidget(shapesStory(Shapes.svgs));
    final svgs = await loadGame(tester);
    expect(svgs.shapes, Shapes.svgs);
    await tester.pumpWidget(shapesStory(Shapes.svgs, count: 5));
    await tester.pump(const Duration(milliseconds: 16));
    expect(currentGame(tester), same(svgs));

    await tester.pumpWidget(shapesStory(Shapes.paths, count: 5));
    final paths = await loadGame(tester);
    expect(paths, isNot(same(svgs)));
    expect(paths.shapes, Shapes.paths);
    expect(paths.tintedShapes, hasLength(5));
    expect(svgs.isAttached, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new cache makes a new game with Flame SVG', (tester) async {
    // With paths, which load no SVG with flame_svg: see the comment at the
    // top of main. The story's key holds the cache with paths too, as with
    // SVGs.
    Widget cacheStory(SvgCache cache) => MaterialApp(
      home: MultipleShapesStory(
        settings: (
          renderer: SvgRenderer.flameSvg,
          shapes: Shapes.paths,
          count: 4,
        ),
        cache: cache,
      ),
    );

    await tester.pumpWidget(cacheStory(defaultSvgCache));
    final first = await loadGame(tester);
    await tester.pumpWidget(
      cacheStory((mode: SvgCacheMode.fixed, size: SvgCacheSize.large)),
    );
    final game = await loadGame(tester) as FlameMultipleShapesExample;
    expect(game, isNot(same(first)));
    expect(game.cacheMode, SvgCacheMode.fixed);
    expect(game.cacheSize, SvgCacheSize.large);
    expect(first.isAttached, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('at speed 0, the components stand still', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, speed: 0);
    final positions = [
      for (final component in game.collidables) component.position.clone(),
    ];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect([
      for (final component in game.collidables) component.position,
    ], positions);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a component all outside the arena comes back in on the other '
      'side', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    // It's anchored at its center, so its position is its center at any
    // angle.
    final shape = game.tintedShapes.first;
    expect(shape.anchor, Anchor.center);
    final rect = game.arena.toRect();
    final width = shape.width * shape.scale.x.abs();
    final height = shape.height * shape.scale.y.abs();
    // Past the right wall and above the top one, by a little more than half
    // its size, so that it stays wholly outside as it moves in a frame.
    final x = rect.right + width / 2 + 20;
    final y = rect.top - height / 2 - 20;
    shape.position.setValues(x, y);
    final velocity = shape.velocity.clone();
    await tester.pump(const Duration(milliseconds: 16));
    final moved = Vector2(x, y)..addScaled(velocity, 0.016);
    expect(
      shape.position.x,
      closeTo(moved.x - rect.width - width, 1e-3),
    );
    expect(
      shape.position.y,
      closeTo(moved.y + rect.height + height, 1e-3),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
