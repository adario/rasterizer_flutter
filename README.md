# rasterizer_flutter

A Flutter port of [Rasterizer](https://github.com/mindbrix/Rasterizer), Nigel Timothy Barber's GPU vector renderer for
Apple platforms. It draws SVG files made of paths and basic shapes, and plain `dart:ui` paths. It also comes with an
integration for the [Flame](https://flame-engine.org) game engine.

The repository has two packages:

- **[rasterizer_gpu](rasterizer_gpu)** runs Rasterizer's C++ core through FFI. A Dart build hook compiles the core. The
  package has three renderers behind one API. Each frame groups its SVGs into runs: SVGs drawn one after another, with
  nothing else between them.
  - The atlas renderer (`RasterizerBackend.gpu`), the default, renders all of a frame's runs into one atlas with
    Flutter GPU. It then draws each run at its place in the app's paint order.
  - The mesh renderer (`RasterizerBackend.mesh`), for games, imports each SVG once into triangles that stay on the GPU.
    It draws them with instanced draws, so each frame only sends their transforms.
  - The canvas renderer (`RasterizerBackend.canvas`) draws with `dart:ui` wherever the other two can't, web included.
- **[flame_rasterizer](flame_rasterizer)** adds Flame components that rasterizer_gpu draws, with the mesh renderer by
  default. Each run of vector components becomes one image, sharp at any camera zoom.

The repository also has three apps:

- **[rasterizer_gpu/example](rasterizer_gpu/example)** shows an SVG to pan and zoom, runs an atlas benchmark, and holds
  rasterizer_gpu's golden tests.
- **[flame_rasterizer/example](flame_rasterizer/example)** is a Widgetbook of SVG examples and games, laid out like
  Flame's examples. A knob picks what draws them: one of flame_rasterizer's renderers, or flame_svg.
- **[flame_rasterizer/benchmark](flame_rasterizer/benchmark)** has a demo, a benchmark against flame_svg, and a
  correctness check.

**Status:** a prototype at version 0.0.1, not on pub.dev. Use it from this repository, as a git dependency. Its APIs may
still change.

## Platforms

| Platform | Renderer | Tested on |
|---|---|---|
| macOS | GPU, on Impeller's Metal | macOS 26.7, M1 Mac |
| iOS | GPU, on Impeller's Metal | iPhone 11 Pro (A13, iOS 26.7.2); iOS Simulator (iPhone 18 Pro, iOS 27.0) |
| Android, API 24+, arm64 and x86_64 | GPU on Vulkan and OpenGL ES; canvas below API 29, on Skia | Android Emulator: API 37 (arm64, host GPU through gfxstream) on Vulkan, OpenGL ES and Skia; API 28 on Skia |
| Linux | GPU on OpenGL ES, Linux's only backend | arm64 Docker container: Debian trixie, Mesa's llvmpipe on the CPU, on X11 (Xvfb) and on Wayland (weston) |
| Web | canvas | Headless Chrome, with CanvasKit and skwasm |
| Windows | GPU on OpenGL ES, through ANGLE, Windows' only backend | not run: built on GitHub's Windows runners |

GPU means either GPU renderer: the atlas renderer, rasterizer_gpu's default, or the mesh renderer, flame_rasterizer's
default. Both draw on the same platforms. On OpenGL ES, an app can turn them off with `RasterizerGpu.allowOpenGles`, and
the canvas renderer then draws.

On web, these tests ran: the canvas renderer's golden tests, against the `macos` set, and its opacity and edge tests;
flame_rasterizer's limits test and Flame check; and, with CanvasKit only, the renderers, collidable and multiple shapes
tests of flame_rasterizer's example.

The golden tests pass on macOS, on the iOS Simulator (against the `macos` set), on the iPhone, on the Android emulator
and on Linux. [TESTING.md](rasterizer_gpu/example/TESTING.md) describes the tests.

Not tested: other iPhone or iPad GPUs, physical Android devices, Linux on a hardware GPU (with Mesa's or NVIDIA's
drivers), and Windows. Flutter GPU has no timestamp queries, so GPU times come only from the Mac: from repeating a
frame's passes, and from Instruments' GPU traces. [DESIGN.md](DESIGN.md) explains why the packages are built as they
are, with the main measurements. Timings on the emulator say nothing about real devices.

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

pub then fetches rasterizer_gpu from the same commit.

flame_rasterizer depends on `flame: ^2.0.0-dev.1`, which only Flame's main branch has, as Flame 2.0 isn't on pub.dev
yet. So a game overrides `flame`, and `flame_svg` if it uses it, with Flame's repository, as this repository's root
`pubspec.yaml` does:

```yaml
dependency_overrides:
  flame:
    git:
      url: https://github.com/flame-engine/flame
      path: packages/flame
      ref: main
```

The app needs:

- **iOS and macOS:** `FLTEnableFlutterGPU` set to true in each platform's `Info.plist`.
- **Android:** API 24 or later. The package turns on Flutter GPU itself. The canvas renderer draws instead of the GPU
  renderers:
  - on 32-bit devices, which get no native code;
  - below API 29, where Flutter renders with Skia;
  - where Impeller picks OpenGL ES, if the app turns `RasterizerGpu.allowOpenGles` off. It's on by default, and the
    GPU renderers then draw on OpenGL ES from the first frame, as on Vulkan.

  The app's manifest can ask for Impeller's Vulkan backend, but only debug and profile builds read it. Release builds
  use the device's own backend. Below API 29, asking for a backend also turns on Impeller, which can't start there, so
  the app crashes at launch.
- **Linux:** Flutter GPU turned on in the app's runner, with `fl_dart_project_set_enable_flutter_gpu` in
  `linux/runner/my_application.cc`. This works in release builds too. Flutter's Linux embedder always renders with
  OpenGL ES, so the GPU renderers draw there unless the app turns `RasterizerGpu.allowOpenGles` off.
- **Windows:** Flutter GPU turned on in the app's runner, with `project.set_enable_flutter_gpu(true)` in
  `windows/runner/main.cpp`. Flutter's Windows embedder renders only with OpenGL ES, through ANGLE, so the GPU
  renderers draw there unless the app turns `RasterizerGpu.allowOpenGles` off. As for any Flutter Windows app, building
  needs Visual Studio's C++ workload: see Flutter's
  [Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
- **Integration tests, from a clean checkout or from the pub cache:** build the app once (`flutter build <platform>`)
  before `flutter test`. Otherwise `flutter test` checks the app's assets before rasterizer_gpu's build hook has written
  its shader bundle. `flutter run` and `flutter build` don't need this.

[rasterizer_gpu's README](rasterizer_gpu/README.md#app-setup) has the details.

## Use

[rasterizer_gpu's README](rasterizer_gpu/README.md#use) covers scenes, frames and runs.
[flame_rasterizer's](flame_rasterizer/README.md#use) covers `HasRasterizer`, `RasterizerSvg`, `RasterizerSvgComponent`,
`RasterizerPathComponent`, `RasterizerPolygonsComponent` and `SvgHitbox`.

## Differences from upstream

Upstream renders with Metal, on Apple platforms. [UPSTREAM.md](UPSTREAM.md) lists how this port differs: Flutter GPU
instead of Metal, the atlas and mesh renderers, the patches to the core, the platforms, what isn't ported, and how it's
tested.

## Repository

```
README.md, DESIGN.md, UPSTREAM.md, LICENSE, THIRD_PARTY_NOTICES.md
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

From the root, `melos analyze` and `melos format-check` check all five packages in the workspace. Activate melos first
with `dart pub global activate melos`, or run it from the workspace, as in `dart run melos analyze`. The examples'
READMEs cover the other platforms and options.

## Credits and licences

- This repository: MIT, © 2026 Dario Accornero (`LICENSE`).
- [Rasterizer](https://github.com/mindbrix/Rasterizer), by Nigel Timothy Barber: MIT. The core, `ra_frame.hpp`, the
  shaders and the draw loop are copied or ported from it.
- [NanoSVG](https://github.com/memononen/nanosvg), by Mikko Mononen: zlib. [xxHash](https://github.com/Cyan4973/xxHash),
  by Yann Collet: BSD 2-clause. Both come with Rasterizer's core.
- [libtess2](https://github.com/memononen/libtess2), Mikko Mononen's version of SGI's GLU tessellator, for the mesh
  renderer: SGI Free Software License B, version 2.0.
- [Flame](https://github.com/flame-engine/flame), by Blue Fire: MIT. rasterizer_gpu copies its contour sampler, for
  paths. The canvas renderer's `SvgPaths` is based on a class this repository's author wrote for flame_svg, which Flame
  didn't merge.
- Three of the SVGs in flame_rasterizer's example and rasterizer_gpu's tests, from [SVG Repo](https://www.svgrepo.com):
  CC0 1.0.
- The Ghostscript tiger, a test SVG in the examples and the benchmark: AGPL-3.0-or-later, separately licensed test data,
  not part of either package.

rasterizer_gpu's `LICENSE` includes the licences of the code it bundles. `THIRD_PARTY_NOTICES.md` has all their notices.
