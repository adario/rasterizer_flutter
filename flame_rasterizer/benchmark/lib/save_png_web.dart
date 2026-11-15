import 'dart:typed_data';

/// No directory: without dart:io, as on the web, the benchmark saves nothing.
String? get pngDirectory => null;

/// Does nothing, as there's no file system to save [png] to.
void savePng(String name, Uint8List png) {}
