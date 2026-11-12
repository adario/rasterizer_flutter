// Picks where the check saves its images: to the temporary directory where
// dart:io is available (see save_png_io.dart), and nowhere on the web.
export 'save_png_web.dart' if (dart.library.io) 'save_png_io.dart';
