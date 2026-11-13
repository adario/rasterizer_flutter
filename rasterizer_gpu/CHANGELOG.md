# Changelog

## Unreleased

- With CanvasKit, on the web, the canvas renderer no longer clips to its
  frame, as CanvasKit dropped some scenes drawn near the clip's edge.
- On Linux's OpenGL ES, the GPU renderers draw a run with a paint as on the
  other platforms, without a layer, which cost an offscreen pass per run.
  Impeller no longer draws an image with a color filter about a pixel off
  there, as of Flutter 3.50.0 on Mesa's llvmpipe.

## 0.0.1

- Initial release.
