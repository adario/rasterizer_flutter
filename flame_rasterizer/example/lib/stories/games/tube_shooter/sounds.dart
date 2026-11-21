import 'package:flame_rasterizer_example/commons/game_sounds.dart';

/// The game's sounds, which [GameSounds] plays.
enum Sound(final String file) {
  /// The ship fires.
  fire('fire'),

  /// An enemy fires.
  enemyFire('enemy_fire'),

  /// An enemy is destroyed.
  explosion('explosion'),

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
