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

/// What the game resumes from when it switches to another renderer: its
/// runner's snapshot, the score and the lives.
typedef TubeRunnerSnapshot = ({RunnerSnapshot runner, int score, int lives});

/// A prototype of an endless runner, where running is flying: see
/// [description].
///
/// It borrows Tube Shooter's tube, ship, stars and view. Its [runner] flies
/// the ship and plays by the rules, and the game hands that mode the
/// player's input. Subclasses pick the component that draws a path: see
/// [pathComponent].
///
/// Given the snapshot of a game with another renderer, it resumes from
/// there: see [snapshot].
abstract class TubeRunnerExample({
  required super.status,
  super.random,
  Tube? tube,
  TubeRunnerSnapshot? from,
}) extends TubeHost {
  this {
    view.tube = tube ?? Tubes.hexagon;
    if (from != null) {
      score = from.score;
      lives = from.lives;
    }
  }

  /// The run, and the rules it plays by.
  final runner = RunnerMode(from: from?.runner);

  /// What a game with another renderer resumes from.
  TubeRunnerSnapshot get snapshot =>
      (runner: runner.snapshot, score: score, lives: lives);

  /// Creates the game for [renderer], using Flame's `PathComponent` for
  /// Flame SVG.
  ///
  /// The ship flies down [tube], one of [tubes], or else the hexagon. Given
  /// [from], the game resumes from that snapshot.
  factory TubeRunnerExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    Tube? tube,
    TubeRunnerSnapshot? from,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeRunnerExample(
          status: status,
          random: random,
          tube: tube,
          from: from,
        )
      : RasterizerTubeRunnerExample(
          status: status,
          renderer: renderer,
          random: random,
          tube: tube,
          from: from,
        );

  /// The tubes the ship can fly down: Tube Shooter's, in the order of its
  /// levels.
  static final tubes = [for (final level in levels) level.tube];

  static const description = '''
    A prototype of an endless runner in vector lines, where running is flying.
    The ship flies down an endless tube that bends as it goes, and that the
    game builds as the ship gets there. RasterizerPolygonsComponent draws the
    tube's quads, and RasterizerPathComponent the other paths, with the
    renderer that the Renderer knob picks; with Flame SVG, Flame's
    PathComponent draws them all.

    Move the ship round the tube with the arrow keys, A and D, by dragging
    left and right, or by a lane per scroll of the mouse wheel. On Android
    and iOS, a finger that circles round the tube's centre moves it instead.
    Fire down its lane with the space bar, or while dragging. The Tube knob
    picks one of Tube Shooter's tubes, and the ship switches to it without
    stopping. On an open tube, the ship stops at the ends. Where the tube
    bends, its nearer lanes hide what's beyond them, as a closed tube's walls
    do. The ship's lane shows in the ship's colour, as in Tube Shooter.

    READY shows until a tap or a key starts the game. The first enemy comes
    3 seconds later, and the next ones every 4 seconds. Each enemy that the
    ship's shots destroy makes the ship fly faster, by 5% of its first speed,
    until the ship is lost. The enemies then come more often, so that they
    stay as far apart along the tube. After each READY, the first two
    enemies are seeders. After them, each enemy's kind is picked at random
    among the five, never the same kind twice in a row, except for seeders.
    Each enemy comes on a lane picked at random. For 2 seconds, its lane
    flashes in the enemy's colour and fades back; in the ship's lane, the
    enemy's colour adds to the ship's. The lane, a seeder's spike and the
    enemy glow as they flash: the mesh renderer draws the glow with
    RasterizerGlow, and the other renderers draw wider, see-through copies
    of them instead. The enemy starts just beyond where the bending tube
    hides its lane, so that it comes into sight as the flash ends, or at the
    farthest ring across the tube if the lane shows that far.

    Enemies climb their lanes toward the ship, and disappear when they pass
    it. A seeder lays a spike behind it, which disappears when all of it has
    passed the ship. A climber flips onto a neighbouring lane every 2 to 4
    seconds, and fires down its lane every 3 to 5 seconds, with at most 2
    climbers' shots in the tube. Its shots climb faster than it does. A
    zapper flips every 3 to 6 seconds. The zappers pulse together every 3
    seconds, for 0.6 of a second. Each flashes white for half a second
    before, and while they pulse, a bolt zigzags from each down its lane to
    the ship's ring, glowing as the flash does, or with wider, see-through
    copies. A splitter neither flips nor fires. When it gets within 4 units
    of the ship, it splits into two climbers, which flip onto the lanes on
    either side. An edge-walker climbs on the edges between lanes, and
    crosses a lane after 1 to 2.5 seconds on an edge. A shot can destroy it
    only while it crosses a lane. All these times are those of Tube
    Shooter's first level.

    The ship's shots fly ahead of it as fast as Tube Shooter's, and go up to
    8 units ahead of the ship, or until the tube bends them out of sight.
    They hit only what shows. As in Tube Shooter, a shot destroys a seeder
    for 50 points and leaves its spike, cuts a spike back from its near end
    for 2 points, destroys a climber for 100, a zapper for 200 or an
    edge-walker for 250, splits a splitter for 150, and destroys a climber's
    shot. An enemy, a spike or a climber's shot that reaches the ship's ring
    in the ship's lane destroys the ship and takes a life. So does an
    edge-walker on an edge of the ship's lane, or a bolt down that lane. The
    enemies, spikes and shots disappear, and READY shows again. When the
    lives run out, Game Over stops the game until a tap or Enter starts a
    new one. The bottom left shows the tube's name and how long the game has
    been played in that tube, and the bottom right the lives left and the
    score. The game plays Tube Shooter's sounds for the same events, and the
    Sound knob turns them on and off. A new renderer's game continues with
    the same ship, enemies, spikes and shots, from where they were.

    The game makes the tube's quads again every frame. The mesh renderer fills
    each quad on its own, as a fan of triangles, rather than their union. The
    bar under the game shows the renderer, the frame times, the renderer's own
    numbers, the tube's quads and the paths made each second.
  ''';

  /// The tube the ship flies down, one of [tubes].
  Tube get tube => view.tube;

  /// Switches to another tube where the ship is, without stopping: see
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
    // Fits the view before the ship loads, as the ship sizes the import of
    // its shape for the view.
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
  int get shipStep => runner.shipStep;

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
  super.from,
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
  super.from,
}) extends TubeRunnerExample
    with FlamePathComponents<ExampleWorld>, FlameTubeHost;
