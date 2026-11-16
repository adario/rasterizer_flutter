# Changelog

## Unreleased

- **Breaking:** on OpenGL ES, the GPU renderers draw from the first frame,
  as on Metal and Vulkan, with no self-test, and no canvas renderer before a
  switch. `RasterizerGpu.allowOpenGles` is on by default: turned off, the
  canvas renderer draws there. Each renderer compiles its pipelines as it's
  made. A format probe checks that the GPU renderer draws right accumulating
  in r32Float, and makes it accumulate in r16g16b16a16Float otherwise, which
  it then checks too. Where Flutter GPU can't make textures 4096 pixels wide,
  support is the new `RasterizerSupport.smallTextures`, and the canvas
  renderer draws.
- **Breaking:** removed with the self-tests: `RasterizerGpu.initialize`,
  `initialized`, `settledBackend`, `rememberSelfTest`, `probationFrames`,
  `onProbation`, `forgetSelfTest` and `debugCountAttempts`, and the same
  members of `RasterizerGpuBackend`. `debugFailFormatProbe`,
  `debugFormatProbe` and `debugProbeFormat` replace `debugFailSelfTest` and
  `debugSelfTest`, and `debugCheckedTextureWidth` is new. The files of
  remembered failures are no longer read, nor deleted. On Linux, they can be
  deleted by hand: `rasterizer_gpu_gles.json` and
  `rasterizer_gpu_gles_mesh.json`, in `$XDG_CACHE_HOME/<executable>/`, or
  `~/.cache/<executable>/`. Android clears them, in the code cache, when the
  app is updated.
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
- The OpenGL ES format probe doesn't parse its SVG: its scene is built as
  NanoSVG parses it, so it checks the GPU alone. Under such a locale, the
  self-tests it replaces failed, and the canvas renderer drew on Linux on any
  GPU.

## 0.0.1

- Initial release.
