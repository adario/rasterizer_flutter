/// Returns the GitHub link to a story's source, from its [path] under
/// `lib/stories/`.
String baseLink(String path) {
  const basePath =
      'https://github.com/adario/rasterizer_flutter/blob/main/'
      'flame_rasterizer/example/lib/stories/';

  return '$basePath$path';
}
