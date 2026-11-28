import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// A game's sounds on the web, which the Web Audio API plays.
///
/// Each sound is decoded once, and each play starts a new source node with
/// it. This bank doesn't use audioplayers, which plays each sound with an
/// `<audio>` element: in Safari, starting one can block the page for hundreds
/// of milliseconds.
class SoundBank._(
  final Map<String, web.AudioBuffer> _buffers,
  final Map<String, int> _sizes,
) {
  /// The page's audio context, which every game shares.
  ///
  /// After the user's input starts it, it stays started for later games.
  static web.AudioContext? _context;

  /// The decoded sounds, which every game shares.
  static final _decoded = <String, Future<web.AudioBuffer>>{};

  /// How many banks are loaded and not yet disposed.
  ///
  /// While there are none, the context is suspended, so that it costs nothing.
  static var _banks = 0;

  /// How many times each sound is playing.
  final _playing = <String, int>{};

  /// Loads the sound at each path in [sizes], which can play at once as many
  /// times as [sizes] gives for it.
  static Future<SoundBank> load(Map<String, int> sizes) async {
    final context = _context ??= _createContext();
    final buffers = {
      for (final path in sizes.keys)
        path: await (_decoded[path] ??= _decode(context, path)),
    };
    _banks++;
    context.resume().toDart.ignore();
    return SoundBank._(buffers, sizes);
  }

  static web.AudioContext _createContext() {
    final context = web.AudioContext();
    // Browsers start a context only during the user's input, such as a tap or
    // a key press, and Safari suspends it after an interruption. The
    // listeners capture on the window, so they run before Flutter's own.
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
    // Copies only the asset's bytes into a buffer of their own, because
    // decodeAudioData takes over the buffer it gets.
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    return await context.decodeAudioData(bytes.buffer.toJS).toDart;
  }

  /// Plays the sound at [path], unless it's already playing as many times as
  /// it can.
  void play(String path) {
    final context = _context!;
    final playing = _playing[path] ?? 0;
    // A source started while the context is suspended would play when it
    // resumes, together with every other sound started meanwhile.
    if (playing >= _sizes[path]! || context.state != 'running') {
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
