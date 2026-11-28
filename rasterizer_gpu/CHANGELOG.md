# Changelog

## Unreleased

- Added `RasterizerPolygons`, a shape made of polygons. A scene draws it as
  it draws a path, but the GPU renderers don't need to flatten it into
  lines first. `RasterizerScene.fromPolygons` makes a scene of them. With
  `separate: true`, the mesh renderer fills each polygon on its own instead
  of filling their union, and fills a convex polygon as a fan of triangles.
- The mesh renderer draws an opaque scene's entries in fewer draws. It used
  to start a new draw whenever entries switched between full and partial
  opacity. Now it draws them together, blended, and gives an unblended draw
  of their own only to 8 or more consecutive entries at full opacity. So a
  star field of one scene at many opacities takes a few draws instead of
  one for each change. This applies to scenes without strokes or gradients.
- The mesh renderer imports paths and polygons with many small contours a
  third faster. It now reserves room for each contour's points once,
  instead of growing them as it reads them.

- The GPU renderers draw on Windows too, on Impeller's OpenGL ES through
  ANGLE, where the app's runner turns Flutter GPU on. The build hook builds
  the native library there with MSVC. Not tested on Windows yet.
- **Breaking:** on OpenGL ES, the GPU renderers draw from the first frame,
  as on Metal and Vulkan, with no self-test, and no canvas renderer before a
  switch. `RasterizerGpu.allowOpenGles` is on by default: turned off, the
  canvas renderer draws there. Each renderer compiles its pipelines when
  it's created. A format probe checks that the GPU renderer draws right
  when it accumulates in r32Float, and otherwise makes it accumulate in
  r16g16b16a16Float, which the probe then checks too. Where Flutter GPU
  can't make textures 4096 pixels wide, support is the new
  `RasterizerSupport.smallTextures`, and the canvas renderer draws.
- On OpenGL ES, `RasterizerRenderer.create` completes once the renderer's
  pipelines have compiled on the raster thread too, so its first frame no
  longer pays for them, and an app can show a loader until then.
- **Breaking:** removed with the self-tests: `RasterizerGpu.initialize`,
  `initialized`, `settledBackend`, `rememberSelfTest`, `probationFrames`,
  `onProbation`, `forgetSelfTest` and `debugCountAttempts`, and the same
  members of `RasterizerGpuBackend`. `debugFailFormatProbe`,
  `debugFormatProbe` and `debugProbeFormat` replace `debugFailSelfTest` and
  `debugSelfTest`, and `debugCheckedTextureWidth` is new. The files of
  remembered failures are no longer read or deleted. On Linux, delete them
  by hand: `rasterizer_gpu_gles.json` and `rasterizer_gpu_gles_mesh.json`,
  in `$XDG_CACHE_HOME/<executable>/`, or `~/.cache/<executable>/`. Android clears them, in the code cache, when the
  app is updated.
- `RasterizerFrame.pageSizes` holds `RasterizerPixelSize` records, with a
  named `width` and `height`, instead of positional ones.
- `RasterizerScene.fromPaths` takes `RasterizerPaintedPath` records, with a
  named `path` and `paint`, instead of positional ones.
- With CanvasKit, on the web, the canvas renderer no longer clips to its
  frame, as CanvasKit dropped some scenes drawn near the clip's edge.
- On Linux's OpenGL ES, the GPU renderers draw a run with a paint as on the
  other platforms, without the layer that cost an offscreen pass per run.
  As of Flutter 3.50.0 on Mesa's llvmpipe, Impeller no longer draws an
  image with a color filter about a pixel off there.
- SVGs read opacities, lengths and viewBoxes the same whatever the C locale.
  Under a locale whose decimal point is a comma, such as `en_DK` or `de_DE`,
  which a GTK app on Linux sets from the user's, `0.5` read as 0: translucent
  paths vanished, and lengths lost their fractions. Lengths in `em` or `ex`,
  such as `1em`, no longer read as 0 in any locale with glibc, as on Linux.
- The OpenGL ES format probe doesn't parse its SVG: it builds the scene
  that NanoSVG would parse, so it checks the GPU alone. Under such a locale,
  the self-tests it replaces failed, so the canvas renderer drew on Linux
  whatever the GPU.

## 0.0.1

- Initial release.
