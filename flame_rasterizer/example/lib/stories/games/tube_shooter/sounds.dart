import 'package:flame_rasterizer_example/stories/games/tube_shooter/sound_bank.dart';
import 'package:flutter/foundation.dart';

/// The game's sounds, which a [SoundBank] plays: see [TubeSounds.play].
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

/// The game's sounds, loaded in the background by [load].
///
/// Until they're loaded, and where they fail to load, such as in tests with
/// no audio plugin, nothing plays.
class TubeSounds() {
  /// How many times each sound can play at once.
  static const playersPerSound = 3;

  SoundBank? _bank;

  /// The sounds started since the last [nextFrame].
  final _played = <Sound>{};

  bool _disposed = false;

  /// Loads every sound.
  Future<void> load() async {
    try {
      final bank = await SoundBank.load(size: playersPerSound);
      if (_disposed) {
        await bank.dispose();
        return;
      }
      _bank = bank;
    } on Object catch (error) {
      debugPrint('Tube Shooter sounds failed to load: $error');
    }
  }

  /// Plays [sound] once, unless it already started this frame: for example,
  /// the enemies that the purge destroys at once sound as one.
  void play(Sound sound) {
    if (_played.add(sound)) {
      _bank?.play(sound);
    }
  }

  /// Lets each sound play again.
  void nextFrame() => _played.clear();

  /// Releases the sounds.
  void dispose() {
    _disposed = true;
    _bank?.dispose();
    _bank = null;
  }
}
