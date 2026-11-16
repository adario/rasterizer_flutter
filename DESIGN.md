# Design

This page explains why the packages are built the way they are. [rasterizer_gpu's README](rasterizer_gpu/README.md)
and [flame_rasterizer's](flame_rasterizer/README.md) describe how each renderer works, and its API. The numbers come
from an M1 Mac, in profile builds, unless said otherwise.

## The workload

The packages target 100 to 1000 vector components on screen, sharing 10 to 50 SVGs of 1 to 10 paths each. That's up to
about 10,000 path instances a frame, mostly vector, with a few sprites or text between them. Vector content keeps its
place in the paint order: the renderers draw a frame's vectors as runs, each a contiguous stretch of vector components
between other draws.

## The core

- **A patched copy of upstream's C++** lives in `rasterizer_gpu/src/core/`. Its README lists each patch, and
  `upstream.patch` holds them all against upstream's commit. The packages don't use upstream's Metal and Swift code.
- **The package's build hook compiles the core**, and Dart calls it through hand-written `@Native` bindings, as its C
  API is small.
- **The build hook also builds the shader bundle**, rather than shipping a prebuilt one, as a bundle only loads with the
  `impellerc` of the engine it was built with. So on every platform, `flutter test` needs the app built once first.

## The GPU (atlas) renderer

- **One atlas a frame.** The renderer renders all of a frame's runs in one pass list, into one atlas, and draws each run
  from its rectangles with `drawImageRect`. A render per run would pay a full screen's fixed costs (target, passes,
  composite) for each run.
- **Frame data in a texture.** Flutter GPU has no storage buffers, so each frame goes into an `r32g32b32a32Float`
  texture, which the shaders read with `texelFetch`. On a 4×4 grid of tigers, the vertex shaders take 0.92 ms a frame,
  against 0.66 ms for upstream's, which use Metal buffers (Instruments, profile). For one tiger, the GPU time is on
  par: 5–8% faster.
- **Coverage accumulates in `r32Float`.** In `r16g16b16a16Float`, a thousand additions of 0.001 end 2.3% off, so that
  format is only the fallback on OpenGL ES.
- **3 frames in flight**, as Flutter GPU has no fences to wait on.
- **One copy per upload.** Each frame slot has a host-visible `DeviceBuffer`, which `copyBufferToTexture` copies into
  the data texture. For 300 animated tigers, the upload takes a median 1.92 ms, against 5.69 ms through
  `Texture.overwrite`.
- **Per-entry opacity and colour filters.** The renderer folds opacity, and colour filters that keep alpha, into each
  path's paint, so components that differ only by them share a run. With 1000 components, each with its own
  `ColorEffect`, that's 1 run, a 45.9 MB atlas and 0.28 ms of raster time, against 1000 runs, 1241.6 MB and 1.08 ms when
  each is drawn as its own image.
- **Atlas pages grow at once, and shrink only after 120 frames that needed less than half of them**, or after a
  viewport change. So a zoom cycle doesn't reallocate them over and over.

## The mesh renderer

Games' SVGs keep their geometry once loaded, and only move. So the mesh renderer imports each SVG once into triangles
that stay on the GPU, and each frame only writes its entries' transforms. It's flame_rasterizer's default. The atlas
renderer stays rasterizer_gpu's default, as it draws any SVG at any size with no import.

- **CPU:** for 100 SVGs, the UI thread spends 0.8–1.3 ms a frame, whatever the SVG and zoom, against 1.9–5.1 ms with
  the atlas renderer (11–13 ms with the tiger). For 300 tigers, it's 2.1 ms, against 9.3–21.7 ms. Memory peaks about
  120 MB lower.
- **GPU:** the renderer draws opaque meshes without blending, so Apple's GPUs shade only their topmost fragments, and
  strokes are strips of triangles. 100 overlapping invaders at zoom 1 take 1.37 ms of GPU time a frame, against 1.33 ms
  with the atlas renderer. Instances without a gradient have a fragment shader of their own: for 100 copies of the
  example's `flame.svg`, which has 3 gradients, fragment time drops to 2.73 ms, from 7.01 ms with one shader for both.
- **libtess2 triangulates fills and self-overlapping strokes.** Points first snap to a grid: the largest power of two
  within 1/32 of the tolerance. Without it, fused multiply-adds on arm64 made the sweep contradict itself on exactly
  collinear edges, so a path came back empty or never finished. With it, all 173,186 imports of the Tube Shooter's
  frames came back whole. Each tessellation also has a memory budget, 64 MiB plus 4 KiB a point. Past it, the path
  isn't drawn, rather than the sweep taking the machine's memory.
- **A path index is a float**, as Impeller's OpenGL ES backend has no integer vertex attributes.
- **Targets are sized as atlas pages are, and shrink after 120 frames below 3/4 of their area.** On a 2880×1620
  window, the Tube Shooter holds 60–68 MB in play, against 192.5 MB with targets that only grow (macOS, debug).
- **Glow is geometry.** The import makes halo ribbons, drawn with the mesh, so a frame needs no layer or blur.

## The canvas renderer

It has the same API in Dart, with no `dart:ffi`, so it builds for web. It draws wherever the GPU renderers can't: on
Skia, Windows and web, and on OpenGL ES unless the app opts in. It parses SVGs with vector_graphics_compiler. It
records each scene once, as a `Picture`: at 1000 vectors, that takes 2.10 ms of UI time a frame, against 4.06 ms when
drawing their paths, for 5–10% more raster time.

## OpenGL ES

The GPU renderers draw on OpenGL ES from the first frame, as on Metal and Vulkan, unless the app turns them off. They
have only run on the Android emulator's OpenGL ES and on Mesa's llvmpipe.

- **No self-test.** Nothing checks the output or guards against a driver's crashes, so the canvas renderer never draws
  first and nothing switches. There are two checks. Support makes a texture 4096 px wide, as wide as the renderers'
  get, and leaves OpenGL ES to the canvas renderer if it can't: it's decided before any scene is made. The format probe
  renders a scene accumulating in r32Float, reads it back alongside the app's frames, and switches the GPU renderer to
  r16g16b16a16Float if the pixels are wrong. It then checks r16g16b16a16Float too, but only reports a failure: falling
  back to the canvas renderer that late would need scenes to switch.
- **Each renderer compiles all of its pipelines as it's made**, as each compile blocks the UI thread, so the app
  hitches once rather than at whichever frames first draw with each: 110 ms for the GPU renderer on the Android
  emulator, 470 ms on llvmpipe (release builds, no shader cache).
- **Nothing waits for a frame.** With Flutter 3.50.0, Flutter GPU's calls don't block before the first rasterized frame
  on OpenGL ES, so renderers can be made before `runApp`.

## Flame

- **`RasterizerCanvas` wraps the game's canvas.** Vector components add entries to the current run, with the canvas's
  transform, perspective included. Any other draw, clip or layer ends the run. The whole transform goes to the GPU, so
  vectors stay sharp at any zoom.
- **The GPU renderers draw a run's image with its paint**, not in a layer. The exceptions are image and mask filters,
  and blend modes that change what's under transparent pixels, across several parts.
- **`SvgHitbox`es share polygons** per outline and size. Making a hitbox takes 0.002 ms, against 0.004–0.03 ms when
  Flame builds each hitbox's polygons, path and segments itself.
- **Flame's main branch**, through the root `pubspec.yaml`'s overrides, until Flame 2.0 is on pub.dev.

## Tests

- **Goldens are integration tests in the app**, as flutter_tester antialiases about 2% of pixels differently.
- **Each platform has its own set**, as GPUs round differently: the iPhone's A13 isn't the Mac's M1.
- **Tolerances count pixels off by over 2/255**, as the core's output varies by 1/255 from frame to frame. The tests
  compare the canvas renderer's goldens in 4×4 blocks, as Impeller multisamples it.
