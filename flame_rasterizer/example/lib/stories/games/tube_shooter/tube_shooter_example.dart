import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/foundation.dart';

/// A tube shooter inspired by Atari's Tempest, drawn entirely with paths: see
/// [description].
///
/// Its [shooter] plays the rounds, from [firstLevel]: it hands the mode the
/// player's input. Subclasses pick the component that draws a path: see
/// [pathComponent].
///
/// Given the snapshot of a game with another renderer, it goes on from there:
/// see [TubeShooterSnapshots].
abstract class TubeShooterExample({
  required super.status,
  super.random,

  /// Which of the levels the first round plays.
  final int firstLevel = 0,
  TubeShooterSnapshot? from,
}) extends TubeHost {
  /// Creates the game for [renderer], with Flame's `PathComponent` for Flame
  /// SVG, which goes on from [from], if any, at its first level and pace.
  factory TubeShooterExample.of(
    SvgRenderer renderer,
    ValueNotifier<String> status, {
    math.Random? random,
    int firstLevel = 0,
    TubeShooterSnapshot? from,
  }) => renderer == SvgRenderer.flameSvg
      ? FlameTubeShooterExample(
          status: status,
          random: random,
          firstLevel: from?.firstLevel ?? firstLevel,
          from: from,
        )
      : RasterizerTubeShooterExample(
          status: status,
          renderer: renderer,
          random: random,
          firstLevel: from?.firstLevel ?? firstLevel,
          from: from,
        );

  static const description = '''
    A tube shooter in vector lines. Everything in the game, text included, is
    a Flutter Path. RasterizerPathComponent draws them with the renderer that
    the Renderer knob picks; with Flame SVG, Flame's PathComponent does.

    Move the ship round the rim of the tube with the arrow keys, A and D, by
    dragging left and right, or a lane per scroll of the mouse wheel. On a
    Steam Deck, a trackpad set to Steam Input's Scroll Wheel mode turns it
    round as a finger circles. Fire down its lane with the space bar, or while
    dragging. Enter, or a double tap, purges the tube once a round. Tap or
    press a key to start a round, and to go on after losing a ship.

    Five kinds of enemies climb the tube. Once they're gone, the ship drops
    down its lane to the next of eight tubes, and any spike left in that lane
    destroys it. Each round is 5% faster than the last, and a game that starts
    at a later level goes as fast as if it had started at the first. After
    Game Over, a new game starts at the round reached, as fast.

    The game makes some paths again every frame, such as the tube's during the
    zoom. It shares others among many components, such as the enemies'
    shapes. The Glow knob makes the lines glow: the mesh renderer draws the
    glow with them, and the other renderers draw it with a shader over the
    world. The Level knob shows the round's level, and starts a new game at
    the level it picks. The other knobs turn the sounds on and off, zoom the
    camera and change the game's speed. After each round's drop, the ship
    flies on down Tube Runner's endless tube, by its rules, as the round's
    enemies come again in the same order, then out of it, onto the next
    round's rim. A new renderer's game goes on with the same round, ship,
    enemies and shots, from where they were, but a run's next round starts.
    The bar under the game shows the renderer, the frame times, the
    renderer's own numbers and the paths made each second.

    Inspired by Atari's Tempest (1981).
  ''';

  /// The rounds, and the rules they play by.
  final shooter = ShooterMode(firstLevel: firstLevel, from: from);

  /// What a game for another renderer goes on from.
  TubeShooterSnapshot get snapshot => shooter.snapshot;

  /// The Runs knob's value: see [ShooterMode.runs].
  bool get runs => shooter.runs;
  set runs(bool value) => shooter.runs = value;

  /// Called with the round's level index each time a round starts.
  void Function(int levelIndex)? get onLevel => shooter.onLevel;
  set onLevel(void Function(int levelIndex)? value) => shooter.onLevel = value;

  /// Twice the widest lane, a shape's longest side, as explosions grow to
  /// twice their size.
  @override
  double get shapeGrowth => 2;

  @override
  Future<void> onLoad() async {
    // Fits the view before the ship loads: it sizes its import for the view.
    await super.onLoad();
    world.add(shooter);
    startStatus();
  }

  @override
  bool get canMove => shooter.canMove;

  @override
  bool get isWaiting => shooter.isWaiting;

  @override
  bool get isReady => shooter.isReady;

  @override
  bool get isOver => shooter.isOver;

  @override
  void endWait() => shooter.endWait();

  @override
  void moveShipBy(double lanes) => shooter.moveShipBy(lanes);

  @override
  int get shipStep => shooter.shipStep;

  @override
  void onFiringChanged() => shooter.onFiringChanged();

  /// Purges.
  @override
  void onDoubleTap() => shooter.purge();

  /// Purges.
  @override
  void onEnter() => shooter.purge();

  @override
  void advance(double dt) => shooter.advance(dt);

  @override
  void updateStillLines() => shooter.updateStillLines();

  @override
  void afterUpdate(double dt) => shooter.afterUpdate(dt);
}

/// The example with flame_rasterizer: [RasterizerPathComponent]s draw its
/// paths, with the renderer that the Renderer knob picks.
class RasterizerTubeShooterExample({
  required super.status,
  @override required final SvgRenderer renderer,
  super.random,
  super.firstLevel,
  super.from,
}) extends TubeShooterExample
    with
        HasRasterizer,
        ExampleRasterizer,
        RasterizerPathComponents<ExampleWorld>,
        RasterizerTubeHost {
  this {
    RasterizerGpu.forceCanvas = forceCanvas;
  }

  /// Keeps [drawing]'s stroke, and gives it the shapes' glow too. If the Glow
  /// knob changed, it imports the shape again.
  @override
  void keepStroke(PathComponent drawing, {double widths = 1}) {
    super.keepStroke(drawing, widths: widths);
    (drawing as RasterizerPathComponent).glow = shapeGlow;
  }
}

/// The example with Flame: Flame's [PathComponent]s draw its paths.
class FlameTubeShooterExample({
  required super.status,
  super.random,
  super.firstLevel,
  super.from,
}) extends TubeShooterExample
    with FlamePathComponents<ExampleWorld>, FlameTubeHost;
