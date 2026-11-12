import 'dart:io';
import 'dart:math' as math;

import 'package:flame/components.dart' show TextComponent;
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/forge2d/revolute_joint_svgs_example.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';

/// The smallest [Forge2DExampleGame]: a physics world with one ball.
class _WorldGame({required super.status}) extends Forge2DExampleGame {
  this : super(world: Forge2DExampleWorld());

  @override
  String get rendererText => '';

  @override
  Iterable<String> get rendererStats => const [];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    world.add(
      Ball(
        Vector2.zero(),
        Vector2.zero(),
        radius: 1,
        color: ExampleColors.slate,
      ),
    );
  }
}

/// Pumps [widget], and waits for [game] to load.
Future<void> pumpGame(
  WidgetTester tester,
  Widget widget,
  FlameGame Function() game,
) async {
  await tester.pumpWidget(widget);
  // The game's assets and Box2D load outside the test's fake time.
  await pumpWhileLoading(tester, () => !game().isLoaded);
  expect(game().isLoaded, isTrue);
}

void main() {
  setUpAll(forge2d.initializeForge2D);

  test("each SVG's convex pieces fit Box2D", () {
    final world = forge2d.World();
    addTearDown(world.destroy);
    for (final name in randomSvgNames) {
      final outline = SvgOutline.fromSvg(
        File('assets/svgs/$name.svg').readAsBytesSync(),
      );
      for (final side in [3.0, 3.1, 3.2, 3.3, 3.4, 3.5]) {
        final rect = outline.rect;
        final size =
            Vector2(rect.width, rect.height) *
            (side / math.max(rect.width, rect.height));
        final pieces = convexPiecesOf(outline, size);
        expect(pieces, isNotEmpty);
        final body = world.createBody(
          forge2d.BodyDef(type: forge2d.BodyType.dynamic),
        );
        for (final piece in pieces) {
          expect(piece.length, inInclusiveRange(3, 8));
          // flame_forge2d warns about smaller shapes.
          expect(
            pieceSide(piece),
            greaterThanOrEqualTo(0.1),
            reason: '$name at $side m',
          );
          // Box2D throws if the hull that it makes of the piece is degenerate.
          body.createShape(forge2d.Polygon(piece), forge2d.ShapeDef());
        }
        body.destroy();
      }
    }
  });

  // Tests run without Impeller, so flame_rasterizer draws with
  // rasterizer_gpu's canvas renderer.
  testWidgets('a tap drops 15 bodies, the SVGs in one run, Pieces too', (
    tester,
  ) async {
    late RevoluteJointSvgsExample game;
    Widget story({bool pieces = false}) => MaterialApp(
      home: GameStory<RevoluteJointSvgsExample>(
        create: (status) => game = RevoluteJointSvgsExample.of(
          (renderer: SvgRenderer.rasterizer, pieces: pieces),
          status,
          random: math.Random(1),
        ),
        update: (game) => game.pieces = pieces,
      ),
    );
    await pumpGame(tester, story(), () => game);
    await tester.pump(const Duration(milliseconds: 16));
    final rect = tester.getRect(
      find.byType(GameWidget<RevoluteJointSvgsExample>),
    );
    await tester.tapAt(Offset(rect.center.dx, rect.top + 60));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.svgBodies.length + game.balls.length, 15);
    final arena = Rect.fromCenter(
      center: Offset.zero,
      width: game.size.x / game.metersToPixels,
      height: game.size.y / game.metersToPixels,
    );
    for (final body in [...game.svgBodies, ...game.balls]) {
      final position = body.body.position;
      expect(arena.contains(Offset(position.x, position.y)), isTrue);
    }
    expect(find.textContaining('canvas (noImpeller) · '), findsOneWidget);
    expect(
      find.textContaining('1 run, ${game.svgBodies.length} entries'),
      findsOneWidget,
    );
    expect(find.textContaining('${game.balls.length} balls, '), findsOneWidget);
    // The bodies dropped, plus the 4 walls, the 2 ramps and the wheel.
    expect(
      game.camera.viewport.children.whereType<TextComponent>().map(
        (text) => text.text,
      ),
      contains('Bodies: ${15 + 7}'),
    );

    // PiecesLayer draws after all the bodies, so the SVGs stay in one run.
    await tester.pumpWidget(story(pieces: true));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.pieces, isTrue);
    expect(
      find.textContaining('1 run, ${game.svgBodies.length} entries'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  // Box2D has room for 128 worlds at once, so each game must destroy its own.
  testWidgets('new games, one after another, have room for their worlds', (
    tester,
  ) async {
    for (var i = 0; i < 130; i++) {
      final game = _WorldGame(status: ValueNotifier(''));
      await pumpGame(
        tester,
        MaterialApp(
          home: GameWidget(key: ValueKey(i), game: game),
        ),
        () => game,
      );
      expect(game.world.physicsWorld.isValid, isTrue, reason: 'game $i');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
