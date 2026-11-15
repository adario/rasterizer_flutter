# Changelog

## Unreleased

- `RasterizerFrame.pageSizes` holds `RasterizerPixelSize` records, with a
  named `width` and `height`, instead of positional ones.
- `RasterizerScene.fromPaths` takes `RasterizerPaintedPath` records, with a
  named `path` and `paint`, instead of positional ones.
- With CanvasKit, on the web, the canvas renderer no longer clips to its
  frame, as CanvasKit dropped some scenes drawn near the clip's edge.
- On Linux's OpenGL ES, the GPU renderers draw a run with a paint as on the
  other platforms, without a layer, which cost an offscreen pass per run.
  Impeller no longer draws an image with a color filter about a pixel off
  there, as of Flutter 3.50.0 on Mesa's llvmpipe.
- SVGs read opacities, lengths and viewBoxes the same whatever the C locale.
  Under a locale whose decimal point is a comma, such as `en_DK` or `de_DE`,
  which a GTK app on Linux sets from the user's, `0.5` read as 0: translucent
  paths vanished, and lengths lost their fractions. Lengths in `em` or `ex`,
  such as `1em`, no longer read as 0 with glibc, as on Linux, in any locale.
- The OpenGL ES self-tests no longer parse their SVG: its scene is built as
  NanoSVG parses it, so they check the GPU alone. Under such a locale, both
  failed, and the canvas renderer drew on Linux on any GPU.

## 0.0.1

- Initial release.
