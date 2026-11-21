import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flutter/foundation.dart';

part 'revolute_joint_svgs_snapshot.dart';

/// The values of the example's knobs, except Zoom, Speed and the cache knobs.
typedef RevoluteJointSvgsSettings = ({SvgRenderer renderer, bool pieces});

/// Flame's Forge2D revolute joint example, as flame_path_shapes extends it,
/// with SVGs: see [description].
///
/// Walls along the game's edges, at a zoom of 1, hold a wheel that a motor
/// turns, under a funnel of two ramps. Each tap drops [dropped] bodies: half
/// balls, and half SVGs from 3 to 3.5 meters at their larger side. The SVG
/// bodies draw above the others, so that flame_rasterizer draws them all in
/// one run of a [RasterizerCanvas]. Their convex pieces draw over them, in
/// the same run, while [pieces] is true.
///
/// The status adds the bodies dropped to [StoryGame]'s. As in
/// flame_path_shapes, the number of bodies at the top right counts the
/// walls, the ramps and the wheel too.
///
/// Given the snapshot of a game with another renderer, it goes on from there,
/// with the same bodies: see [RevoluteJointSvgsSnapshots].
abstract class RevoluteJointSvgsExample({
  @override required var bool pieces,
  required super.status,
  math.Random? random,
  RevoluteJointSvgsSnapshot? from,
}) extends Forge2DExampleGame
    with ExampleSvgs, SvgBodies, PathComponents<Forge2DExampleWorld> {
  this : super(world: RevoluteJointSvgsWorld());

  /// Creates the game for [settings]' renderer, with flame_svg's [cache] for
  /// Flame SVG, which goes on from [from], if any.
  factory RevoluteJointSvgsExample.of(
    RevoluteJointSvgsSettings settings,
    ValueNotifier<String> status, {
    SvgCache cache = defaultSvgCache,
    math.Random? random,
    RevoluteJointSvgsSnapshot? from,
  }) => settings.renderer == SvgRenderer.flameSvg
      ? FlameSvgRevoluteJointExample(
          pieces: settings.pieces,
          status: status,
          cache: cache,
          random: random,
          from: from,
        )
      : RasterizerRevoluteJointExample(
          pieces: settings.pieces,
          status: status,
          renderer: settings.renderer,
          random: random,
          from: from,
        );

  static const description = '''
    Flame's Forge2D revolute joint example, as flame_path_shapes extends it,
    with SVGs: a motor turns a wheel of five circles under a funnel. Each tap
    drops 15 bodies, half balls and half SVGs, which fall through the funnel
    into the wheel.

    The SVG bodies collide as the convex pieces of their outlines, which
    flame_rasterizer's SvgOutline gives, whatever draws the SVGs. They draw
    above the other bodies, so that flame_rasterizer draws them all together,
    in one run.

    The knobs pick the renderer, draw the convex pieces over the SVGs, zoom
    the camera and change the physics' speed. With Flame SVG, the cache knobs
    set flame_svg's cache. Only a new renderer or cache makes a new game. A
    new renderer's game goes on with the same bodies, from where they were.
    The frame rate is at the top left, and the number of bodies at the top
    right. The bar under the game shows the renderer, the frame times, the
    renderer's own numbers and the bodies dropped.

    Based on flame_path_shapes' RevoluteJointWithMotorExample.
  ''';

  /// How many bodies each tap drops.
  static const dropped = 15;

  /// The speed at which new bodies move away from the tap, in meters a
  /// second.
  static const _spreadSpeed = 2.0;

  /// The wheel's depth below the funnel's center, in meters, as in
  /// flame_path_shapes.
  static const _maxWheelDepth = 25.0;

  /// The room that the wheel leaves for the largest SVG, in meters.
  static const _wheelClearance = SvgBodies.maxSide;

  /// The wheel's least depth, in meters, which leaves [_wheelClearance]
  /// between it and the ramps' tips, 6 meters from the funnel's center.
  static const _minWheelDepth = 9.0;

  @override
  final math.Random random = random ?? math.Random();

  /// The snapshot that it goes on from, if any.
  final RevoluteJointSvgsSnapshot? _from = from;

  /// The wheel, from [onLoad] on.
  CircleShuffler? _wheel;

  /// The last time we dropped bodies.
  late DateTime _lastDrop = DateTime.now();

  /// The walls along the game's edges, at a zoom of 1.
  var _walls = <Wall>[];

  /// The world's rectangle that the game shows at a zoom of 1.
  Rect get _arena => Rect.fromCenter(
    center: Offset.zero,
    width: size.x / metersToPixels,
    height: size.y / metersToPixels,
  );

  /// The wheel's center: [_maxWheelDepth] below the funnel's center, or
  /// higher in a short game, to leave [_wheelClearance] above the bottom
  /// wall. In a game shorter still, it stays at [_minWheelDepth], over the
  /// bottom wall.
  Vector2 get _wheelPosition {
    final depth =
        _arena.bottom - Wall.width - CircleShuffler.reach - _wheelClearance;
    return Vector2(0, depth.clamp(_minWheelDepth, _maxWheelDepth));
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!await loadBodySvgs()) {
      return;
    }
    final center = Vector2.zero();
    world.addAll([
      ...(_walls = Wall.around(_arena)),
      _wheel = CircleShuffler(_wheelPosition, from: _from?.wheel),
      CornerRamp(center, isMirrored: true),
      CornerRamp(center),
    ]);
    _restoreBodies();
    startStatus();
  }

  /// Drops [dropped] bodies around [tap], a point in the world. They're
  /// spread out so that they don't overlap, and move away from [tap].
  void drop(Vector2 tap) {
    if (!isLoaded) {
      return;
    }
    // Half balls and half SVGs, alternating.
    final ballsFirst = random.nextBool();
    final bodies = <NewBody>[
      for (var i = 0; i < dropped; i++)
        if (i.isEven == ballsFirst) randomBall() else randomSvg(),
    ];
    final positions = spreadAround(
      tap,
      [for (final (:radius, create: _) in bodies) radius],
      bounds: _arena.deflate(Wall.width),
      world: world.physicsWorld,
      random: random,
    );
    for (final (i, (radius: _, :create)) in bodies.indexed) {
      final position = positions[i];
      addBody(create(position, awayFrom(tap, position, _spreadSpeed, random)));
    }

    // Reverse the wheel if enough time has elapsed since the last drop.
    const delay = 250;
    final now = DateTime.now();
    if (now.difference(_lastDrop).inMilliseconds > delay) {
      _wheel?.reverse();
    }
    _lastDrop = now;
  }

  /// Moves the walls to the game's new edges, and removes the bodies they
  /// leave outside, which would fall forever.
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded) {
      return;
    }
    final arena = _arena;
    world.removeAll(_walls);
    world.addAll(_walls = Wall.around(arena));
    bool outside(BodyComponent body) =>
        body.isLoaded && !arena.contains(body.body.position.toOffset());
    removeBodies([...svgBodies.where(outside), ...balls.where(outside)]);
  }
}

/// The example's world, which drops bodies where it's tapped. Its HUD shows
/// the number of bodies, the fixed ones included.
class RevoluteJointSvgsWorld()
    extends Forge2DExampleWorld
    with TapCallbacks, HasGameRef<RevoluteJointSvgsExample>, BodiesHud {
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    gameRef.drop(event.localPosition);
  }
}

/// The example with flame_rasterizer: [RasterizerSvgComponent]s draw its
/// SVGs, with the renderer that the Renderer knob picks.
class RasterizerRevoluteJointExample({
  required super.pieces,
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.from,
}) extends RevoluteJointSvgsExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerSvgs,
        RasterizerPathComponents {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with flame_svg: its `SvgComponent`s draw its SVGs as images,
/// cached as [cache] sets.
class FlameSvgRevoluteJointExample({
  required super.pieces,
  required super.status,
  final SvgCache cache = defaultSvgCache,
  super.random,
  super.from,
}) extends RevoluteJointSvgsExample with FlameSvgs, FlamePathComponents {
  @override
  SvgCacheMode get cacheMode => cache.mode;

  @override
  SvgCacheSize get cacheSize => cache.size;
}
