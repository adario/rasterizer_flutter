import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

/// A prototype of an endless runner, where running is flying: see
/// [description].
///
/// It borrows Tube Shooter's tube, ship, stars and view. Its [runner] flies
/// the ship, and plays by the rules: it hands the mode the player's input.
/// Subclasses pick the component that draws a path: see [pathComponent].
abstract class TubeRunnerExample({
  required super.status,
  super.random,
  Tube? tube,
}) extends TubeHost {
  this {
    view.tube = tube ?? Tubes.hexagon;
  }

  /// The run, and the rules it plays by.
  final runner = RunnerMode();

  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG, down [tube], one of [tubes], or the hexagon.
  factory TubeRunnerExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    Tube? tube,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeRunnerExample(status: status, random: random, tube: tube)
      : RasterizerTubeRunnerExample(
          status: status,
          renderer: renderer,
          random: random,
          tube: tube,
        );

  /// The tubes it can fly down: Tube Shooter's, in the order of its levels.
  static final tubes = [for (final level in levels) level.tube];

  static const description = '''
    A prototype of an endless runner in vector lines, where running is flying.
    The ship flies down an endless tube that bends as it goes, and that the
    game makes as the ship gets there. RasterizerPolygonsComponent draws the
    tube's quads, and RasterizerPathComponent the other paths, with the
    renderer that the Renderer knob picks; with Flame SVG, Flame's
    PathComponent draws them all.

    Move the ship round the tube with the arrow keys, A and D, by dragging
    left and right, or a lane per scroll of the mouse wheel. Fire down its
    lane with the space bar, or while dragging, as in Tube Shooter. The Tube
    knob picks one of Tube Shooter's tubes, which the ship goes on down
    without a stop. Round an open tube, the ship stops at its ends, as in
    Tube Shooter, and where the tube bends, its nearer lanes hide what's
    beyond them, as a closed tube's walls do. The ship's lane shows in the
    ship's colour, as in Tube Shooter.

    READY shows until a tap or a key starts the game. After 4 seconds, and
    every 4 seconds from then on, an enemy comes at the farthest ring across
    the tube, on a lane picked at random: a seeder at first, after 30 seconds
    in the tube, a seeder or a climber, after 60, a zapper too, and after 90,
    a splitter too, of a kind picked at random. For a second and a half, its
    lane flashes in the enemy's colour, added to the ship's in the ship's
    lane, and glows with the enemy and a seeder's spike, fading out: the mesh
    renderer draws the glow with RasterizerGlow, only on them, and with the
    other renderers, wider, see-through copies of them stand for it. Enemies
    climb their lanes toward the ship, and go once they pass it. A seeder lays
    a spike behind it, which goes once all of it passes the ship. A climber
    flips onto a neighbouring lane every 2 to 4 seconds, and fires down its
    lane every 3 to 5 seconds, with at most 2 of its kind's shots in the tube,
    as on Tube Shooter's first level; its shots climb half as fast again as
    it does. A zapper flips every 3 to 6 seconds, and the zappers pulse
    together every 3 seconds, for 0.6 of a second, as on Tube Shooter's first
    level: each flashes white for half a second before, and while they
    pulse, a bolt zigzags from each down its lane to the ship's ring,
    glowing, or with wider, see-through copies, as the flash does. A
    splitter neither flips nor fires; 4 units ahead of the ship, as Tube
    Shooter's at the rim, it splits into two climbers, which flip onto the
    lanes on either side.

    The ship's shots fly as fast as Tube Shooter's ahead of it, and go 8
    units down the tube. As in Tube Shooter, a shot destroys a seeder for 50
    points, and leaves its spike, cuts a spike back from its near end for 2
    points, destroys a climber for 100 or a zapper for 200, splits a
    splitter for 150, and destroys a climber's shot. An enemy, a spike or a climber's shot that touches the
    ship, in its lane at the ship's ring, or a bolt down the ship's lane,
    destroys it, and takes a life, as in Tube Shooter: the
    enemies, spikes and shots go, and READY shows again. Once the lives are
    gone, Game Over stops the game until a tap, or Enter, starts a new one.
    The bottom left shows the tube's name and how long the game has gone on
    in it, and the bottom right the lives left and the score. The game plays
    Tube Shooter's sounds as the same things happen, and the Sound knob turns
    them on and off.

    The game makes the tube's quads again every frame. The mesh renderer fills
    each quad on its own, as a fan of triangles, rather than their union. The
    bar under the game shows the renderer, the frame times, the renderer's own
    numbers, the tube's quads and the paths made each second.
  ''';

  /// The tube it flies down, one of [tubes].
  Tube get tube => view.tube;

  /// Changes the tube where the ship is, without a stop: see
  /// [RunnerMode.switchTube].
  set tube(Tube value) {
    final from = view.tube;
    if (value == from) {
      return;
    }
    view.tube = value;
    if (runner.isLoaded) {
      runner.switchTube(from);
    }
  }

  @override
  Future<void> onLoad() async {
    // Fits the view before the ship loads: it sizes its import for the view.
    await super.onLoad();
    world.add(runner);
    startStatus();
  }

  @override
  Iterable<String> get exampleStats => [
    '${runner.quads} quads',
    '$pathsPerSecond paths/s',
  ];

  @override
  bool get canMove => runner.canMove;

  @override
  bool get isWaiting => runner.isWaiting;

  @override
  bool get isReady => runner.isReady;

  @override
  bool get isOver => runner.isOver;

  @override
  void endWait() => runner.endWait();

  @override
  void moveShipBy(double lanes) => runner.moveShipBy(lanes);

  @override
  void advance(double dt) => runner.advance(dt);

  @override
  void afterUpdate(double dt) => runner.afterUpdate(dt);
}

/// The example with flame_rasterizer: [RasterizerPathComponent]s draw its
/// paths, with the renderer that the Renderer knob picks.
class RasterizerTubeRunnerExample({
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.tube,
}) extends TubeRunnerExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerPathComponents<ExampleWorld>,
        RasterizerTubeHost {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeRunnerExample({
  required super.status,
  super.random,
  super.tube,
}) extends TubeRunnerExample
    with FlamePathComponents<ExampleWorld>, FlameTubeHost;
