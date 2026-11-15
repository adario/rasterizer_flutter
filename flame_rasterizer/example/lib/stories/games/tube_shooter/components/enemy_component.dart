import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/edge_walker_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/lane_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// The kinds of enemy, each with the score for destroying one.
enum EnemyKind(final int score) {
  climber(100),
  splitter(150),
  seeder(50),
  zapper(200),
  edgeWalker(250);

  Path get shape => switch (this) {
    climber => Shapes.climber,
    splitter => Shapes.splitter,
    seeder => Shapes.seeder,
    zapper => Shapes.zapper,
    edgeWalker => Shapes.edgeWalker,
  };

  Color get color => switch (this) {
    climber => TubeColors.climber,
    splitter => TubeColors.splitter,
    seeder => TubeColors.seeder,
    zapper => TubeColors.zapper,
    edgeWalker => TubeColors.edgeWalker,
  };

  /// Creates an enemy of this kind in [lane], at [depth].
  EnemyComponent create({required int lane, required double depth}) =>
      switch (this) {
        climber => ClimberComponent(lane: lane, depth: depth),
        splitter => SplitterComponent(lane: lane, depth: depth),
        seeder => SeederComponent(lane: lane, depth: depth),
        zapper => ZapperComponent(lane: lane, depth: depth),
        edgeWalker => EdgeWalkerComponent(lane: lane, depth: depth),
      };

  /// Creates an enemy of this kind that goes on from [from], the snapshot of
  /// an enemy in a game with another renderer.
  EnemyComponent goOnFrom(EnemySnapshot from) {
    final (:lane, :depth, previousDepth: _) = from.at;
    return switch (this) {
      climber => ClimberComponent(lane: lane, depth: depth, from: from),
      splitter => SplitterComponent(lane: lane, depth: depth, from: from),
      seeder => SeederComponent(lane: lane, depth: depth, from: from),
      zapper => ZapperComponent(lane: lane, depth: depth, from: from),
      edgeWalker => EdgeWalkerComponent(lane: lane, depth: depth, from: from),
    };
  }
}

/// What an enemy in a game for another renderer goes on from: its kind, where
/// it is, its flip, if any, and what its kind keeps, as
/// [EnemyComponent.ownSnapshot] gives it.
typedef EnemySnapshot = ({
  EnemyKind kind,
  LaneSnapshot at,
  ({int to, double progress, double angle})? flip,
  Record? own,
});

/// An enemy in a lane of the tube, which can flip onto a neighbouring lane.
///
/// Given [from], it goes on from there.
abstract class EnemyComponent(
  final EnemyKind kind, {
  required super.lane,
  required super.depth,
  final EnemySnapshot? from,
}) extends LaneComponent {
  this : super(kind.shape, kind.color, previousDepth: from?.at.previousDepth);

  int? _flipTo = from?.flip?.to;
  double _flipProgress = from?.flip?.progress ?? 0;
  double _flipAngle = from?.flip?.angle ?? 0;

  /// What a game with another renderer goes on from.
  ///
  /// An enemy that hasn't loaded yet has made no picks of its kind, so the
  /// new game's makes them.
  EnemySnapshot get snapshot => (
    kind: kind,
    at: laneSnapshot,
    flip: switch (_flipTo) {
      final to? => (to: to, progress: _flipProgress, angle: _flipAngle),
      null => null,
    },
    own: isLoaded ? ownSnapshot : null,
  );

  /// What its kind keeps beyond [snapshot]'s, if anything, for a game with
  /// another renderer to go on from.
  Record? get ownSnapshot => null;

  bool get isFlipping => _flipTo != null;

  /// Whether a shot in its lane can destroy it.
  bool get canBeShot => true;

  /// Returns whether it destroys the ship now, with the ship in [shipLane] on
  /// the rim.
  bool destroysShip(int shipLane) => false;

  /// Returns a random time within [range].
  double between(Range range) =>
      range.least + (range.most - range.least) * gameRef.random.nextDouble();

  /// The lane it counts as in, for hits: halfway through a flip, it's the
  /// lane it flips to.
  int get currentLane {
    final to = _flipTo;
    return to != null && _flipProgress >= 0.5 ? to : lane;
  }

  /// Flips onto lane [to], next to its own in [tube], unless it's already
  /// flipping.
  ///
  /// It turns about the corner the two lanes share, through the inside of the
  /// tube, over the level's flip time.
  void flip(int to, Tube tube) {
    if (_flipTo != null) {
      return;
    }
    _flipTo = to;
    _flipProgress = 0;
    _flipAngle = tube.flipAngle(lane, to);
  }

  /// Flips onto the next lane on [side], 1 or -1, or onto the one on the
  /// other side if an open tube ends there.
  void flipAside(int side) {
    final tube = gameRef.view.tube;
    flip((tube.neighbour(lane, side) ?? tube.neighbour(lane, -side))!, tube);
  }

  @override
  void move(double dt) {
    final to = _flipTo;
    if (to == null) {
      return;
    }
    _flipProgress += dt * gameRef.pace / gameRef.level.flipTime;
    if (_flipProgress >= 1) {
      lane = to;
      _flipTo = null;
    }
  }

  @override
  void place() {
    final to = _flipTo;
    if (to == null) {
      return super.place();
    }
    final view = gameRef.view;
    final tube = view.tube;
    final scale = view.scaleAt(depth);
    final corner = tube.points[tube.cornerOf(lane, to)];
    final turn = _flipAngle * _flipProgress;
    final at =
        (corner + Tube.rotate(tube.middles[lane] - corner, turn)) * scale;
    position.setValues(at.dx, at.dy);
    angle = tube.angles[lane] + turn;
    this.scale.splat(tube.laneWidth * scale);
  }
}
