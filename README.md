# rasterizer_flutter

A Flutter port of [Rasterizer](https://github.com/mindbrix/Rasterizer), Nigel Timothy Barber's GPU vector renderer for
Apple platforms. It draws SVG files made of paths and basic shapes, and plain `dart:ui` paths, and comes with an
integration for the [Flame](https://flame-engine.org) game engine.

The repository has two packages:

- **[rasterizer_gpu](rasterizer_gpu)** runs Rasterizer's C++ core through FFI, built by a Dart build hook. It has three
  renderers behind one API:
  - the atlas renderer, its default, renders all of a frame's SVGs into one atlas with Flutter GPU, then draws each run
    of them at its place in the app's paint order;
  - the mesh renderer, for games, imports each SVG once into triangles that stay on the GPU, and draws them instanced,
    so that each frame only sends their transforms;
  - the canvas renderer draws with `dart:ui` wherever Flutter GPU can't, web included.
- **[flame_rasterizer](flame_rasterizer)** adds Flame components drawn by rasterizer_gpu, with the mesh renderer by
  default. Each contiguous run of vector components is drawn as one image, sharp at any camera zoom.

Each package has an example app:

- **[rasterizer_gpu/example](rasterizer_gpu/example)** holds rasterizer_gpu's golden tests.
- **[flame_rasterizer/example](flame_rasterizer/example)** is a Widgetbook, laid out like Flame's examples, of games
  drawn by flame_rasterizer or by flame_svg, switched with a knob.
- **[flame_rasterizer/benchmark](flame_rasterizer/benchmark)** has a demo, a benchmark against flame_svg, and a check.

**Status:** a prototype at version 0.0.1, not on pub.dev. Use it from this repository, as a git dependency. Its APIs may
still change.

## Platforms

| Platform | Renderer | Tested on |
|---|---|---|
| macOS | GPU, on Impeller's Metal | macOS 26.7, M1 Mac |
| iOS | GPU, on Impeller's Metal | iPhone 11 Pro (A13, iOS 26.7.2); iOS Simulator (iPhone 18 Pro, iOS 27.0) |
| Android, API 24+, arm64 and x86_64 | GPU on Vulkan; canvas on OpenGL ES unless the app opts in; canvas below API 29, on Skia | Android Emulator: API 37 (arm64, host GPU through gfxstream) on Vulkan, OpenGL ES and Skia; API 28 on Skia |
| Linux | canvas on OpenGL ES, Linux's only backend, unless the app opts in | arm64 Docker container: Debian trixie, Mesa's llvmpipe on the CPU, Xvfb |
| Web | canvas | Headless Chrome, with CanvasKit and skwasm |
| Windows | canvas | not built: no machine |

GPU means either GPU renderer: the atlas renderer, rasterizer_gpu's default, or the mesh renderer, flame_rasterizer's.
Both draw on the same platforms. On OpenGL ES, an app that opts in gets the canvas renderer until the GPU renderer's
self-test passes.

On web, these tests ran: the canvas renderer's golden tests, against the `macos` set, and its opacity test;
flame_rasterizer's limits test and Flame check; and, on CanvasKit only, the example's renderers, collidable and
multiple shapes tests.

The golden tests pass on macOS, on the iOS Simulator, which uses the `macos` set, on the iPhone, on the Android emulator
and on Linux. See `rasterizer_gpu/example/TESTING.md`.

Not tested: other iPhone or iPad GPUs, physical Android devices, Linux on a GPU (Mesa's drivers or NVIDIA's), and
Windows. Flutter GPU has no timestamp queries, so GPU times were measured only on the Mac, by repeating a frame's passes
and with Instruments' GPU traces. [DESIGN.md](DESIGN.md) has the main timings, and why the packages are built as they
are. The emulator's timings say nothing about real devices.

## Setup

Use Flutter 3.47.9 or later. Depend on the packages through git, at a release tag such as `v0.0.1`. Each tag covers
both packages:

```yaml
dependencies:
  flame_rasterizer:            # or rasterizer_gpu alone, with path: rasterizer_gpu
    git:
      url: https://github.com/adario/rasterizer_flutter.git
      path: flame_rasterizer
      ref: v0.0.1
```

pub fetches rasterizer_gpu from the same commit.

flame_rasterizer depends on `flame: ^2.0.0-dev.1`, which is Flame's main branch. A game therefore overrides `flame`, and
`flame_svg` if it uses it, with Flame's repository, as this repository's root `pubspec.yaml` does:

```yaml
dependency_overrides:
  flame:
    git:
      url: https://github.com/flame-engine/flame
      path: packages/flame
      ref: main
```

The app needs:

- **iOS and macOS:** `FLTEnableFlutterGPU` set to true in each `Info.plist`.
- **Android:** API 24 or later. The package turns on Flutter GPU itself. The canvas renderer draws instead of the GPU
  renderers:
  - on 32-bit devices, which get no native code;
  - below API 29, where Flutter renders with Skia;
  - where Impeller picks OpenGL ES, unless the app sets `RasterizerGpu.allowOpenGles`. Then the canvas renderer draws
    from the first frame, and the GPU renderer takes over once its self-test passes, a few seconds in.

  The app's manifest can ask for Impeller's Vulkan backend, but only debug and profile builds read it: release builds
  use the device's own backend. Asking for a backend also forces Impeller below API 29, where it can't start, so the app
  crashes at launch there.
- **Linux:** Flutter GPU turned on in the app's runner, with `fl_dart_project_set_enable_flutter_gpu` in
  `linux/runner/my_application.cc`. Release builds honour it too. Flutter's Linux embedder always renders with OpenGL
  ES, so the canvas renderer draws unless the app sets `RasterizerGpu.allowOpenGles`, as on Android.
- **Integration tests, from a clean checkout or the pub cache:** one build of the app (`flutter build <platform>`)
  before `flutter test`. Otherwise `flutter test` checks the assets before rasterizer_gpu's build hook has written its
  shader bundle. `flutter run` and `flutter build` don't need it.

[rasterizer_gpu's README](rasterizer_gpu/README.md#app-setup) has the details.

## Use

[rasterizer_gpu's README](rasterizer_gpu/README.md#use) covers scenes, frames and runs.
[flame_rasterizer's](flame_rasterizer/README.md#use) covers `HasRasterizer`, `RasterizerSvg`, `RasterizerSvgComponent`
and `RasterizerPathComponent`.

## Differences from upstream

Upstream renders with Metal, on Apple platforms, from Swift or Objective-C. This port:

- **Renders with Flutter GPU and GLSL**, instead of Metal. The build hook compiles upstream's `Shaders.metal`, ported to
  GLSL, into a shader bundle. Instead of Metal buffers, each frame is copied once into a host-visible buffer, blitted
  into an `r32g32b32a32Float` data texture, and read with `texelFetch`.
- **Renders into an atlas.** All of a frame's runs are rendered once, into atlas pages. Each run is then drawn with
  `Canvas.drawImageRect` at its place in the paint order, so vector content keeps its z-order among other content.
- **Patches the core** (see `rasterizer_gpu/src/core/README.md`):
  - for portability off Apple platforms: `std::thread` and other replacements for GCD and Apple-only calls;
  - device clips: a device-pixel rectangle per scene, with its soft clip, for the atlas;
  - NanoSVG's viewBox, which it otherwise drops;
  - NanoSVG's bounding box gradients and gradient opacity, drawn as SVG and Chrome draw them. Upstream paints most
    bounding box gradients in their last stop's colour, and gradient shapes opaque.
- **Works around two render pass bugs in Impeller's Vulkan backend:** a texture's first render pass is reused for its
  later ones, and depth never survives a pass. So targets are cleared by drawing, and opaque paths redraw their depth in
  each later pass.
- **Runs the GPU renderers on Metal and Android's Vulkan**, and on Android's and Linux's OpenGL ES if the app opts in
  and a self-test passes. 32-bit ARM isn't supported. Elsewhere, on Skia, web and Windows, the canvas renderer draws. It
  parses SVGs in Dart with vector_graphics_compiler, through a trimmed copy of `SvgPaths`, a class written for
  flame_svg.
- **Has known differences in the canvas renderer**, from vector_graphics_compiler. On shapes that aren't square,
  diagonal or rotated bounding box linear gradients keep their bands perpendicular to the gradient. `skewX` and `skewY`
  angles are read as radians. Its antialiasing is Impeller's or Skia's, not the core's exact coverage.
- **Doesn't port** clip masks, blend modes, images, text, PDF, or the draw-editing API.
- **Adds a mesh renderer**, flame_rasterizer's default. It flattens each SVG once, for the largest size it's drawn at,
  triangulates its fills and stroke outlines with libtess2, and draws them 4× multisampled by default. So a frame's CPU
  work doesn't depend on the SVGs' paths, whereas upstream works out most paths again each frame, in device space.
- **Adds a Flame integration**, flame_rasterizer.
- **Tests with generated scenes and per-platform goldens**, rather than by comparing with upstream's renderer. The
  goldens were checked against upstream's Metal renderer, given the same frames, then against Chrome for the gradient
  patches. Upstream's Metal renderer isn't in this repository.

## Repository

```
README.md, DESIGN.md, LICENSE, THIRD_PARTY_NOTICES.md
pubspec.yaml             the pub workspace of the five packages, with melos
rasterizer_gpu/          the renderer package, its example app with the golden tests, and its tools
flame_rasterizer/        the Flame package, its example (a Widgetbook) and its benchmark app: demo, benchmark and check
tool/                    scripts that run the integration tests across devices, and the Linux container
```

## Checks

```sh
cd rasterizer_gpu && flutter test                     # the core through FFI, and the canvas renderer's SVG import
cd rasterizer_gpu/example && flutter test integration_test/golden_test.dart -d macos
cd flame_rasterizer/benchmark && flutter test integration_test/check_test.dart -d macos
cd flame_rasterizer/example && flutter test           # the Widgetbook, its knobs and games, off Impeller
cd flame_rasterizer/example && flutter test integration_test/renderers_test.dart -d macos
```

From the root, `melos analyze` and `melos format-check` check the workspace's five packages, with melos activated
(`dart pub global activate melos`). The examples' READMEs cover the other platforms and options.

## Credits and licences

- This repository: MIT, © 2026 Dario Accornero (`LICENSE`).
- [Rasterizer](https://github.com/mindbrix/Rasterizer), by Nigel Timothy Barber: MIT. The core, `ra_frame.hpp`, the
  shaders and the draw loop are copied or ported from it.
- [NanoSVG](https://github.com/memononen/nanosvg), by Mikko Mononen: zlib. [xxHash](https://github.com/Cyan4973/xxHash),
  by Yann Collet: BSD 2-clause. Both as copied into Rasterizer's core.
- [libtess2](https://github.com/memononen/libtess2), Mikko Mononen's version of SGI's GLU tessellator, for the mesh
  renderer: SGI Free Software License B, version 2.0.
- [Flame](https://github.com/flame-engine/flame), by Blue Fire: MIT. Its contour sampler is copied, for paths. The
  canvas renderer's `SvgPaths` is based on a class this repository's author wrote for flame_svg, which Flame didn't
  merge.
- Three of the SVGs in flame_rasterizer's example and rasterizer_gpu's tests, from [SVG Repo](https://www.svgrepo.com):
  CC0 1.0.
- The Ghostscript tiger, rasterizer_gpu's example's test SVG: AGPL-3.0-or-later, separately licensed test data, not part
  of either package.

rasterizer_gpu's `LICENSE` includes the licences of the code it bundles. `THIRD_PARTY_NOTICES.md` has all their notices.
