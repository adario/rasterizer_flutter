import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/climber_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/edge_walker_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/lane_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/seeder_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/splitter_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/zapper_component.dart';
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
}

/// An enemy in a lane of the tube, which can flip onto a neighbouring lane.
abstract class EnemyComponent(
  final EnemyKind kind, {
  required super.lane,
  required super.depth,
}) extends LaneComponent {
  this : super(kind.shape, kind.color);

  int? _flipTo;
  double _flipProgress = 0;
  double _flipAngle = 0;

  bool get isFlipping => _flipTo != null;

  /// Whether a shot in its lane can destroy it.
  bool get canBeShot => true;

  /// Whether it destroys the ship now, with the ship in [shipLane] on the rim.
  bool destroysShip(int shipLane) => false;

  /// A random time within [range].
  double between((double, double) range) =>
      range.$1 + (range.$2 - range.$1) * gameRef.random.nextDouble();

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
