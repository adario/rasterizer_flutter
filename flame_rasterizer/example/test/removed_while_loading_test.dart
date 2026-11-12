import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as forge2d;
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/collision_detection/multiple_shapes_example.dart';
import 'package:flame_rasterizer_example/stories/forge2d/revolute_joint_svgs_example.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';
import 'package:flame_rasterizer_example/stories/svg/collidable_svgs_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'slow_bundle.dart';

void main() {
  setUpAll(forge2d.initializeForge2D);

  // Each game, with how many components its world has before its SVGs load:
  // Collidable Svgs adds its arena first.
  final games = <String, (FlameGame Function(ValueNotifier<String>), int)>{
    'Revolute Joint Svgs': (
      (status) => RevoluteJointSvgsExample.of(
        (renderer: SvgRenderer.rasterizer, pieces: false),
        status,
        random: math.Random(1),
      ),
      0,
    ),
    'Svg Shooter': (
      (status) => SvgShooterExample.of(
        SvgRenderer.rasterizer,
        status,
        random: math.Random(1),
      ),
      0,
    ),
    'Collidable Svgs': (
      (status) => CollidableSvgsExample.of(
        (renderer: SvgRenderer.rasterizer, count: 10),
        status,
        random: math.Random(1),
      ),
      1,
    ),
    'Multiple Shapes': (
      (status) => MultipleShapesExample.of(
        (renderer: SvgRenderer.rasterizer, shapes: Shapes.svgs, count: 10),
        status,
        random: math.Random(1),
      ),
      0,
    ),
  };
  for (final MapEntry(key: name, value: (create, before)) in games.entries) {
    // A knob can make a new game, or the user can pick another story, while
    // a game's SVGs load. The removed game's onLoad then goes on. It mustn't
    // start its status, which would keep the game alive, nor fill its world.
    testWidgets('$name, removed while it loads, stops loading', (tester) async {
      Flame.bundle = SlowBundle();
      addTearDown(() => Flame.bundle = rootBundle);
      final status = ValueNotifier('');
      final game = create(status);
      await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
      var loaded = false;
      unawaited(Future.value(game.toBeLoaded()).then((_) => loaded = true));
      await tester.pump();
      expect(loaded, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(game.isRemoved, isTrue);
      // The rest of its SVGs load, and its onLoad ends.
      for (var i = 0; i < 100 && !loaded; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(loaded, isTrue);
      expect(
        game.camera.viewport.children.whereType<FpsTextComponent>(),
        isEmpty,
      );
      expect(status.value, isEmpty);
      expect(game.world.children, hasLength(before));
    });
  }
}
