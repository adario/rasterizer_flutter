// Checks the Tube Shooter example headlessly, with flame_rasterizer's canvas
// renderer and with Flame's PathComponent. It covers the tube's geometry, the
// ship, the shots, the enemies, the stars, the glow, the game's states and
// texts, and that no path falls back from the renderer in a whole game.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/edge_walker_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/explosion_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/player_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/spawn_dot_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/star_field_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_while_loading.dart';
import 'tube_shooter_whole_game.dart';

/// The game with [renderer], at [zoom] and [speed], starting from
/// [firstLevel], with a seeded random so that runs repeat.
///
/// With [pixelRatio], it sits in a MediaQuery of that device pixel ratio, as
/// Widgetbook's device frames set one.
Widget story(
  SvgRenderer renderer, {
  double zoom = 1,
  double speed = 1,
  int firstLevel = 0,
  double? pixelRatio,
}) => MaterialApp(
  builder: pixelRatio == null
      ? null
      : (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(devicePixelRatio: pixelRatio),
          child: child!,
        ),
  home: GameStory<TubeShooterExample, Never>(
    renderer: renderer,
    create: (status, _) => TubeShooterExample.of(
      renderer,
      status,
      random: math.Random(1),
      firstLevel: firstLevel,
    ),
    zoom: zoom,
    speed: speed,
  ),
);

/// The index of the octagon's level, whose tube and enemies most tests count
/// on.
final octagonLevel = levels.indexWhere((level) => level.tube == Tubes.octagon);

/// Pumps a [story] from [firstLevel], or from the octagon's level by default,
/// and waits for its game to load.
Future<TubeShooterExample> pumpGame(
  WidgetTester tester,
  SvgRenderer renderer, {
  double zoom = 1,
  int? firstLevel,
  double? pixelRatio,
}) async {
  await tester.pumpWidget(
    story(
      renderer,
      zoom: zoom,
      firstLevel: firstLevel ?? octagonLevel,
      pixelRatio: pixelRatio,
    ),
  );
  final game = tester
      .widget<GameWidget<TubeShooterExample>>(
        find.byWidgetPredicate((w) => w is GameWidget),
      )
      .game!;
  await pumpWhileLoading(tester, () => !game.isLoaded);
  expect(game.isLoaded, isTrue);
  // The game loop's first frame has no time step, so pump one more.
  await tester.pump(const Duration(milliseconds: 16));
  return game;
}

/// Pumps [frames] of 16 ms.
Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Pumps frames until [done], at most [frames] of them, then expects [done].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int frames = 300,
}) async {
  for (var i = 0; i < frames && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue);
}

/// Pumps frames until [game] waits on READY, at most [frames] of them, and
/// begins its level with a key press.
Future<void> beginLevel(
  WidgetTester tester,
  TubeShooterExample game, {
  int frames = 300,
}) async {
  await pumpUntil(tester, () => game.state == TubeState.ready, frames: frames);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
  expect(game.state, TubeState.play);
}

/// Pumps the game with flame_rasterizer, and begins its level once zoomed in.
///
/// It turns spawning off, so that no enemy comes and a test adds its own.
Future<TubeShooterExample> playing(
  WidgetTester tester, {
  int? firstLevel,
}) async {
  final game = await pumpGame(
    tester,
    SvgRenderer.rasterizer,
    firstLevel: firstLevel,
  );
  game.spawning = false;
  await beginLevel(tester, game);
  return game;
}

/// The path components of the tube group: the tube, the ship's lane, and the
/// spikes and the bolts while there are any.
Iterable<PathComponent> tubePathsOf(TubeShooterExample game) =>
    game.tubeGroup.children.whereType<PathComponent>();

/// The explosions of [game].
Iterable<ExplosionComponent> explosionsOf(TubeShooterExample game) =>
    game.explosionGroup.children.whereType<ExplosionComponent>();

/// Fires one shot from the ship, over one frame.
Future<void> fireOnce(WidgetTester tester, TubeShooterExample game) async {
  game.player.beginFire();
  await tester.pump(const Duration(milliseconds: 16));
  game.player.stopFire();
}

/// Walks the ship from one end of open [tube] to the other, on the tube's
/// level, once the stars have settled at the first end.
///
/// Returns a star that starts 1.5 from the eye, how far it turned about the
/// axis, and how far the ship's angle turned.
Future<(StarComponent, double, double)> walkOpenTube(
  WidgetTester tester,
  Tube tube,
) async {
  final game = await playing(
    tester,
    firstLevel: levels.indexWhere((level) => level.tube == tube),
  );
  await pumpFrames(tester, 20);
  expect(game.state, TubeState.play);
  expect(tube.isOpen, isTrue);
  game.player.moveBy(-100);
  await pumpFrames(tester, 60);
  // Near the camera's aim, the middle of the tube's drawing, so on screen.
  const from = Offset(0.3, 0.6);
  final star = game.starField.stars[0]
    ..point = from
    ..eyeDistance = 1.5;
  final heading = PlayerComponent.headingOn(tube, game.player.step);
  game.player.moveBy(100);
  await pumpFrames(tester, 60);
  return (
    star,
    star.point.direction - from.direction,
    PlayerComponent.headingOn(tube, game.player.step) - heading,
  );
}

void main() {
  final tube = Tubes.octagon;

  group('the tube', () {
    test('has 16 lanes as wide, its sides 1 from its axis', () {
      expect(tube.points, hasLength(16));
      for (var i = 0; i < tube.laneCount; i++) {
        final width =
            (tube.points[tube.pointAfter(i)] - tube.points[i]).distance;
        expect(width, closeTo(tube.laneWidth, 1e-9));
      }
      final reach = tube.points
          .map((point) => math.max(point.dx.abs(), point.dy.abs()))
          .reduce(math.max);
      expect(reach, closeTo(1, 1e-9));
      // The points go round to the right along the bottom side.
      expect(tube.points[0].dy, closeTo(1, 1e-9));
      expect(tube.points[1].dx, greaterThan(tube.points[0].dx));
      expect(tube.points[1].dy, closeTo(1, 1e-9));
    });

    test('is 3.8 times smaller at its far end, each lane at its angle at '
        'every depth', () {
      final view = TubeView()..fit(900, 0.5);
      expect(view.scaleAt(0), 450);
      expect(view.scaleAt(0) / view.scaleAt(Tube.depth), closeTo(3.8, 1e-9));
      for (final depth in [0.0, 1.0, Tube.depth]) {
        for (var i = 0; i < tube.laneCount; i++) {
          final edge =
              view.project(tube.points[i], depth) -
              view.project(tube.points[tube.pointAfter(i)], depth);
          expect(edge.direction, closeTo(tube.angles[i], 1e-9));
        }
      }
    });

    test('draws lines 4 device pixels wide at the rim, thinner with depth, '
        'but never under a device pixel', () {
      const pixel = 0.5;
      final view = TubeView()..fit(900, pixel);
      expect(view.lineWidthAt(0), 4 * pixel);
      expect(view.lineWidthAt(Tube.depth), closeTo(4 / 3.8 * pixel, 1e-9));
      // The shapes' strokes, in lane units, scaled to a lane's width.
      double strokeAt(double depth) =>
          view.shapeStroke * tube.laneWidth * view.scaleAt(depth);
      expect(strokeAt(0), closeTo(4 * pixel, 1e-9));
      expect(strokeAt(Tube.depth), closeTo(4 / 3.8 * pixel, 1e-9));
      // With the eye far back, as the zoom starts, the lines stay a device
      // pixel wide.
      view.eyeShift = -TubeShooterExample.zoomDistance;
      expect(view.lineWidthAt(Tube.depth), pixel);
      expect(view.lineWidthAt(0), pixel);
    });

    test('draws its lines a sixteenth of a device pixel off its axis, so that '
        "the edges of one along an axis don't step together", () {
      const pixel = 0.5;
      final center = (TubeView()..fit(900, pixel))
          .tubePath()
          .getBounds()
          .center;
      expect(center.dx, closeTo(pixel / 16, 1e-3));
      expect(center.dy, closeTo(pixel / 16, 1e-3));
    });

    test('clips its lines before the eye, as it drops', () {
      final view = TubeView()
        ..fit(900, 0.5)
        ..eyeShift = Tube.depth;
      final bounds = view.tubePath().getBounds();
      // Only the far end's ring is left, as large as the rim in play, and the
      // spokes. The view clips them 0.2 before the eye, where they're 5 times
      // larger.
      expect(bounds.width, greaterThan(4 * 900));
      expect(bounds.width, lessThan(6 * 900));
    });

    test('flips a shape onto a neighbouring lane through its inside, '
        'landing half a turn from that lane', () {
      for (var i = 0; i < tube.laneCount; i++) {
        for (final to in [tube.neighbour(i, -1)!, tube.neighbour(i, 1)!]) {
          final corner = tube.points[tube.cornerOf(i, to)];
          final angle = tube.flipAngle(i, to);
          final start = tube.middles[i] - corner;
          final end = corner + Tube.rotate(start, angle);
          expect((end - tube.middles[to]).distance, lessThan(1e-9));
          final middle = corner + Tube.rotate(start, angle / 2);
          expect(middle.distance, lessThan(corner.distance));
          var landing = tube.angles[i] + angle - tube.angles[to] - math.pi;
          landing -= 2 * math.pi * (landing / (2 * math.pi)).roundToDouble();
          expect(landing, closeTo(0, 1e-9));
        }
      }
    });

    test('every tube has lanes as wide, round its axis, within 1 of it, and '
        'flips a shape onto its neighbour, through a closed one', () {
      for (final tube in Tubes.all) {
        final points = tube.points;
        final inside = ui.Path()..addPolygon(points, true);
        for (var i = 0; i < tube.laneCount; i++) {
          final a = points[i];
          final b = points[tube.pointAfter(i)];
          expect(
            (b - a).distance,
            closeTo(tube.laneWidth, 1e-9),
            reason: tube.name,
          );
          // The lanes go round to the right along the bottom side, and none
          // points at the axis.
          expect(a.dx * b.dy - a.dy * b.dx, lessThan(-0.01), reason: tube.name);
          expect(math.max(a.dx.abs(), a.dy.abs()), lessThan(1 + 1e-9));
          for (final side in [-1, 1]) {
            final to = tube.neighbour(i, side);
            if (to == null) {
              continue;
            }
            final corner = points[tube.cornerOf(i, to)];
            final start = tube.middles[i] - corner;
            final angle = tube.flipAngle(i, to);
            final end = corner + Tube.rotate(start, angle);
            expect((end - tube.middles[to]).distance, lessThan(1e-9));
            if (!tube.isOpen) {
              final middle = corner + Tube.rotate(start, angle / 2);
              expect(inside.contains(middle), isTrue, reason: tube.name);
            }
          }
        }
      }
    });

    test('has a climber and a zapper that look the same turned by half a '
        'turn', () {
      for (final shape in [Shapes.climber, Shapes.zapper]) {
        // Half a turn: x and y negated.
        final turned = shape.transform(
          Float64List.fromList([
            -1,
            0,
            0,
            0,
            0,
            -1,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        );
        List<ui.Offset> pointsOf(ui.Path path) => [
          for (final metric in path.computeMetrics())
            for (var d = 0.0; d <= metric.length; d += metric.length / 50)
              metric.getTangentForOffset(d)!.position,
        ];
        final points = pointsOf(shape);
        for (final point in pointsOf(turned)) {
          final nearest = points
              .map((other) => (other - point).distance)
              .reduce(math.min);
          expect(nearest, lessThan(0.05));
        }
      }
    });
  });

  for (final (renderer, status) in [
    (SvgRenderer.rasterizer, 'flame_rasterizer, canvas (noImpeller)'),
    (SvgRenderer.flameSvg, "Flame's PathComponent"),
  ]) {
    testWidgets('the game loads with ${renderer.label}, and zooms in, the '
        "tube's path made again each frame", (tester) async {
      final game = await pumpGame(tester, renderer);
      expect(game.state, TubeState.zoom);
      expect(game.round, 1);
      expect(game.player.isVisible, isFalse);
      expect(game.spawns, hasLength(16));
      expect(game.starField.stars, hasLength(StarFieldComponent.count));
      await pumpFrames(tester, 70);
      expect(game.state, TubeState.ready);
      expect(game.player.isVisible, isTrue);
      expect(game.player.lane, 0);
      expect(game.view.eyeShift, 0);
      await beginLevel(tester, game);
      await pumpFrames(tester, 2);
      // The tube and the ship's lane, with no spikes or bolts yet.
      final paths = tubePathsOf(game).toList();
      expect(paths, hasLength(2));
      for (final path in paths) {
        expect(
          path is RasterizerPathComponent,
          renderer != SvgRenderer.flameSvg,
        );
      }
      expect(game.pathsPerSecond, greaterThan(50));
      final text = find.textContaining(status);
      expect(text, findsOneWidget);
      final line = tester.widget<Text>(text).data!;
      expect(line, contains(' paths/s'));
      if (renderer != SvgRenderer.flameSvg) {
        expect(line, contains(RegExp(r'\b1 run, ')));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('its lines keep their device widths at any zoom', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer, zoom: 2);
    await pumpUntil(tester, () => game.state == TubeState.ready);
    final ratio = tester.view.devicePixelRatio;
    expect(game.view.devicePixel, 1 / (ratio * 2));
    // A paint keeps its stroke width as a 32-bit float.
    expect(
      game.player.drawing.paint.strokeWidth,
      closeTo(game.view.shapeStroke, 1e-6 * game.view.shapeStroke),
    );
    expect(
      game.spawns.first.scale.x,
      closeTo(SpawnDotComponent.pixels * game.view.devicePixel, 1e-6),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('its lines are in the device pixels of its MediaQuery, as the '
      "renderer's", (tester) async {
    expect(tester.view.devicePixelRatio, isNot(1.5));
    final game = await pumpGame(
      tester,
      SvgRenderer.rasterizer,
      pixelRatio: 1.5,
    );
    expect(game.view.devicePixel, 1 / 1.5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on an open tube the ship stops at the ends, an enemy turns '
      'back there, and the camera looks at its middle', (tester) async {
    final game = await playing(tester, firstLevel: 2);
    final tube = game.view.tube;
    final player = game.player;
    expect(tube.isOpen, isTrue);
    expect(player.lane, tube.bottomLane);
    player.moveBy(-100);
    expect(player.step, 0);
    player.moveBy(100);
    expect(player.step, tube.laneCount * PlayerComponent.stepsPerLane - 1);
    expect(
      game.camera.viewfinder.position.y,
      closeTo(tube.center.dy * game.view.rimScale, 1e-3),
    );
    final climber = ClimberComponent(lane: 0, depth: Tube.depth / 2);
    game.addEnemy(climber);
    await pumpFrames(tester, 1);
    climber.flipAside(-1);
    await pumpFrames(tester, 30);
    expect(climber.lane, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('each round is on the next level, whose tube replaces the old '
      'one, with what was in its lanes', (tester) async {
    final game = await playing(tester, firstLevel: 0);
    expect(game.view.tube, same(levels[0].tube));
    // The hexagon's last lane, lane 11, which the next level's Floor, with 8
    // lanes, doesn't have.
    game.player.step = 11 * PlayerComponent.stepsPerLane + 8;
    game.clearSpawns();
    await pumpUntil(tester, () => game.state == TubeState.drop);
    game.player.beginFire();
    await pumpUntil(tester, () => game.round == 2);
    game.player.stopFire();
    await pumpFrames(tester, 2);
    expect(game.level, same(levels[1]));
    expect(game.view.tube, same(levels[1].tube));
    expect(game.player.lane, levels[1].tube.bottomLane);
    expect(game.spawns, hasLength(12));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the ship moves 16 steps a lane, round the tube, by keys and '
      'drags', (tester) async {
    final game = await playing(tester);
    final player = game.player;
    expect(player.step, PlayerComponent.startStep);
    player.moveBy(1);
    expect(player.step, 24);
    expect(player.lane, 1);
    player.moveBy(-2);
    expect(player.lane, 15);
    expect(player.step, 248);
    player.moveBy(1 / 32);
    expect(player.step, 248);
    player.moveBy(1 / 32);
    expect(player.step, 249);

    // A drag of 80 logical pixels to the right: two lanes.
    player.step = 8;
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    final drag = await tester.startGesture(center);
    await tester.pump();
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    await drag.up();
    expect(player.lane, 2);
    expect(player.step, 40);

    // Half a second of the right arrow, speeding up from 3 lanes a second to
    // 10.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await pumpFrames(tester, 31);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final lanes = (player.step - 40) / PlayerComponent.stepsPerLane;
    expect(lanes, closeTo(3 * 0.5 + 7 * 0.5 / 2, 0.25));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shots cross the tube down the ship lane, 8 at most', (
    tester,
  ) async {
    final game = await playing(tester);
    game.player.step = 3 * 16 + 8;
    game.player.beginFire();
    var most = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      most = math.max(most, game.shots.length);
      for (final shot in game.shots) {
        expect(shot.lane, 3);
      }
    }
    // A shot every 0.1 s, each crossing the tube in 0.5 s: 5 or 6 at once.
    expect(most, inInclusiveRange(5, 6));
    game.player.stopFire();
    await pumpFrames(tester, 40);
    expect(game.shots, isEmpty);
    // No more than 8 in the tube.
    for (var i = 0; i < 8; i++) {
      game.fire(3, 0);
    }
    game.player.beginFire();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.shots, hasLength(8));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the enemies to come wait as dots of their colours, wandering '
      'round the far end; each flashes white in its lane, then comes there', (
    tester,
  ) async {
    final game = await playing(tester);
    final spawns = [...game.spawns];
    expect(spawns, hasLength(16));
    int countOf(Color color) => spawns
        .where(
          (spawn) =>
              spawn.drawing.paint.color.toARGB32() == color.toARGB32() &&
              spawn.drawing.paint.style == PaintingStyle.fill,
        )
        .length;
    final level = game.level;
    expect(countOf(TubeColors.climber), level.climbers);
    expect(countOf(TubeColors.splitter), level.splitters);
    expect(countOf(TubeColors.seeder), level.seeders);
    expect(countOf(TubeColors.zapper), level.zappers);
    expect(countOf(TubeColors.edgeWalker), level.edgeWalkers);
    // Each dot lies on the far end's outline, so its distance from the axis
    // is between a side's middle's and a corner's.
    final far = game.view.scaleAt(Tube.depth);
    for (final spawn in spawns) {
      expect(
        spawn.position.length / far,
        inInclusiveRange(1 - 1e-6, 1 / math.cos(math.pi / 8) + 1e-6),
      );
    }
    final before = [for (final spawn in spawns) spawn.at];
    await pumpFrames(tester, 10);
    for (final (i, spawn) in spawns.indexed) {
      expect(spawn.at, isNot(before[i]));
      expect(spawn.isArriving, isFalse);
    }

    // The next enemy to come arrives as a flashing dot at its lane's middle.
    game.spawning = true;
    await tester.pump(const Duration(milliseconds: 16));
    game.spawning = false;
    final arriving = game.spawns.singleWhere((spawn) => spawn.isArriving);
    expect(arriving, same(game.spawns.last));
    final lane = arriving.lane;
    final tints = <bool>{};
    var frames = 0;
    while (game.enemies.isEmpty && frames < 40) {
      await tester.pump(const Duration(milliseconds: 16));
      tints.add(arriving.drawing.paint.colorFilter != null);
      frames++;
    }
    expect(tints, {true, false});
    expect(frames * 0.016, greaterThanOrEqualTo(SpawnDotComponent.arriveTime));
    expect(arriving.at, closeTo(lane + 0.5, 1e-9));
    final enemy = game.enemies.single;
    expect(enemy.kind, arriving.kind);
    expect(enemy.lane, lane);
    expect(enemy.depth, closeTo(Tube.depth, 0.05));
    expect(game.spawns, hasLength(15));
    expect(game.spawns, isNot(contains(arriving)));
    // The dots add no path to the tube group.
    expect(tubePathsOf(game), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stars fly by on the drop and the zoom, around the tube, '
      'and stay after them', (tester) async {
    final game = await playing(tester);
    final field = game.starField;
    expect(field.stars, hasLength(StarFieldComponent.count));

    game.clearSpawns();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.drop);
    await pumpFrames(tester, 30);
    final pixel = game.view.devicePixel;
    for (final star in field.stars) {
      final (inner, outer) = StarFieldComponent.radii;
      expect(star.point.distance, inInclusiveRange(inner, outer));
      expect(
        star.eyeDistance,
        inInclusiveRange(TubeView.near, StarFieldComponent.far),
      );
      // Twice the lines' width at the star's depth. A component keeps its
      // scale in 32-bit floats.
      expect(
        star.scale.y / pixel,
        inInclusiveRange(2 - 1e-6, 2 * TubeView.rimPixels + 1e-6),
      );
      // Each star is a streak, pointing out from the axis.
      expect(star.cameFrom, greaterThanOrEqualTo(star.eyeDistance));
      expect(star.scale.x, greaterThanOrEqualTo(star.scale.y));
      expect(star.angle, closeTo(star.point.direction, 1e-6));
      // Farther stars are dimmer, by their opacity, not a tint. Faded in by
      // now, a star is at its brightest from the bright distance in. A paint
      // keeps its color in 32-bit floats.
      expect(
        star.brightness == 1,
        star.eyeDistance <= StarFieldComponent.bright,
      );
      expect(star.drawing.opacity, closeTo(star.brightness, 1e-6));
      expect(star.drawing.paint.colorFilter, isNull);
    }
    // A star comes as much closer as the eye went deeper.
    final star = field.stars.firstWhere((star) => star.eyeDistance > 2);
    final (eyeDistance, eyeShift) = (star.eyeDistance, game.view.eyeShift);
    await tester.pump(const Duration(milliseconds: 16));
    final deeper = game.view.eyeShift - eyeShift;
    expect(deeper, greaterThan(0));
    expect(star.eyeDistance, closeTo(eyeDistance - deeper, 1e-9));
    // On screen, its streak runs from where it was to where it is.
    final view = game.view;
    final from = star.point * view.scaleOf(eyeDistance);
    final to = star.point * view.scaleOf(star.eyeDistance);
    expect(star.position.x, closeTo((from.dx + to.dx) / 2, 1e-3));
    expect(star.position.y, closeTo((from.dy + to.dy) / 2, 1e-3));
    expect(star.scale.x - star.scale.y, closeTo((to - from).distance, 1e-3));

    // The stars stay through the zoom, and after it.
    await pumpUntil(tester, () => game.state == TubeState.zoom, frames: 200);
    expect(field.stars, hasLength(StarFieldComponent.count));
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 100);
    await pumpFrames(tester, 25);
    expect(field.stars, hasLength(StarFieldComponent.count));
    expect(field.children, hasLength(StarFieldComponent.count));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("on an open tube, the stars lie round the viewport's centre, "
      "where the camera looks, not round the tube's axis", (tester) async {
    final floor = levels.indexWhere((level) => level.tube == Tubes.floor);
    final game = await playing(tester, firstLevel: floor);
    await pumpFrames(tester, 2);
    final centre = game.camera.viewfinder.position;
    expect(centre.y, greaterThan(0));
    final view = game.view;
    for (final star in game.starField.stars) {
      final drawn =
          star.point *
          ((view.scaleOf(star.eyeDistance) + view.scaleOf(star.cameFrom)) / 2);
      expect(star.position.x, closeTo(centre.x + drawn.dx, 1e-3));
      expect(star.position.y, closeTo(centre.y + drawn.dy, 1e-3));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in play, stars drift at the cruise speed, their streaks very '
      'short, and one past the edge becomes a new one at the farthest', (
    tester,
  ) async {
    final game = await playing(tester);
    final field = game.starField;
    final view = game.view;
    final right = game.camera.visibleWorldRect.right;
    Future<void> frame() => tester.pump(const Duration(milliseconds: 16));
    double distanceFor(double radius, double x) => radius * view.rimScale / x;
    await pumpFrames(tester, 20);
    expect(game.state, TubeState.play);

    final drifting = field.stars[0];
    final eyeDistance = drifting.eyeDistance;
    await frame();
    expect(
      drifting.eyeDistance,
      closeTo(
        eyeDistance - StarFieldComponent.cruise * game.pace * 0.016,
        1e-9,
      ),
    );
    // Later rounds speed it up, at the game's pace.
    game.round = 5;
    final later = drifting.eyeDistance;
    await frame();
    expect(
      drifting.eyeDistance,
      closeTo(later - StarFieldComponent.cruise * game.pace * 0.016, 1e-9),
    );
    expect(game.pace, greaterThan(1.2));
    game.round = 1;

    // Close to the eye, a drifting star's streak is at most as long as the
    // star is wide, and a logical pixel longer.
    const near = Offset(0.3, 0);
    final short = field.stars[1]
      ..point = near
      ..eyeDistance = distanceFor(near.dx, 0.8 * right);
    await frame();
    expect(short.point, near);
    expect(
      short.scale.x,
      closeTo(
        2 * short.scale.y +
            StarComponent.slowLength / game.camera.viewfinder.zoom,
        1e-3,
      ),
    );

    // A star inside the screen's edge goes on. One past the edge becomes a new
    // star at the farthest distance.
    const point = Offset(3, 0);
    final inside = field.stars[2]
      ..point = point
      ..eyeDistance = distanceFor(point.dx, 0.9 * right);
    final past = field.stars[3]
      ..point = point
      ..eyeDistance = distanceFor(point.dx, 2 * right);
    await frame();
    expect(inside.point, point);
    expect(past.point, isNot(point));
    expect(past.eyeDistance, StarFieldComponent.far);
    expect(past.cameFrom, StarFieldComponent.far);
    expect(past.brightness, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in play, stars turn about the axis against the ship, nearer '
      'ones more, easing in, at the same distances', (tester) async {
    final game = await playing(tester);
    final tube = game.view.tube;
    double wrapped(double angle) =>
        angle - 2 * math.pi * (angle / (2 * math.pi)).roundToDouble();
    double shipDirection() => game.player.position.toOffset().direction;
    await pumpFrames(tester, 20);
    expect(game.state, TubeState.play);
    expect(tube.isOpen, isFalse);

    // Two stars that stay on screen, one near the eye and one far from it.
    const nearPoint = Offset(0.5, 0);
    const farPoint = Offset(2, 0);
    final near = game.starField.stars[0]
      ..point = nearPoint
      ..eyeDistance = 1.5;
    final far = game.starField.stars[1]
      ..point = farPoint
      ..eyeDistance = 8;
    double nearTurn() => wrapped(near.point.direction - nearPoint.direction);
    double farTurn() => wrapped(far.point.direction - farPoint.direction);
    final shipFrom = shipDirection();
    game.player.moveBy(1);
    await tester.pump(const Duration(milliseconds: 16));
    final shipTurn = wrapped(shipDirection() - shipFrom);
    // The ship's lane, turned the other way.
    final lane = -shipTurn.sign * 2 * math.pi / tube.laneCount;
    expect(lane, isNot(0));
    double ratioAt(double distance) =>
        StarFieldComponent.turnRatio * StarFieldComponent.bright / distance;
    // The other way from the ship, and only a part of the way at first.
    expect(nearTurn().sign, lane.sign);
    expect(nearTurn().abs(), lessThan(ratioAt(1.5) * lane.abs() / 5));
    // Then nearly all of it, as the bright distance over the star's own, a bit
    // more as it comes closer. The turn leaves its distances from the axis and
    // the eye alone.
    await pumpFrames(tester, 60);
    final drift = StarFieldComponent.cruise * game.pace * 0.016;
    for (final (star, turn, from) in [
      (near, nearTurn(), 1.5),
      (far, farTurn(), 8.0),
    ]) {
      expect(
        turn / lane,
        inInclusiveRange(0.98 * ratioAt(from), ratioAt(star.eyeDistance)),
      );
      expect(star.eyeDistance, closeTo(from - 61 * drift, 1e-6));
    }
    expect(near.point.distance, closeTo(nearPoint.distance, 1e-9));
    expect(far.point.distance, closeTo(farPoint.distance, 1e-9));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("along the Floor's straight, neither the ship nor the stars "
      'turn', (tester) async {
    final (_, turn, shipTurn) = await walkOpenTube(tester, Tubes.floor);
    expect(shipTurn, 0);
    expect(turn, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("across the Ridge's peak, stars turn against the ship's turn "
      'there, nearer ones more', (tester) async {
    final ridge = Tubes.ridge;
    final (star, turn, shipTurn) = await walkOpenTube(tester, ridge);
    expect(
      shipTurn,
      closeTo(ridge.headings.last - ridge.headings.first, 1e-9),
    );
    expect(shipTurn.abs(), greaterThan(0.5));
    double ratioAt(double distance) =>
        StarFieldComponent.turnRatio * StarFieldComponent.bright / distance;
    // As in the closed tube's test: nearly all of it, a bit more as the star
    // comes closer.
    expect(
      -turn / shipTurn,
      inInclusiveRange(0.98 * ratioAt(1.5), ratioAt(star.eyeDistance)),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a star brightens by its opacity each frame, with no tint', (
    tester,
  ) async {
    final game = await playing(tester);
    final star = game.starField.stars.firstWhere(
      (star) => star.brightness > 0.2 && star.brightness < 0.8,
    );
    for (var i = 0; i < 60; i++) {
      final brightness = star.brightness;
      await tester.pump(const Duration(milliseconds: 16));
      expect(star.brightness, greaterThan(brightness));
      expect(star.drawing.opacity, closeTo(star.brightness, 1e-6));
      expect(star.drawing.paint.colorFilter, isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with drifting stars off, stars only show on the drop and the '
      'zoom, and the running game changes at once', (tester) async {
    final game = await playing(tester);
    final field = game.starField;
    expect(field.stars, hasLength(StarFieldComponent.count));
    // In play, they fade out.
    game.driftingStars = false;
    await pumpFrames(tester, 25);
    expect(field.stars, isEmpty);
    expect(field.children, isEmpty);

    game.clearSpawns();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.drop);
    expect(field.stars, hasLength(StarFieldComponent.count));
    await pumpUntil(tester, () => game.state == TubeState.zoom, frames: 200);
    expect(field.stars, hasLength(StarFieldComponent.count));
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 100);
    await pumpFrames(tester, 25);
    expect(field.stars, isEmpty);

    // On again, they fade in.
    game.driftingStars = true;
    expect(field.stars, hasLength(StarFieldComponent.count));
    await pumpFrames(tester, 25);
    expect(field.stars.map((star) => star.brightness), anyElement(1));

    // Once the game is over, nothing fades: the knob turns them off and on
    // again at once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    game
      ..lives = 1
      ..addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));
    await pumpUntil(tester, () => game.state == TubeState.over, frames: 120);
    game.driftingStars = false;
    expect(field.stars, isEmpty);
    game.driftingStars = true;
    await tester.pump(const Duration(milliseconds: 16));
    expect(field.stars.map((star) => star.brightness), anyElement(1));
    await tester.pumpWidget(const SizedBox());
  });

  group('the glow', () {
    /// The glows of what [linesOf] returns, in its order.
    const glows = [
      TubeShooterExample.lineGlow,
      TubeShooterExample.lineGlow,
      TubeShooterExample.tubeGlow,
      TubeShooterExample.tubeGlow,
      TubeShooterExample.tubeGlow,
    ];

    /// Returns [game]'s lines after two frames: the ship, [climber], the tube,
    /// the ship's lane and the spikes.
    Future<List<RasterizerPathComponent>> linesOf(
      WidgetTester tester,
      TubeShooterExample game,
      ClimberComponent climber,
    ) async {
      await pumpFrames(tester, 2);
      final lines = [
        game.player.drawing,
        climber.drawing,
        ...tubePathsOf(game),
      ].cast<RasterizerPathComponent>();
      expect(lines, hasLength(5));
      return lines;
    }

    testWidgets('is on the lines, but not on the texts, the dots and the '
        'stars', (tester) async {
      final game = await pumpGame(tester, SvgRenderer.rasterizer);
      game.glow = true;
      await pumpUntil(tester, () => game.state == TubeState.ready);
      final spawned = game.spawnGroup.descendants();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      game.spawning = false;
      final climber = ClimberComponent(lane: 3, depth: Tube.depth / 2);
      game
        ..addEnemy(climber)
        ..spikes.grow(0, Tube.depth / 2);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        glows,
      );
      final plain = [
        ...spawned,
        ...game.starField.descendants(),
        ...game.camera.viewport.descendants(),
      ].whereType<RasterizerPathComponent>().toList();
      expect(plain, isNotEmpty);
      for (final drawing in plain) {
        expect(drawing.glow, isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is off at first, and goes on and off with its knob, at once '
        'in a still world', (tester) async {
      final game = await playing(tester);
      final climber = ClimberComponent(lane: 3, depth: Tube.depth / 2);
      game
        ..addEnemy(climber)
        ..spikes.grow(0, Tube.depth / 2);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        everyElement(isNull),
      );

      game.glow = true;
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        glows,
      );

      final version = game.view.version;
      game.glow = true;
      expect(game.view.version, version);

      game.glow = false;
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        everyElement(isNull),
      );

      game.speed = 0;
      game.glow = true;
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        glows,
      );

      game.glow = false;
      expect(
        (await linesOf(tester, game, climber)).map((line) => line.glow),
        everyElement(isNull),
      );
      await tester.pumpWidget(const SizedBox());
    });

    for (final glow in [false, true]) {
      testWidgets("is a new explosion's too, as its knob is then: "
          '${glow ? 'on' : 'off'}', (tester) async {
        final game = await playing(tester);
        game.glow = glow;
        game.addEnemy(ClimberComponent(lane: 3, depth: Tube.depth / 2));
        await tester.pump(const Duration(milliseconds: 16));
        game.purge();
        await pumpFrames(tester, 2);
        final bursts = explosionsOf(game)
            .expand((e) => e.children)
            .whereType<RasterizerPathComponent>();
        // Its burst and its 8 flying rays.
        expect(bursts, hasLength(9));
        expect(
          bursts.map((burst) => burst.glow),
          everyElement(glow ? TubeShooterExample.lineGlow : isNull),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets("isn't Flame's, whose paths draw with its knob on or off", (
      tester,
    ) async {
      final game = await pumpGame(tester, SvgRenderer.flameSvg);
      await pumpFrames(tester, 2);
      game.glow = true;
      await pumpFrames(tester, 2);
      expect(tubePathsOf(game), isNotEmpty);
      expect(game.descendants().whereType<RasterizerPathComponent>(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('comes from the story, to a new game and to the running one', (
      tester,
    ) async {
      Widget storyWith({required bool glow}) => MaterialApp(
        home: TubeShooterStory(renderer: SvgRenderer.rasterizer, glow: glow),
      );
      TubeShooterExample gameOf() => tester
          .widget<GameWidget<TubeShooterExample>>(
            find.byWidgetPredicate((w) => w is GameWidget),
          )
          .game!;

      await tester.pumpWidget(storyWith(glow: false));
      final game = gameOf();
      expect(game.glow, isFalse);
      await tester.pumpWidget(storyWith(glow: true));
      expect(gameOf(), same(game));
      expect(game.glow, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a shot destroys a climber in its lane, and scores; the '
      'explosion fades out and removes itself', (tester) async {
    final game = await playing(tester);
    final climber = ClimberComponent(lane: 0, depth: Tube.depth / 2);
    game.addEnemy(climber);
    await tester.pump(const Duration(milliseconds: 16));
    await fireOnce(tester, game);
    await pumpUntil(tester, () => game.enemies.isEmpty, frames: 40);
    expect(game.score, 100);
    expect(game.shots, isEmpty);
    await tester.pump();
    expect(explosionsOf(game), hasLength(1));
    final drawings = explosionsOf(
      game,
    ).single.children.whereType<PathComponent>().toList();
    final [burst, ...rays] = drawings;
    expect(rays, hasLength(8));
    // Its burst fades by its opacity, not by a tint to black, so it hides
    // nothing. Its rays fly out from its middle, each on its own line, tinted
    // to the climber's colour.
    await pumpFrames(tester, 10);
    expect(burst.opacity, inExclusiveRange(0, 1));
    expect(burst.paint.colorFilter, isNull);
    expect(
      rays.map((ray) => ray.paint.colorFilter),
      everyElement(
        const ui.ColorFilter.mode(TubeColors.climber, ui.BlendMode.srcATop),
      ),
    );
    final distances = [for (final ray in rays) ray.position.length];
    for (final (i, ray) in rays.indexed) {
      expect(ray.opacity, 1);
      // Flame keeps angles within half a turn either way, so this compares
      // directions.
      expect(math.cos(ray.angle), closeTo(math.cos(i * math.pi / 4), 1e-6));
      expect(math.sin(ray.angle), closeTo(math.sin(i * math.pi / 4), 1e-6));
      final away = ray.position.normalized();
      expect(away.x, closeTo(math.cos(ray.angle + math.pi / 8), 1e-6));
      expect(away.y, closeTo(math.sin(ray.angle + math.pi / 8), 1e-6));
    }
    // The burst is gone, and the rays fly on, fading out.
    await pumpFrames(tester, 25);
    expect(burst.opacity, 0);
    for (final (i, ray) in rays.indexed) {
      expect(ray.opacity, inExclusiveRange(0, 1));
      expect(ray.position.length, greaterThan(distances[i]));
    }
    await pumpFrames(tester, 35);
    expect(explosionsOf(game), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an explosion near the far end has no flying rays, and lasts '
      'half as long', (tester) async {
    final game = await playing(tester);
    final climber = ClimberComponent(lane: 0, depth: Tube.depth);
    game.addEnemy(climber);
    await tester.pump(const Duration(milliseconds: 16));
    game.destroy(climber);
    await tester.pump();
    final explosion = explosionsOf(game).single;
    expect(explosion.depth, greaterThan(ExplosionComponent.farDepth));
    expect(explosion.children.whereType<PathComponent>(), hasLength(1));
    await pumpFrames(tester, 35);
    expect(explosionsOf(game), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a shot splits a splitter into two climbers, which flip onto '
      'its neighbouring lanes', (tester) async {
    final game = await playing(tester);
    game.player.step = 3 * 16 + 8;
    game.addEnemy(SplitterComponent(lane: 3, depth: Tube.depth / 2));
    await tester.pump(const Duration(milliseconds: 16));
    await fireOnce(tester, game);
    await pumpUntil(
      tester,
      () => game.enemies.whereType<SplitterComponent>().isEmpty,
      frames: 40,
    );
    expect(game.score, 150);
    final climbers = game.enemies.whereType<ClimberComponent>().toList();
    expect(climbers, hasLength(2));
    expect(climbers.every((climber) => climber.isFlipping), isTrue);
    await pumpFrames(tester, 20);
    expect(climbers.map((climber) => climber.lane).toSet(), {2, 4});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a seeder grows its lane's spike, a path made again as it "
      'grows, and a shot shortens it', (tester) async {
    final game = await playing(tester);
    game.player.step = 5 * 16 + 8;
    final seeder = SeederComponent(lane: 5, depth: Tube.depth);
    game.addEnemy(seeder);
    await pumpFrames(tester, 45);
    final length = game.spikes.lengths[5];
    expect(length, greaterThan(0.15));
    expect(game.spikes.tipOf(5), Tube.depth - length);
    // A paint keeps its colour in 32-bit floats, so compare ARGB values.
    PathComponent spikesPath() => tubePathsOf(game).singleWhere(
      (path) => path.paint.color.toARGB32() == TubeColors.spikes.toARGB32(),
    );
    final first = spikesPath();
    await pumpFrames(tester, 2);
    expect(spikesPath(), isNot(same(first)));
    expect(game.spikes.lengths[5], greaterThan(length));

    game.discard(seeder);
    final grown = game.spikes.lengths[5];
    await fireOnce(tester, game);
    await pumpUntil(tester, () => game.spikes.lengths[5] < grown, frames: 40);
    expect(
      game.spikes.lengths[5],
      closeTo(grown - TubeShooterExample.spikeHit, 1e-9),
    );
    expect(game.score, TubeShooterExample.spikeScore);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a zapper flashes white, then its pulse draws a bolt down its '
      'lane, a new path each frame, and destroys the ship there', (
    tester,
  ) async {
    final game = await playing(tester);
    final zapper = ZapperComponent(lane: 3, depth: Tube.depth / 2);
    game.addEnemy(zapper);
    // A paint keeps its colour in 32-bit floats, so compare ARGB values.
    PathComponent? boltsPath() => tubePathsOf(game)
        .where(
          (path) => path.paint.color.toARGB32() == TubeColors.bolts.toARGB32(),
        )
        .firstOrNull;
    await pumpUntil(tester, () => game.isWarning, frames: 180);
    expect(zapper.drawing.paint.colorFilter, isNotNull);
    expect(boltsPath(), isNull);
    await pumpUntil(tester, () => game.isPulsing, frames: 40);
    // The bolts' path mounts the frame after it's added.
    await tester.pump(const Duration(milliseconds: 16));
    final first = boltsPath();
    expect(first, isNotNull);
    expect(zapper.drawing.paint.colorFilter, isNull);
    await tester.pump(const Duration(milliseconds: 16));
    expect(boltsPath(), isNot(same(first)));
    expect(game.state, TubeState.play);
    game.player.step = 3 * 16 + 8;
    await pumpFrames(tester, 2);
    expect(game.state, TubeState.dying);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a zapper that arrives in the ship's lane during a pulse waits "
      'for the next pulse, which it flashes white for', (tester) async {
    final game = await playing(tester);
    await pumpUntil(tester, () => game.isPulsing, frames: 240);
    final zapper = ZapperComponent(lane: game.player.lane, depth: Tube.depth);
    game.addEnemy(zapper);
    await pumpFrames(tester, 3);
    expect(game.isPulsing, isTrue);
    expect(zapper.isZapping, isFalse);
    expect(game.state, TubeState.play);
    await pumpUntil(tester, () => game.isWarning, frames: 180);
    expect(zapper.drawing.paint.colorFilter, isNotNull);
    await pumpUntil(tester, () => game.state == TubeState.dying, frames: 40);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an edge-walker on an edge lets shots pass; one crossing a lane '
      'is destroyed by a shot, and one at the rim destroys the ship', (
    tester,
  ) async {
    final game = await playing(tester);
    final walker = EdgeWalkerComponent(lane: 0, depth: Tube.depth / 4);
    game.addEnemy(walker);
    // It walks from its lane's middle to one of the lane's edges. Its lane is
    // the ship's.
    await tester.pump(const Duration(milliseconds: 16));
    await pumpUntil(tester, () => !walker.isCrossing, frames: 30);
    expect(walker.edge, anyOf(0, 1));
    await fireOnce(tester, game);
    await pumpUntil(tester, () => game.shots.isEmpty, frames: 60);
    expect(game.enemies, contains(walker));
    walker.cross(walker.edge == 0 ? 1 : 0);
    await fireOnce(tester, game);
    await pumpUntil(tester, () => game.enemies.isEmpty, frames: 30);
    expect(game.score, EnemyKind.edgeWalker.score);

    game.addEnemy(EdgeWalkerComponent(lane: game.player.lane, depth: 0));
    await pumpFrames(tester, 2);
    expect(game.state, TubeState.dying);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a climber at the rim in the ship's lane costs a life; the "
      'enemies go back to the queue, and the ship comes back', (tester) async {
    final game = await playing(tester);
    final queued = game.spawns.length;
    game.addEnemy(ClimberComponent(lane: 9, depth: Tube.depth));
    game.addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));
    await pumpFrames(tester, 2);
    expect(game.state, TubeState.dying);
    expect(game.lives, TubeShooterExample.startLives - 1);
    expect(game.enemies, isEmpty);
    expect(game.spawns, hasLength(queued + 2));
    // They wait at the far end of their lanes, the next to come.
    expect(game.spawns.skip(queued).map((spawn) => spawn.lane).toSet(), {
      9,
      game.player.lane,
    });
    expect(explosionsOf(game), hasLength(1));
    // The ship fades by its opacity, then comes back whole.
    await pumpFrames(tester, 30);
    expect(game.player.drawing.opacity, inExclusiveRange(0, 1));
    expect(game.player.drawing.paint.colorFilter, isNull);
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 100);
    expect(game.player.drawing.opacity, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a level waits on READY, the tube at rest and nothing coming, '
      'until a key but a modifier, which only begins it', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    await pumpUntil(tester, () => game.state == TubeState.ready);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.readyText.isMounted, isTrue);
    expect(game.player.isVisible, isTrue);
    await pumpFrames(tester, 125);
    expect(game.state, TubeState.ready);
    expect(game.enemies, isEmpty);
    expect(game.spawns.where((spawn) => spawn.isArriving), isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.ready);

    // The space bar begins the level, but held, it doesn't fire.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(game.state, TubeState.play);
    await pumpFrames(tester, 20);
    expect(game.shots, isEmpty);
    expect(game.readyText.isMounted, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Enter at READY begins the level, and keeps the purge', (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    game.spawning = false;
    await pumpUntil(tester, () => game.state == TubeState.ready);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.play);
    expect(game.purgeReady, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap at READY begins the level once it is up, without a shot '
      'or counting towards a double tap', (tester) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    game.spawning = false;
    await pumpUntil(tester, () => game.state == TubeState.ready);
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    final tap = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.ready);
    await tap.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.play);
    await pumpFrames(tester, 5);
    expect(game.shots, isEmpty);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.purgeReady, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after a lost ship the level waits on READY again, and what '
      'was held since before does not begin it', (tester) async {
    final game = await playing(tester);
    game.addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));
    await pumpFrames(tester, 2);
    expect(game.state, TubeState.dying);
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    final finger = await tester.startGesture(center);
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 120);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.readyText.isMounted, isTrue);
    expect(game.player.drawing.opacity, 1);
    final step = game.player.step;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await finger.up();
    await pumpFrames(tester, 10);
    expect(game.state, TubeState.ready);
    expect(game.player.step, step);
    expect(game.shots, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    expect(game.state, TubeState.play);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('taps mashed around READY never purge', (tester) async {
    final game = await playing(tester);
    game.addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));
    await pumpFrames(tester, 2);
    expect(game.state, TubeState.dying);
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    // A tap that went down before READY and up during it doesn't begin the
    // level.
    await pumpFrames(tester, 90);
    expect(game.state, TubeState.dying);
    final early = await tester.startGesture(center);
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 10);
    await early.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.ready);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.play);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.purgeReady, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a round ends with the drop down the ship lane, then the next '
      'round, 5% faster, zooms in', (tester) async {
    final game = await playing(tester);
    // A game that starts at a later level goes as fast as if it had started
    // at the first.
    expect(game.pace, closeTo(math.pow(1.05, octagonLevel), 1e-9));
    final pace = game.pace;
    game.spikes.grow(7, 1);
    game.clearSpawns();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.drop);
    await pumpFrames(tester, 62);
    // The ship drops down its lane with the eye, a quarter of the way in
    // about a second.
    expect(game.player.depth, closeTo(Tube.depth / 4, 0.1));
    expect(game.view.eyeShift, game.player.depth);
    await pumpUntil(tester, () => game.state == TubeState.zoom, frames: 80);
    expect(game.round, 2);
    expect(game.pace, closeTo(pace * 1.05, 1e-9));
    expect(game.spawns, hasLength(18));
    expect(game.spikes.lengths.every((length) => length == 0), isTrue);
    expect(game.lives, TubeShooterExample.startLives);
    await pumpUntil(tester, () => game.state == TubeState.ready, frames: 80);
    expect(game.player.depth, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a spike taller than the dropping ship destroys it', (
    tester,
  ) async {
    final game = await playing(tester);
    game.spikes.grow(game.player.lane, Tube.depth * 0.9);
    game.clearSpawns();
    await pumpUntil(tester, () => game.state == TubeState.dying);
    expect(game.player.depth, greaterThanOrEqualTo(Tube.depth * 0.1));
    expect(game.lives, TubeShooterExample.startLives - 1);
    // Then the next round.
    await pumpUntil(tester, () => game.state == TubeState.zoom, frames: 100);
    expect(game.round, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the purge, by Enter or a double tap, destroys every enemy, '
      'once a round', (tester) async {
    final game = await playing(tester);
    for (final lane in [4, 8, 12]) {
      game.addEnemy(ClimberComponent(lane: lane, depth: Tube.depth / 2));
    }
    game.addEnemy(SplitterComponent(lane: 10, depth: Tube.depth / 2));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(game.enemies, isEmpty);
    expect(game.score, 3 * 100 + 150);
    expect(game.purgeReady, isFalse);
    final climber = ClimberComponent(lane: 6, depth: Tube.depth / 2);
    game.addEnemy(climber);
    game.purge();
    expect(game.enemies, {climber});

    // The next round's purge, by a double tap.
    game.discard(climber);
    game.clearSpawns();
    await pumpUntil(tester, () => game.state == TubeState.zoom, frames: 200);
    await beginLevel(tester, game, frames: 100);
    expect(game.purgeReady, isTrue);
    game.addEnemy(ClimberComponent(lane: 6, depth: Tube.depth / 2));
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.purgeReady, isTrue);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.purgeReady, isFalse);
    expect(game.enemies, isEmpty);

    // PURGE shows for a second.
    Iterable<String> banners() => game.camera.viewport.children
        .whereType<VectorTextComponent>()
        .where((text) => text.capHeight == TubeShooterExample.bannerCap)
        .map((text) => text.text);
    await tester.pump(const Duration(milliseconds: 16));
    expect(banners(), contains('PURGE'));
    await pumpFrames(tester, 70);
    expect(banners(), isNot(contains('PURGE')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in a still world, a resize or a zoom fits the tube, and '
      'what is on it, again', (tester) async {
    final game = await playing(tester);
    final climber = ClimberComponent(lane: 3, depth: Tube.depth / 2);
    game.addEnemy(climber);
    await tester.pump(const Duration(milliseconds: 16));
    game.speed = 0;
    await tester.pump(const Duration(milliseconds: 16));

    /// Returns the climber's place, the tube's path and the view's rim scale.
    (Vector2, PathComponent, double) fit() =>
        (climber.position.clone(), tubePathsOf(game).first, game.view.rimScale);

    /// Expects the climber at its lane's middle and its depth, in the view as
    /// it is now.
    void expectPlaced() {
      final view = game.view;
      final tube = view.tube;
      final middle = tube.middles[3] * view.scaleAt(climber.depth);
      // A Vector2 keeps 32-bit floats.
      expect(climber.position.x, closeTo(middle.dx, 1e-3));
      expect(climber.position.y, closeTo(middle.dy, 1e-3));
    }

    var (position, path, rimScale) = fit();
    tester.view.physicalSize = tester.view.physicalSize * 1.5;
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.view.rimScale, isNot(rimScale));
    expect(climber.position, isNot(position));
    expect(tubePathsOf(game).first, isNot(same(path)));
    expectPlaced();

    (position, path, rimScale) = fit();
    await tester.pumpWidget(
      story(
        SvgRenderer.rasterizer,
        zoom: 2,
        speed: 0,
        firstLevel: octagonLevel,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.world.timeScale, 0);
    expect(tubePathsOf(game).first, isNot(same(path)));
    expectPlaced();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the game is over after the last life, still, until a tap '
      'starts a new one at the round reached', (tester) async {
    final game = await playing(tester, firstLevel: 0);
    final reported = <int>[];
    game.onLevel = reported.add;
    game.clearSpawns();
    await pumpUntil(tester, () => game.round == 2);
    expect(game.levelIndex, 1);
    expect(reported, [1]);
    await beginLevel(tester, game);
    game.lives = 1;
    game.score = 500;
    game.addEnemy(ClimberComponent(lane: game.player.lane, depth: 0));
    await pumpUntil(tester, () => game.state == TubeState.over, frames: 120);
    expect(game.world.timeScale, 0);
    await tester.pump();
    expect(game.gameOverText.isMounted, isTrue);
    // The stars stay, standing still.
    final star = game.starField.stars.first;
    final eyeDistance = star.eyeDistance;
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.starField.stars, hasLength(StarFieldComponent.count));
    expect(star.eyeDistance, eyeDistance);
    final center = tester.getCenter(
      find.byType(GameWidget<TubeShooterExample>),
    );
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.state, TubeState.zoom);
    expect(game.lives, TubeShooterExample.startLives);
    expect(game.score, 0);
    expect(game.round, 2);
    expect(game.levelIndex, 1);
    expect(game.pace, closeTo(1.05, 1e-9));
    expect(reported, [1, 1]);
    expect(game.world.timeScale, 1);
    expect(game.gameOverText.isMounted, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the round's number shows on the zoom; a changed score keeps "
      "the glyphs that stay, and the others share their glyphs' scenes", (
    tester,
  ) async {
    final game = await pumpGame(tester, SvgRenderer.rasterizer);
    game.spawning = false;
    Iterable<VectorTextComponent> texts(double capHeight) => game
        .camera
        .viewport
        .children
        .whereType<VectorTextComponent>()
        .where((text) => text.capHeight == capHeight);
    expect(texts(TubeShooterExample.bannerCap).single.text, 'ROUND 1');
    // The level's name and the round show at the bottom left, the round
    // below, opposite the lives and the score.
    VectorTextComponent hud(String text) => texts(
      TubeShooterExample.hudCap,
    ).singleWhere((component) => component.text == text);
    final levelText = hud('OCTAGON');
    final roundText = hud('ROUND 1');
    expect(levelText.anchor, Anchor.bottomLeft);
    expect(levelText.position.x, StoryGame.hudMargin);
    expect(roundText.position.x, StoryGame.hudMargin);
    expect(roundText.position.y, game.size.y - StoryGame.hudMargin);
    expect(levelText.position.y, lessThan(roundText.position.y));
    expect(hud('LIVES 3').position.y, levelText.position.y);
    expect(hud('SCORE 0').position.y, roundText.position.y);
    // Under it, as each round recharges the purge.
    expect(
      texts(TubeShooterExample.hudCap).map((text) => text.text),
      contains('PURGE READY'),
    );
    await pumpUntil(tester, () => game.state == TubeState.ready);
    await tester.pump(const Duration(milliseconds: 16));
    expect(texts(TubeShooterExample.bannerCap).single.text, 'READY');
    expect(
      texts(TubeShooterExample.hudCap).map((text) => text.text),
      isNot(contains('PURGE READY')),
    );
    await beginLevel(tester, game);
    await tester.pump(const Duration(milliseconds: 16));
    expect(texts(TubeShooterExample.bannerCap), isEmpty);

    final score = texts(TubeShooterExample.hudCap)
        .singleWhere((text) => text.text.startsWith('SCORE'));
    List<RasterizerPathComponent> glyphs() =>
        score.children.whereType<RasterizerPathComponent>().toList();
    game.score = 11;
    // The text changes in an update, and its glyphs mount and draw the next
    // frame.
    await pumpFrames(tester, 2);
    expect(score.text, 'SCORE 11');
    final first = glyphs();
    expect(first, hasLength(7));
    final s = first[0].debugScene;
    final one = first[5].debugScene;
    expect(s, isNotNull);
    expect(one, isNotNull);
    expect(first[6].debugScene, same(one));
    game.score = 111;
    await pumpFrames(tester, 2);
    final again = glyphs();
    expect(again, hasLength(8));
    for (var i = 0; i < 7; i++) {
      expect(again[i], same(first[i]));
    }
    expect(again[0].debugScene, same(s));
    expect(again[7].debugScene, same(one));

    game.score = 5;
    await pumpFrames(tester, 2);
    expect(score.text, 'SCORE 5');
    final shorter = glyphs();
    expect(shorter, hasLength(6));
    for (var i = 0; i < 5; i++) {
      expect(shorter[i], same(first[i]));
    }
    expect(shorter[5], isNot(same(first[5])));
    await tester.pumpWidget(const SizedBox());
  });

  group('the canvas fallback', () {
    // Pumps 60 frames a second, for the seconds given or until done.
    Future<void> Function(double, {bool Function()? done}) pumpWith(
      WidgetTester tester,
    ) => (seconds, {done}) async {
      final frames = (seconds * 60).round();
      for (var i = 0; i < frames && !(done?.call() ?? false); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    };

    for (final (index, level) in levels.indexed) {
      testWidgets('no path of a whole game from the ${level.tube.name} falls '
          'back, in any state, on any frame', (tester) async {
        final game = await pumpGame(
          tester,
          SvgRenderer.rasterizer,
          firstLevel: index,
        ) as RasterizerTubeShooterExample;
        // Headless, with no GPU, the canvas renderer draws. Since
        // RasterizerScene.canDraw decides alike for every renderer, a path
        // that would fall back on a GPU falls back here too.
        final watch = FallbackWatch(game, RasterizerBackend.canvas);
        await playWholeGame(
          tester,
          game,
          tester.getCenter(find.byType(GameWidget<TubeShooterExample>)),
          pumpWith(tester),
        );
        watch.stop();
        expect(watch.problems, isEmpty);
        expect(watch.states, TubeState.values.toSet());
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('the watch sees another renderer, and a path drawn with '
        'Canvas.drawPath', (tester) async {
      final game = await pumpGame(
        tester,
        SvgRenderer.rasterizer,
      ) as RasterizerTubeShooterExample;
      final watch = FallbackWatch(game, RasterizerBackend.mesh);
      await pumpFrames(tester, 2);
      expect(watch.problems, contains('zoom: the canvas renderer'));
      watch.stop();

      final hairline = FallbackWatch(game, RasterizerBackend.canvas);
      await pumpFrames(tester, 2);
      expect(hairline.problems, isEmpty);
      game.tubeGroup.add(
        RasterizerPathComponent(
          path: ui.Path()..addRect(const Rect.fromLTWH(0, 0, 9, 9)),
          paint: Paint()..style = PaintingStyle.stroke,
        ),
      );
      await pumpFrames(tester, 2);
      expect(
        hairline.problems,
        contains('zoom: Canvas.drawPath under Component'),
      );
      hairline.stop();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
