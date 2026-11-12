// Reads the GPU renderer's frames for the golden tests out of their atlas
// pages: see golden_atlas_ffi.dart. On the web, without dart:ffi, there are
// none.
export 'golden_atlas_stub.dart' if (dart.library.ffi) 'golden_atlas_ffi.dart';
