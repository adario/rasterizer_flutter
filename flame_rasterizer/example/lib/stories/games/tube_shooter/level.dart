import 'dart:ui';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';

/// A level: its tube, the colour of the tube's lines, and the numbers that set
/// its difficulty in the first round.
///
/// Each later round goes [roundSpeedUp] times as fast as the one before. Times
/// are in seconds, and depths are fractions of the tube's depth from the rim.
typedef Level = ({
  Tube tube,
  Color color,

  /// How many enemies of each kind a round has. A new one comes every
  /// [spawnPeriod], with at most [maxEnemies] in the tube.
  int climbers,
  int splitters,
  int seeders,
  int zappers,
  int edgeWalkers,
  double spawnPeriod,
  int maxEnemies,

  /// How long each kind takes to climb the tube. Seeders only climb to
  /// [seederTurn], then go back down.
  double climberTime,
  double splitterTime,
  double seederTime,
  double seederTurn,
  double zapperTime,
  double edgeWalkerTime,

  /// A climber flips onto a neighbouring lane after a random time within
  /// [flipPeriod], taking [flipTime]. At the rim, it flips toward the ship
  /// every [rimFlipPeriod].
  (double, double) flipPeriod,
  double flipTime,
  double rimFlipPeriod,

  /// A climber fires after a random time within [firePeriod], while fewer
  /// than [maxEnemyShots] shots are in the tube. A shot climbs the tube in
  /// [enemyShotTime].
  (double, double) firePeriod,
  int maxEnemyShots,
  double enemyShotTime,

  /// A zapper flips as a climber does, after a random time within
  /// [zapperFlipPeriod], and at the rim every [zapperRimFlipPeriod]. All the
  /// zappers pulse together every [pulsePeriod], for [pulseTime]. Each one
  /// flashes white for [pulseWarning] before a pulse.
  (double, double) zapperFlipPeriod,
  double zapperRimFlipPeriod,
  double pulsePeriod,
  double pulseTime,
  double pulseWarning,

  /// An edge-walker crosses a lane after a random time within [crossPeriod],
  /// taking [crossTime]. At the rim, it crosses toward the ship every
  /// [rimCrossPeriod].
  (double, double) crossPeriod,
  double crossTime,
  double rimCrossPeriod,
});

/// How much faster each round goes than the one before.
const roundSpeedUp = 1.05;

/// The levels, from the easiest to the hardest. Rounds play them in turn, then
/// start again from the first. Each has about one enemy per lane, at least 12,
/// of every kind.
final List<Level> levels = [
  _level(
    Tubes.hexagon,
    TubeColors.tube,
    climbers: 6,
    splitters: 2,
    seeders: 2,
    zappers: 1,
    edgeWalkers: 1,
  ),
  _level(
    Tubes.floor,
    TubeColors.tubeOrange,
    climbers: 6,
    splitters: 2,
    seeders: 2,
    zappers: 1,
    edgeWalkers: 1,
  ),
  _level(
    Tubes.ridge,
    TubeColors.tubeLime,
    climbers: 5,
    splitters: 2,
    seeders: 1,
    zappers: 2,
    edgeWalkers: 2,
  ),
  _level(
    Tubes.horseshoe,
    TubeColors.tubeSlate,
    climbers: 4,
    splitters: 2,
    seeders: 2,
    zappers: 2,
    edgeWalkers: 2,
  ),
  _level(
    Tubes.octagon,
    TubeColors.tube,
    climbers: 6,
    splitters: 3,
    seeders: 3,
    zappers: 2,
    edgeWalkers: 2,
  ),
  _level(
    Tubes.cog,
    TubeColors.tubeOrange,
    climbers: 5,
    splitters: 3,
    seeders: 5,
    zappers: 3,
    edgeWalkers: 2,
  ),
  _level(
    Tubes.star,
    TubeColors.tubeLime,
    climbers: 8,
    splitters: 4,
    seeders: 4,
    zappers: 2,
    edgeWalkers: 2,
  ),
  _level(
    Tubes.diamond,
    TubeColors.tubeSlate,
    climbers: 4,
    splitters: 6,
    seeders: 3,
    zappers: 2,
    edgeWalkers: 1,
  ),
];

/// A level on [tube], in [color], with those enemies and the numbers that all
/// levels share.
Level _level(
  Tube tube,
  Color color, {
  required int climbers,
  required int splitters,
  required int seeders,
  required int zappers,
  required int edgeWalkers,
}) => (
  tube: tube,
  color: color,
  climbers: climbers,
  splitters: splitters,
  seeders: seeders,
  zappers: zappers,
  edgeWalkers: edgeWalkers,
  spawnPeriod: 2.5,
  maxEnemies: 4,
  climberTime: 8,
  splitterTime: 12,
  seederTime: 6,
  seederTurn: 0.4,
  zapperTime: 10,
  edgeWalkerTime: 9,
  flipPeriod: (2, 4),
  flipTime: 0.25,
  rimFlipPeriod: 0.8,
  firePeriod: (3, 5),
  maxEnemyShots: 2,
  enemyShotTime: 3,
  zapperFlipPeriod: (3, 6),
  zapperRimFlipPeriod: 1.5,
  pulsePeriod: 3,
  pulseTime: 0.6,
  pulseWarning: 0.5,
  crossPeriod: (1, 2.5),
  crossTime: 0.4,
  rimCrossPeriod: 1.2,
);
