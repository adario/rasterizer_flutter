// Watches the frames that the C++ core writes for the GPU renderer: see
// core_frames_ffi.dart. On the web, without dart:ffi, there are none.
export 'core_frames_stub.dart' if (dart.library.ffi) 'core_frames_ffi.dart';
