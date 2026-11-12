import 'dart:typed_data';

/// No directory: without dart:io, as on the web, nothing is saved.
String? get pngDirectory => null;

/// Does nothing, as there's no file system to save [png] to.
void savePng(String name, Uint8List png) {}
