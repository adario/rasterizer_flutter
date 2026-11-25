import 'dart:ui' show StrokeCap, StrokeJoin;

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/runner_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// What an enemy in a game for another renderer goes on from: its kind, the
/// lane it came in and the one it's in, where it is, and was before it last
/// climbed, how long it has climbed, its flip, if any, the seconds until it
/// flips, if it picked them, and what its kind keeps, as
/// [RunnerEnemyComponent.ownSnapshot] gives it.
typedef RunnerEnemySnapshot = ({
  EnemyKind kind,
  int spawnLane,
  int lane,
  double at,
  double previousAt,
  double age,
  ({int to, double progress, double angle})? flip,
  double? untilFlip,
  Record? own,
});

/// An enemy of [kind], which comes at the far end of [spawnLane] and climbs
/// the tube toward the ship, with the shape and colour of Tube Shooter's, and
/// [strokeWidths] as wide a stroke.
///
/// The game moves it with [climb], and places it with [placeAt] where the
/// tube says it shows. It goes once it passes the ship.
///
/// For [flashTime] after it comes, it glows in its colour, fading out as
/// [flash] says: with [TubeHost.glowShape] if the renderer draws
/// glows, or else under a wider, see-through copy of its shape, as wide as
/// that glow. A splitter's climbers don't flash, as they don't come down the
/// tube.
///
/// Given [from], it goes on from there.
abstract class RunnerEnemyComponent(
  final EnemyKind kind,
  final int spawnLane, {
  bool flashes = true,
  final RunnerEnemySnapshot? from,
}) extends PositionComponent
    with HasGameRef<TubeHost>, HasVisibility, TubePlaced, InRunnerMode {
  this : super(priority: 1);

  /// How fast every kind climbs its lane, along the axis, in tube units a
  /// second.
  static const climbSpeed = 1.0;

  /// How many times as wide as the ship's its stroke is.
  static const strokeWidths = 2.0;

  /// How long it flashes after it comes, in seconds of the game.
  static const flashTime = 1.5;

  /// Where it is along the axis, in tube units.
  double get at;

  /// Where it was along the axis before it last climbed.
  late double previousAt = from?.previousAt ?? at;

  /// The lane it's in, or flips from.
  int get lane;

  /// The lane it counts as in, for hits.
  int get currentLane;

  /// How long it has climbed, in seconds of the game, or [flashTime] at
  /// first if it doesn't flash.
  double _age = from?.age ?? (flashes ? 0 : flashTime);

  /// What a game with another renderer goes on from.
  RunnerEnemySnapshot get snapshot {
    final self = this;
    final flipper = self is RunnerFlipperComponent ? self : null;
    return (
      kind: kind,
      spawnLane: spawnLane,
      lane: lane,
      at: at,
      previousAt: previousAt,
      age: _age,
      flip: switch (flipper?._flipTo) {
        final to? => (
          to: to,
          progress: flipper!._flipProgress,
          angle: flipper._flipAngle,
        ),
        null => null,
      },
      untilFlip: flipper?._untilFlip,
      own: ownSnapshot,
    );
  }

  /// What its kind keeps beyond [snapshot]'s, if anything, for a game with
  /// another renderer to go on from.
  Record? get ownSnapshot => null;

  /// How strong its flash is: 1 as it comes, fading to 0 over [flashTime].
  double get flash => _age < flashTime ? 1 - _age / flashTime : 0;

  /// The component that draws its shape.
  late final PathComponent drawing;

  /// The component that draws the copy of its shape under it, while it
  /// flashes, if the renderer doesn't draw the glow.
  PathComponent? _halo;

  /// How many times as wide as the ship's the halo's stroke is.
  static const _haloStroke = strokeWidths * 2 * RunnerMode.shapeGlowWidths;

  @override
  Future<void> onLoad() async {
    findRunner();
    if (!gameRef.rendererGlows) {
      add(
        _halo =
            gameRef.shapeComponent(kind.shape, kind.color, widths: _haloStroke)
              ..paint.strokeJoin = StrokeJoin.round
              ..paint.strokeCap = StrokeCap.round
              ..opacity = 0,
      );
    }
    add(
      drawing = gameRef.shapeComponent(
        kind.shape,
        kind.color,
        widths: strokeWidths,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    gameRef
      ..keepStroke(drawing, widths: strokeWidths)
      ..glowShape(
        drawing,
        RunnerMode.flashGlow(RunnerMode.shapeGlowWidths, flash, kind.color),
      );
    final halo = _halo;
    if (halo == null) {
      return;
    }
    if (flash == 0) {
      halo.removeFromParent();
      _halo = null;
      return;
    }
    gameRef.keepStroke(halo, widths: _haloStroke);
    halo.opacity = RunnerMode.haloAlpha * flash;
  }

  /// Climbs over [dt] seconds, as [move] says.
  void climb(double dt) {
    _age += dt;
    previousAt = at;
    move(dt);
  }

  /// Moves it over [dt] seconds, as its kind does.
  void move(double dt);
}

/// An enemy that climbs from [at] in [spawnLane], and flips onto a
/// neighbouring lane after a random time within [flipPeriod], as Tube
/// Shooter's do, over its first level's flip time: it turns about the corner
/// the two lanes share, through the inside of the tube.
abstract class RunnerFlipperComponent(
  super.kind,
  super.spawnLane,
  @override var double at, {
  super.flashes,
  super.from,
}) extends RunnerEnemyComponent {
  @override
  late int lane = from?.lane ?? spawnLane;

  /// The pace of Tube Shooter's first level, which its kind goes at.
  static final level = levels.first;

  /// The range of times between its flips.
  Range get flipPeriod;

  /// The lane it flips onto, if it's flipping, how far through the flip it
  /// is, from 0 to 1, and the angle the whole flip turns by.
  int? _flipTo = from?.flip?.to;
  double _flipProgress = from?.flip?.progress ?? 0;
  double _flipAngle = from?.flip?.angle ?? 0;

  /// Seconds until it flips, once it picked them, as it first climbed.
  double? _untilFlip = from?.untilFlip;

  bool get isFlipping => _flipTo != null;

  /// Halfway through a flip, it's in the lane it flips to, as in Tube
  /// Shooter.
  @override
  int get currentLane {
    final to = _flipTo;
    return to != null && _flipProgress >= 0.5 ? to : lane;
  }

  @override
  TubeMark get mark => (
    lane: lane,
    at: at,
    flip: switch (_flipTo) {
      final to? => (to: to, turn: _flipAngle * _flipProgress),
      null => null,
    },
  );

  @override
  void move(double dt) {
    at -= RunnerEnemyComponent.climbSpeed * dt;
    if (_flipTo case final to?) {
      _flipProgress += dt / level.flipTime;
      if (_flipProgress >= 1) {
        lane = to;
        _flipTo = null;
      }
    }
    var untilFlip = (_untilFlip ?? between(flipPeriod)) - dt;
    if (untilFlip <= 0 && _flipTo == null) {
      untilFlip = between(flipPeriod);
      _flipAside(gameRef.random.nextBool() ? 1 : -1);
    }
    _untilFlip = untilFlip;
  }

  /// Starts flipping onto the next lane on [side], 1 or -1.
  void _flipAside(int side) {
    final tube = gameRef.view.tube;
    flip((tube.neighbour(lane, side) ?? tube.neighbour(lane, -side))!, tube);
  }

  /// Starts flipping onto lane [to], next to its own in [tube].
  void flip(int to, Tube tube) {
    _flipTo = to;
    _flipProgress = 0;
    _flipAngle = tube.flipAngle(lane, to);
  }

  /// Returns a random time within [range].
  double between(Range range) =>
      range.least + (range.most - range.least) * gameRef.random.nextDouble();
}
