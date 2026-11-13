import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// The game's sounds, each played through a [SoundPool]: see
/// [TubeSounds.play].
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

/// A few players of the same sound, which are reused: creating a player each
/// time a sound plays would use up the browser's audio resources, on the web.
class SoundPool._(final List<AudioPlayer> _players) {
  /// Mixed with the other sounds, without taking the audio focus.
  static final _audioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  /// The players asked to play, which haven't started yet.
  final Set<AudioPlayer> _starting = {};

  /// Loads [sound] into [size] players.
  static Future<SoundPool> load(Sound sound, {required int size}) async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < size; i++) {
      final player = AudioPlayer()
        ..audioCache = FlameAudio.audioCache
        // Otherwise, while it plays, it asks the platform for its position
        // every frame, which costs frames.
        ..positionUpdater = null;
      await player.setAudioContext(_audioContext);
      // Back to the start when it ends, ready to play again.
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(sound.path));
      players.add(player);
    }
    return SoundPool._(players);
  }

  /// Plays the sound with a player that isn't busy, if any: otherwise, skips
  /// it.
  void play() {
    final player = _players.where((player) => !_isBusy(player)).firstOrNull;
    if (player == null) {
      return;
    }
    // Busy until it starts, or fails to.
    _starting.add(player);
    player.resume().whenComplete(() => _starting.remove(player));
  }

  bool _isBusy(AudioPlayer player) =>
      _starting.contains(player) || player.state == PlayerState.playing;

  /// Releases the players, which can't be used anymore.
  Future<void> dispose() {
    return Future.wait([for (final player in _players) player.dispose()]);
  }
}

/// The game's sounds, loaded in the background by [load].
///
/// Until they're loaded, and where they fail to load, such as in tests with
/// no audio plugin, nothing plays.
class TubeSounds() {
  /// How many times each sound can play at once.
  static const playersPerSound = 3;

  final _pools = <Sound, SoundPool>{};

  /// The sounds started since the last [nextFrame].
  final _played = <Sound>{};

  bool _disposed = false;

  /// Loads every sound, each into its pool.
  Future<void> load() async {
    try {
      await FlameAudio.audioCache.loadAll([
        for (final sound in Sound.values) sound.path,
      ]);
      for (final sound in Sound.values) {
        final pool = await SoundPool.load(sound, size: playersPerSound);
        if (_disposed) {
          await pool.dispose();
          return;
        }
        _pools[sound] = pool;
      }
    } on Object catch (error) {
      debugPrint('Tube Shooter sounds failed to load: $error');
    }
  }

  /// Plays [sound] once, unless it already started this frame: for example,
  /// the enemies that the purge destroys at once sound as one.
  void play(Sound sound) {
    if (_played.add(sound)) {
      _pools[sound]?.play();
    }
  }

  /// Lets each sound play again.
  void nextFrame() => _played.clear();

  /// Releases the players.
  void dispose() {
    _disposed = true;
    for (final pool in _pools.values) {
      pool.dispose();
    }
    _pools.clear();
  }
}
