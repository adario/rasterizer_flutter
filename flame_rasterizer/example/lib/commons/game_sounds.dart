import 'package:flame_rasterizer_example/commons/sound_bank.dart';
import 'package:flutter/foundation.dart';

/// A game's sounds, loaded in the background by [load].
///
/// Until they're loaded, and where they fail to load, such as in tests with
/// no audio plugin, nothing plays. At most [size] of each sound play at once.
class GameSounds(
  /// The sounds' asset paths.
  final List<String> paths, {

  /// How many times each sound can play at once.
  final int size = 3,
}) {
  SoundBank? _bank;

  /// The sounds started since the last [nextFrame].
  final _played = <String>{};

  bool _disposed = false;

  /// Loads every sound.
  Future<void> load() async {
    try {
      final bank = await SoundBank.load(paths, size: size);
      if (_disposed) {
        await bank.dispose();
        return;
      }
      _bank = bank;
    } on Object catch (error) {
      debugPrint('Sounds failed to load: $error');
    }
  }

  /// Plays the sound at [path] once, unless it already started this frame:
  /// for example, the enemies that a purge destroys at once sound as one.
  void play(String path) {
    if (_played.add(path)) {
      _bank?.play(path);
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
