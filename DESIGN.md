# Design

This page explains why the packages are built the way they are. [rasterizer_gpu's README](rasterizer_gpu/README.md)
and [flame_rasterizer's](flame_rasterizer/README.md) describe how each renderer works, and their APIs.
[Measurements](#measurements), at the end, has the numbers behind these choices.

## The workload

The packages target 100 to 1000 vector components on screen, sharing 10 to 50 SVGs of 1 to 10 paths each. That's up to
about 10,000 path instances a frame, mostly vector, with a few sprites or text between them. Vector content keeps its
place in the paint order. So the renderers draw a frame's vectors as runs: each run is a stretch of vector components
with no other draw between them.

## The core

- **A patched copy of upstream's C++** lives in `rasterizer_gpu/src/core/`. Its README lists each patch, and
  `upstream.patch` holds them all, as a diff against upstream's commit. The packages don't use upstream's Metal and
  Swift code.
- **The package's build hook compiles the core.** Dart calls it through hand-written `@Native` bindings, as its C API
  is small.
- **The build hook also builds the shader bundle**, rather than shipping a prebuilt one, as a bundle only loads with the
  `impellerc` of the engine that built it. So on every platform, the app must be built once before `flutter test`.

## The GPU (atlas) renderer

- **One atlas a frame.** The renderer renders all of a frame's runs in one list of passes, into one atlas. It then draws
  each run from its rectangles with `drawImageRect`. Rendering each run on its own would pay a full screen's fixed costs
  (target, passes, composite) once per run.
- **Frame data in a texture.** Flutter GPU has no storage buffers, so each frame's data goes into an
  `r32g32b32a32Float` texture, which the shaders read with `texelFetch`. The vertex shaders then take longer than
  upstream's, which read Metal buffers, but for a single tiger, a frame's GPU time is on par with upstream's.
- **Coverage accumulates in `r32Float`.** In `r16g16b16a16Float`, a thousand additions of 0.001 end 2.3% off. So that
  format is only a fallback, on OpenGL ES drivers that can't make or draw `r32Float` correctly.
- **2 frames in flight** by default (`slots`). Flutter GPU has no fences to wait on, so the renderer can't tell when
  the GPU is done with a frame's textures. Flutter often starts building the next frame before the last one has
  rasterized, but it rasterizes each frame before it builds the one after next.
  Under GPU load, Flutter's frame timings showed this on macOS, an iPhone, and the emulator's Vulkan and OpenGL ES. Two
  frames use less memory than three, at the same frame rate. An app that takes an image of a frame after drawing it,
  such as with `RepaintBoundary.toImage`, needs 3.
- **One copy per upload.** Each frame slot has a host-visible `DeviceBuffer`, which `copyBufferToTexture` copies into
  the data texture. That's faster than `Texture.overwrite`.
- **Per-entry opacity and colour filters.** The renderer folds an entry's opacity, and colour filters made with
  `RasterizerColorTransform`, which keep alpha, into each path's paint. So components that differ only by them share a
  run, and the run needs no layer.
- **Atlas pages grow at once, and shrink at most once every 120 frames**, to what those frames needed, if that's less
  than half of a page. After a viewport change, such as a rotation, they shrink at the end of the next 120 frames,
  however little that saves. So a zoom cycle doesn't reallocate them over and over.

## The mesh renderer

Games' SVGs keep their geometry once loaded, and only move. So the mesh renderer imports each SVG once into triangles
that stay on the GPU, and each frame only writes its entries' transforms. It's flame_rasterizer's default. The atlas
renderer stays rasterizer_gpu's default, as it draws any SVG at any size with no import.

- **CPU:** the UI thread's time per frame stays low and steady whatever the SVG and zoom, well below the atlas
  renderer's. Memory peaks lower too.
- **GPU:** the renderer draws opaque meshes without blending, so Apple's GPUs shade only their topmost fragments.
  Strokes are strips of triangles. Overlapping SVGs take about as much GPU time as with the atlas renderer. Instances
  with a colour transform have a fragment shader of their own, so the other instances' gradients don't pay for reading
  the transform in every fragment.
- **libtess2 triangulates fills and self-overlapping strokes.** Points first snap to a grid: the largest power of two
  at most 1/32 of the tolerance. Without the grid, the sweep could contradict itself on nearly collinear edges, mostly
  on arm64, where fused multiply-adds keep rounding errors. A path then came back empty or never finished. Each
  tessellation also has a memory budget, 64 MiB plus 4 KiB a point. Past it, the path isn't drawn, rather than the
  sweep taking all of the machine's memory.
- **A path index is a float**, as Impeller's OpenGL ES backend has no integer vertex attributes.
- **Targets are sized as atlas pages are, and shrink after 120 frames below 3/4 of their area.** That's more than the
  atlas pages' half, so a run that covered the viewport, then much less of it, gives most of its target back.
- **Glow is geometry.** The import makes halo ribbons, drawn with the mesh, so a frame needs no layer or blur.

## The canvas renderer

It has the same API in Dart, with no `dart:ffi`, so it builds for web. It draws wherever the GPU renderers can't: on
Skia and web, and on OpenGL ES if the app turns `RasterizerGpu.allowOpenGles` off. It parses SVGs with
vector_graphics_compiler. By default (`RasterizerGpu.canvasPictures`), it records each scene once as a `Picture`, and
draws that wherever the scene has full opacity and no colour filter. That takes less UI time than drawing the paths
each frame, for a little more raster time.

## OpenGL ES

The GPU renderers draw on OpenGL ES from the first frame, as on Metal and Vulkan, unless the app turns them off. They
have only run on the Android emulator's OpenGL ES and on Mesa's llvmpipe.

- **Only two checks.** Nothing checks what the renderers draw, or guards against a driver's crashes. So the canvas
  renderer never draws first, and the app never switches renderers later. The two checks are:
  - Support makes a texture 4096 px wide, as wide as the renderers' textures get. If it can't, the canvas renderer
    draws on OpenGL ES. This is decided before any scene is made.
  - The first GPU renderer runs a format probe. The probe renders a scene accumulating in r32Float, reads it back
    alongside the app's frames, and switches the GPU renderer to r16g16b16a16Float if the pixels are wrong. Where an
    r32Float texture can't be made, it switches at once. The probe then checks r16g16b16a16Float too, but only reports
    a failure: falling back to the canvas renderer that late would need the app's scenes to switch.
- **Each renderer compiles all of its pipelines as it's made**, as each compile stalls the thread that runs it. So the
  app hitches once, rather than at whichever frames first draw with each pipeline. On OpenGL ES, part of the work runs
  on the UI thread as the renderer is made, and the rest on the raster thread right after. Making the renderer
  completes once both have run, so an app can show a loader meanwhile, and its first frame doesn't pay for them. If
  they haven't compiled within `RasterizerGpu.warmUpTimeout`, 5 s by default, the canvas renderer draws instead, so a
  lost completion doesn't keep the app waiting. A driver that blocks the UI thread while compiling still hangs the app.
- **Nothing waits for a frame.** With Flutter 3.50.0, Flutter GPU's calls don't block before the first frame is
  rasterized on OpenGL ES, so an app can make renderers before `runApp`.

## Flame

- **`HasRasterizer` wraps the game's canvas in a `RasterizerCanvas`.** Vector components add entries to the current
  run, each with the canvas's transform, perspective included. Any other draw, a clip, a layer, or a paint that draws
  differently ends the run. Each entry's whole transform goes to the GPU, so vectors stay sharp at any zoom. The atlas
  renderer is the exception for perspective: it gives an entry under perspective a run of its own, and draws that run's
  image warped.
- **The GPU renderers draw a run's image with its paint**, not in a layer, which saves an offscreen pass. Two cases
  still take a layer: image and mask filters, and blend modes that change what's under transparent pixels, when a run
  has several parts.
- **`SvgHitbox`es share polygons.** Making them is most of what a hitbox costs, so hitboxes that sample one outline the
  same way, such as at the same size, share them.
- **Flame's main branch**, through the root `pubspec.yaml`'s overrides, until Flame 2.0 is on pub.dev.

## Tests

- **Goldens are integration tests in the app**, as flutter_tester antialiases about 2% of pixels differently.
- **Each platform has its own set**, as GPUs round differently: the iPhone's A13 isn't the Mac's M1.
- **The tolerance lets a few pixels differ by over 2/255**: 1 in 10,000 at most, and none by over 16/255. The core can
  sum a frame's coverage in a different order from one render to the next, and float rounding then changes a few
  pixels slightly. The tests compare the canvas renderer's renders with the same goldens in 4×4 blocks, as Impeller
  multisamples its edges.

## Measurements

The numbers come from an M1 Mac, in profile builds, unless the table says otherwise.

| Choice | Case | Result |
|---|---|---|
| Frame data in a texture | Vertex shaders, 4×4 grid of tigers (Instruments) | 0.92 ms a frame, against 0.66 ms for upstream's, which read Metal buffers |
| Frame data in a texture | GPU time, one tiger | 5–8% faster than upstream |
| 2 frames in flight | Memory, against 3 frames | 19% less for the atlas pages, a third less for the mesh renderer's targets, at the same frame rate |
| One copy per upload | Upload of 300 animated tigers, median | 1.92 ms, against 5.69 ms with `Texture.overwrite` |
| Per-entry colour filters | 1000 components, each with its own Flame `ColorEffect` | 1 run, a 45.9 MB atlas and 0.28 ms of raster time, against 1000 runs, 1241.6 MB and 1.08 ms with each drawn as its own image |
| Mesh renderer, CPU | UI time, 100 SVGs, any SVG and zoom | 0.8–1.3 ms a frame, against 1.9–5.1 ms with the atlas renderer (11–13 ms with the tiger) |
| Mesh renderer, CPU | UI time, 300 tigers | 2.1 ms a frame, against 9.3–21.7 ms with the atlas renderer |
| Mesh renderer, memory | Peak, in the same runs | About 120 MB lower than with the atlas renderer |
| Mesh renderer, GPU | 100 overlapping invader SVGs, at zoom 1 | 1.37 ms of GPU time a frame, against 1.33 ms with the atlas renderer |
| Fragment shader for colour transforms | Fragment time, 100 copies of the example's `flame.svg`, which has 3 gradients | 2.73 ms, against 7.01 ms with one shader for both |
| Grid snap before libtess2 | Imports of the animated frames of one of the example's games | All 173,186 came back whole |
| Mesh targets that shrink | Memory in play, in a game from the example, in a 2880×1620 window (macOS, debug) | 60–68 MB, against 192.5 MB with targets that only grow |
| Canvas renderer's pictures | UI time, 1000 vectors | 2.10 ms a frame, against 4.06 ms when drawing the paths, for 5–10% more raster time |
| Pipelines compiled up front | GPU renderer, Android emulator's OpenGL ES (release, no shader cache) | 110 ms on the UI thread, then 50–90 ms on the raster thread |
| Pipelines compiled up front | GPU renderer, Mesa's llvmpipe (release, no shader cache) | 550 ms on the UI thread, then 150 ms on the raster thread |
| Shared hitbox polygons | Making one `SvgHitbox` | 0.002 ms, against 0.004–0.03 ms when Flame builds each hitbox's polygons, path and segments itself |
