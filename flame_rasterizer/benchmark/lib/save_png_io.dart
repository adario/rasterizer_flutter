import 'dart:io';
import 'dart:typed_data';

/// The directory that [savePng] saves to: the system's temporary one.
String? get pngDirectory => Directory.systemTemp.path;

/// Saves [png] as `<name>.png` in [pngDirectory].
void savePng(String name, Uint8List png) =>
    File('$pngDirectory/$name.png').writeAsBytesSync(png);
