import 'package:flame_audio/flame_audio.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';

/// The game's sounds on native platforms, which audioplayers plays: a
/// [SoundPool] for each sound.
class SoundBank._(final Map<Sound, SoundPool> _pools) {
  /// Loads every sound into [size] players.
  static Future<SoundBank> load({required int size}) async {
    await FlameAudio.audioCache.loadAll([
      for (final sound in Sound.values) sound.path,
    ]);
    return SoundBank._({
      for (final sound in Sound.values)
        sound: await SoundPool.load(sound, size: size),
    });
  }

  /// Plays [sound] with one of its players that isn't busy, if any:
  /// otherwise, skips it.
  void play(Sound sound) => _pools[sound]!.play();

  /// Releases the players, which can't be used anymore.
  Future<void> dispose() {
    return Future.wait([for (final pool in _pools.values) pool.dispose()]);
  }
}

/// A few players of the same sound, which are reused rather than created
/// each time the sound plays.
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
