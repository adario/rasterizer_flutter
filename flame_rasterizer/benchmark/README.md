# flame_rasterizer_benchmark

[flame_rasterizer](..)'s benchmark app: a demo, the benchmark, and a correctness check, on macOS, iOS, Android, Linux
and web. It generates its SVGs (`lib/layout.dart`), except for its one asset, `assets/tiger.svg`, which `SVG=tiger`
draws. On an iPhone, pick your development team in Xcode first (Runner ▸ Signing & Capabilities): the project has none.

It runs on Flame's main branch, flame 2.0.0-dev and flame_svg 3.0.0-dev, through the workspace's dependency overrides
(the root `pubspec.yaml`). So its baseline is flame_svg 3.0.0-dev.

## Runs

Below, `<device>` is `macos`, an iOS udid or `emulator-5554`.

- **`flutter run -d macos`** runs the demo, under a moving and zooming camera. Vector components draw in 3 runs, with
  sprites and text between them. There's also a clipped group, and painted components: some faded in and out with an
  `OpacityEffect`, some tinted, some with their hue turned by a `HueEffect`, some blurred, and 3 that share one paint.
  - `--dart-define=ENGINE=flame_svg` draws them with flame_svg instead.
  - The demo logs the sizes and bytes of rasterizer_gpu's atlas pages, or of the mesh renderer's run targets, when they
    change (`RASTERIZER_PAGES`).
- **`--dart-define=MODE=check`** runs the check. It draws the game, and the same frame composed with rasterizer_gpu's
  API, with transforms computed from the layout rather than by Flame. It reads both back, and logs
  `FLAME_RASTERIZER check PASS` or `FAIL`. `CHECK_TIME` picks the frame, and so the camera's zoom. Except on web, it
  saves both images to the temporary directory. In the composed frame:
  - the faded, tinted and hue-turned items draw in one run, with their tint and hue as color transforms, as the game
    folds them;
  - the other painted runs' entries are faded by their paint's opacity, then drawn plainly in a layer with the rest of
    their paint (the blur, and the paint that 3 items share).
- **`--dart-define=BACKEND=atlas`** draws with rasterizer_gpu's atlas renderer, which rasterizes the SVGs into an atlas
  each frame, rather than with the mesh renderer, flame_rasterizer's default, which draws them imported once into
  triangles.
- **`--dart-define=BACKEND=canvas`** draws with rasterizer_gpu's canvas renderer, even where its GPU renderers are
  supported. It draws each SVG as a picture, or its paths with `--dart-define=CANVAS_PICTURES=false`. On web, and on
  Android built with `IMPELLER_BACKEND=opengles`, the app picks the canvas renderer by itself.
  - On the Android emulator's Vulkan with the host GPU, the check hangs, as any frame of more than about 800 draws does
    there (see rasterizer_gpu's README). Use OpenGL ES, or start the emulator with `-gpu swiftshader_indirect`.
- **`flutter test integration_test/check_test.dart -d <device> [--dart-define=BACKEND=atlas|canvas]`** runs the check
  as a test, at 4 times, so at camera zooms from 0.5 to 1.6 times the zoom that fits the world.
- **`flutter test integration_test/limits_test.dart -d <device> [--dart-define=BACKEND=atlas|canvas]`** checks
  flame_rasterizer's README's Limits. It draws each case with vector components and with Flame's rectangles, and
  compares them: scale 0, mirrored, skewed, clipped, a fixed resolution, perspective, a snapshot, a post process, and
  the game off the pixel grid.
- **`flutter test integration_test/oversize_test.dart -d <device> [--dart-define=BACKEND=atlas]`** checks a game wider
  than its renderer takes (`maxViewportSize`), whose vectors render at a lower pixel ratio, to fit.
- **`python3 -I tool/bench.py <device> <output file>`** runs the benchmark, in profile mode. It runs each engine with
  100 and 1000 vector components, 0, 2 and 9 sprites between them (so 1, 3 and 10 runs), and an animated or fixed zoom.
  - `--backends mesh,atlas,canvas,canvas_paths` picks rasterizer_gpu's renderers.
  - `--paints 0,1` also benchmarks each case with each component fading at its own rate, so with its own opacity. That
    splits no runs, as flame_rasterizer fades each entry's paths.
  - `--paints 2` tints each component with a `ColorEffect` of its own color and rate, so a new color filter each
    frame. That splits no runs either, as flame_rasterizer filters each entry's paths.
  - `--svgs tiger` (`--dart-define=SVG=tiger`) draws the tiger, 301 paths, for every component, rather than 50 small
    generated SVGs. That makes many entries of one big scene, as the example's Svg Renderers does.
  - It runs `flutter` from the `PATH`. A run fails after `--timeout` seconds (900 by default), or once the app, which
    logs its progress every 60 frames, has logged nothing for `--stall` seconds (15). The run's line in the output file
    then says why, and the tool's last 30 lines go to `<output file>.fail<n>.txt`. On macOS, the tool first samples a
    stalled app into `<output file>.stall<n>.txt`, and it kills the app after each run.
- **`flutter run -d chrome`**, or **`flutter build web [--wasm]`**, runs the demo on web, or the check with
  `MODE=check`, with the canvas renderer.
  - There, and on Skia, the check allows 1 pixel in 800 over 8/255, rather than 1 in 10,000, as Skia antialiases edges
    analytically, so float rounding moves them by fractions of a pixel.
  - `flutter test` doesn't run integration tests on web. `check_test` and `limits_test` run there with
    `flutter drive`, through the repository's `tool/device_tests.py`, as the `web_flame_js` and `web_limits_js` steps of
    its `tool/matrix.py`, and their `_wasm` steps.
- **`python3 -I tool/web_check.py [js,wasm] [0.0,3.7,8.0,15.0]`** runs the check on web instead, at the test's 4 times,
  with CanvasKit (`js`) and skwasm (`wasm`). For each, it builds the app, serves it locally, and runs it in headless
  Chrome with the repository's `tool/web_shot.py`, in real time, until it logs its line. Screenshots go to
  `build/web_check/`. It needs Chrome: `CHROME_EXECUTABLE`, as for Flutter, or else its default macOS install.
- **Linux:** run it in the repository's `tool/linux/` container, on Mesa's llvmpipe, as `tool/linux/linux.py`
  describes.

## The benchmark's numbers

Each benchmark run logs one `FLAME_RASTERIZER bench` line, which `bench.py` writes to its output file. It has the median
and the 95th percentile, over `FRAMES` frames after 60 frames of warm-up, of:

- `render`, the game's `render` on the UI thread, which records the frame's commands, so it leaves out the GPU's work;
- `build`, Flutter's build phase, `render` included;
- `raster`, the raster thread's time, which encodes the frame for the GPU;
- `interval`, the time between the frames' vsyncs, which shows the frame rate.

With rasterizer_gpu, the line ends with the last frame's renderer, runs, entries, and atlas pages or mesh targets, and
with the renderer's own CPU, upload and encode times. Benchmark runs keep the demo's HUD: its text, laid out again every
0.5 s, is drawn each frame, after the vectors.

## Android and clean checkouts

The Android manifest asks for Impeller's Vulkan backend, as the emulator otherwise gets OpenGL ES. The
`IMPELLER_BACKEND` environment variable, read when building, can ask for another, such as `opengles`. Only debug and
profile builds read the manifest's key: a release build gets OpenGL ES on the emulator. Below API 29, build with
`IMPELLER_BACKEND=auto`. Flutter then renders with Skia, whereas a backend asked for forces Impeller, which crashes at
launch there.

From a clean checkout, build the app once (`flutter build macos`, `flutter build ios`, or
`flutter build apk --debug --target-platform android-arm64`) before `flutter test`. Otherwise `flutter test` checks the
assets before rasterizer_gpu's build hook has written its shader bundle.
