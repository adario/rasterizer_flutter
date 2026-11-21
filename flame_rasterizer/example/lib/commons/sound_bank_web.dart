import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// A game's sounds on the web, which the Web Audio API plays: each sound is
/// decoded once, and each play starts a new source node with it.
///
/// audioplayers plays each sound with an `<audio>` element instead, and in
/// Safari starting one can block the page for hundreds of milliseconds.
class SoundBank._(
  final Map<String, web.AudioBuffer> _buffers,
  final int _size,
) {
  /// The page's audio context, which every game shares: once the user's input
  /// starts it, it stays started for the games that come later.
  static web.AudioContext? _context;

  /// The decoded sounds, which every game shares.
  static final _decoded = <String, Future<web.AudioBuffer>>{};

  /// How many banks are loaded and not disposed: while there are none, the
  /// context is suspended, so that it costs nothing.
  static var _banks = 0;

  /// How many times each sound is playing.
  final _playing = <String, int>{};

  /// Loads the sounds at [paths], each of which can play [size] times at
  /// once.
  static Future<SoundBank> load(
    List<String> paths, {
    required int size,
  }) async {
    final context = _context ??= _createContext();
    final buffers = {
      for (final path in paths)
        path: await (_decoded[path] ??= _decode(context, path)),
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
    String path,
  ) async {
    final data = await rootBundle.load(path);
    // A copy of just the asset's bytes, which decodeAudioData takes over.
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return await context.decodeAudioData(bytes.buffer.toJS).toDart;
  }

  /// Plays the sound at [path], unless it's already playing as many times as
  /// it can: then, skips it.
  void play(String path) {
    final context = _context!;
    final playing = _playing[path] ?? 0;
    // A source started while the context is suspended would play when it
    // resumes, together with every other sound started meanwhile.
    if (playing >= _size || context.state != 'running') {
      return;
    }
    final source = context.createBufferSource()..buffer = _buffers[path];
    source.connect(context.destination);
    source.onended = ((web.Event _) {
      _playing[path] = _playing[path]! - 1;
    }).toJS;
    _playing[path] = playing + 1;
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
