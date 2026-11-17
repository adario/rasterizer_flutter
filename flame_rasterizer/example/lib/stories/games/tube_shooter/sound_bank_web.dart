import 'dart:js_interop';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/sounds.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// The game's sounds on the web, which the Web Audio API plays: each sound is
/// decoded once, and each play starts a new source node with it.
///
/// audioplayers plays each sound with an `<audio>` element instead, and in
/// Safari starting one can block the page for hundreds of milliseconds.
class SoundBank._(final Map<Sound, web.AudioBuffer> _buffers, final int _size) {
  /// The page's audio context, which every game shares: once the user's input
  /// starts it, it stays started for the games that come later.
  static web.AudioContext? _context;

  /// The decoded sounds, which every game shares.
  static final _decoded = <Sound, Future<web.AudioBuffer>>{};

  /// How many banks are loaded and not disposed: while there are none, the
  /// context is suspended, so that it costs nothing.
  static var _banks = 0;

  /// How many times each sound is playing.
  final _playing = <Sound, int>{};

  /// Loads every sound, which can play [size] times at once.
  static Future<SoundBank> load({required int size}) async {
    final context = _context ??= _createContext();
    final buffers = {
      for (final sound in Sound.values)
        sound: await (_decoded[sound] ??= _decode(context, sound)),
    };
    _banks++;
    context.resume().toDart.ignore();
    return SoundBank._(buffers, size);
  }

  static web.AudioContext _createContext() {
    final context = web.AudioContext();
    // Browsers start a context only during the user's input, such as a tap or
    // a key, and Safari suspends it when interrupted. The listeners capture
    // on the window, so they run before Flutter's own.
    final resume = ((web.Event _) {
      if (_banks > 0 && context.state != 'running') {
        context.resume().toDart.ignore();
      }
    }).toJS;
    for (final type in ['pointerdown', 'pointerup', 'touchend', 'keydown']) {
      web.window.addEventListener(
        type,
        resume,
        web.AddEventListenerOptions(capture: true),
      );
    }
    return context;
  }

  static Future<web.AudioBuffer> _decode(
    web.AudioContext context,
    Sound sound,
  ) async {
    final data = await rootBundle.load(sound.path);
    // A copy of just the asset's bytes, which decodeAudioData takes over.
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return await context.decodeAudioData(bytes.buffer.toJS).toDart;
  }

  /// Plays [sound], unless it's already playing as many times as it can:
  /// then, skips it.
  void play(Sound sound) {
    final context = _context!;
    final playing = _playing[sound] ?? 0;
    // A source started while the context is suspended would play when it
    // resumes, together with every other sound started meanwhile.
    if (playing >= _size || context.state != 'running') {
      return;
    }
    final source = context.createBufferSource()..buffer = _buffers[sound];
    source.connect(context.destination);
    source.onended = ((web.Event _) {
      _playing[sound] = _playing[sound]! - 1;
    }).toJS;
    _playing[sound] = playing + 1;
    source.start();
  }

  /// Stops this game's sounds from playing, and suspends the context if no
  /// other game uses it.
  Future<void> dispose() async {
    _banks--;
    if (_banks == 0) {
      await _context!.suspend().toDart;
    }
  }
}
