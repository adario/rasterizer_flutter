// Picks how the game plays its sounds: with audioplayers on native platforms
// (see sound_bank_native.dart), and with the Web Audio API on the web (see
// sound_bank_web.dart).
export 'sound_bank_native.dart'
    if (dart.library.js_interop) 'sound_bank_web.dart';
