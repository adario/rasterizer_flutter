import 'package:flame_rasterizer_example/commons/game_sounds.dart';

/// The game's sounds, which [GameSounds] plays.
enum Sound(
  final String file, {

  /// How many times the sound can play at once.
  final int size = 3,
}) {
  /// The ship fires: as often as every `RunnerRun.firePeriod`, so as many
  /// times at once as fit in the sound, and one more.
  fire('fire', size: 10),

  /// An enemy fires.
  enemyFire('enemy_fire'),

  /// An enemy is destroyed: often a few, close together.
  explosion('explosion', size: 6),

  /// The ship is destroyed.
  crash('crash'),

  /// A shot shortens a spike.
  spike('spike'),

  /// The zappers' bolts run down their lanes.
  zap('zap'),

  /// The purge destroys every enemy.
  purge('purge'),

  /// The tube zooms in.
  zoom('zoom'),

  /// The ship drops down its lane.
  drop('drop');

  /// The asset's path.
  String get path => 'assets/audio/$file.wav';
}
