# rasterizer_gpu_example's tests

The example's integration tests run in the app: first the golden tests, then the others. Run the commands from this
folder, except those of the repository's `tool/`, which run from its root.

## Golden tests

```sh
flutter test integration_test/golden_test.dart -d macos                                      # Metal
flutter test integration_test/golden_test.dart -d <iOS udid>                                 # Metal, on an iOS Simulator or device
IMPELLER_BACKEND=vulkan flutter test integration_test/golden_test.dart -d emulator-5554      # Vulkan, on the Android emulator
IMPELLER_BACKEND=opengles flutter test integration_test/golden_test.dart -d emulator-5554    # OpenGL ES
flutter test integration_test/golden_test.dart -d linux                                      # OpenGL ES, in the Linux container (see below)
```

From a clean checkout, build the app once first, on any platform: `flutter build macos`, `flutter build ios` (with
`--simulator` for the Simulator), or `flutter build apk --debug --target-platform android-arm64`. Otherwise
`flutter test` checks the assets before rasterizer_gpu's build hook has written its shader bundle, and fails with "No
file or variants found for asset". `flutter run` and `flutter build` don't have this problem.

The tests run in the app, because `flutter_tester`'s Impeller doesn't render as the app does. It also runs Flutter GPU
on Metal, but its antialiasing differs from the app's in about 2% of pixels.

- **Cases** (`lib/goldens.dart`):
  - the tiger fitted, with and without curves, and the sweep's checkpoints, with and without curves;
  - the sweep of a 4×4 grid of tigers, with curves;
  - the atlas frame: 200 entries of the generated SVGs in 4 runs, many of them crossing the viewport's edges;
  - `gradients`, and `gradients_skewed`, the gradients that vector_graphics_compiler doesn't draw as SVG says;
  - `paths`: a scene of plain paths, 14 draws at their own size, and a shape 3 units wide at 40 px a unit, in one run
    (`lib/scenes.dart`).

  Each image is one run, as drawn into a 1024×768 px viewport, in `goldens/<platform>/<name>.png`.
  - The sets are `macos`, `ios` for devices, `android_emulator` (Vulkan), `android_emulator_gles`, and
    `linux_llvmpipe`: Mesa's CPU renderer in the repository's Linux container, which its image picks with
    `GALLIUM_DRIVER=llvmpipe`. An Android device would use `android`, and Linux on a GPU `linux`. Neither has goldens
    yet: record them as below, then list the folder in `pubspec.yaml`'s assets.
  - The iOS Simulator uses `macos`, as it renders with the Mac's GPU and matches it.
  - An iPhone's GPU rounds differently from the Mac's, by 1/255 on a few pixels, from the same core frames. So devices
    have their own set, recorded on an iPhone 11 Pro (A13).
  - The PNGs hold the raw premultiplied RGBA read back from the GPU, so they round-trip exactly. Viewers show
    translucent pixels slightly dark.
- **Tolerance:** an image passes when at most 1 pixel in 10,000 differs by over 2/255, at most 1% differs at all, and
  none differs by over 16/255. From one render to the next, the core can write a frame's edges in another order, which
  sums their coverage in another order too. That can change a few pixels by several 255ths, or hundreds by 1/255.
- **The canvas renderer** is tested against the same goldens, except two kinds: curves drawn as line segments
  (`_fast`), which it never draws, and `gradients_skewed` (see `../README.md`). It's tested wherever it runs, and the
  GPU renderer only where it's supported. `BACKEND=gpu` or `BACKEND=canvas` tests only that one. With
  `IMPELLER_BACKEND=opengles` on Android, the test waits for the self-test, and tests the GPU renderer once it passes.
  - Its tolerance is looser, as Impeller antialiases with 4x MSAA, and the core with exact coverage. Images are
    compared in 4×4 pixel blocks, which average edges out: at most 0.5% of blocks may differ by over 32/255, and 0.05%
    by over 64/255. In the first runs, antialiasing alone made at most 0.15% of blocks differ by over 32/255. Drawing
    curves as line segments, as a stand-in for a real difference, made 1.9% differ.
  - It writes its failures as `canvas_<name>.png`, and never writes goldens.
- **The mesh renderer** has its own goldens, `mesh_<name>.png` in the same folders, as its 4x MSAA edges aren't the
  core's exact coverage. Its cases are those with curves (it draws the same frames without them), the atlas frame, the
  gradients, `paths`, and three of its own:
  - `strokes`: its strips' joins and caps, and translucent strokes that overlap themselves, which must blend once,
    where the GPU renderer blends them twice;
  - `thin_strokes`: strokes thinner than its least width, drawn whole at that width, never dotted;
  - `glow`: strokes and fills with a `RasterizerGlow`, which only the mesh renderer draws.

  It's tested where it's supported. `BACKEND=mesh` tests only it, and `UPDATE_GOLDENS` writes its goldens too. Every
  set has them.
  - It flattens each SVG's curves for the largest size a case draws it at, its `maxSize`: the tiger's for the sweep's
    20× zoom. It fits the tiger by the GPU scene's bounds, the core's, which are looser than its triangles', so both
    renderers draw the same frames.
  - Its renders are checked against its own goldens with the GPU renderer's tolerance. They're also checked against
    the GPU goldens with the canvas renderer's tolerance, so that a golden it records can't hide a wrong shape or
    colour. When its goldens were first recorded, at most 32 of 49,152 blocks differed from the GPU goldens by over
    32/255, and 17 by over 64/255.
  - The exceptions are frames that show the tiger's outlines, about 0.14 of a pixel wide at its fit. The mesh renderer
    widens them to its least width, while the GPU renderer draws them as faint lines, so the two differ by more than
    the tolerance. The tiger's fitted frame, its sweep's frames 90 and 150, and the grid's frames but 59 are checked
    against the mesh goldens only.
  - It writes its failures as `mesh_<name>.png`, and the diffs of those against the GPU goldens as
    `mesh_<name>_vs_gpu_diff.png`.
- **Self-consistency:** each of the atlas frame's runs must match the same entries rendered as a frame of their own,
  with at most 1 pixel in 10,000 over 8/255. Nothing over 1/255 may be drawn outside the runs' rectangles.
- **Where the goldens came from:** the first goldens were checked against the original Metal renderer, given the same
  frames, before the GPU renderer replaced it. On Metal, they were off by at most 1/255, on at most 5 pixels a page. On
  the emulator's Vulkan, they were within 1–2/255, but for a few dozen isolated pixels in a frame with curves. Since the
  core's gradient patches (`../src/core/README.md`), the goldens of the atlas frame and the gradient cases stand for
  Chrome's renders of the same SVGs instead: within 26/255 on a pixel, at edges, and 6/255 in a 4×4 block. The
  emulator's and the iPhone's sets were checked against `macos`: within 1/255, but for the iPhone's tiger sweep frame
  119, with at most 141 pixels over 1/255, by up to 10/255. So a render that matches its golden still matches the
  original renderer, or Chrome's for gradients.
- **Updating the goldens** after an intended rendering change:
  1. Run the test with `--dart-define=UPDATE_GOLDENS=true`. On iOS and Android, add `--no-uninstall` too, so that the
     files survive the run.
  2. Run `python3 -I tool/pull_goldens.py macos | android <serial> | ios-simulator <udid> | ios <udid>`. It copies the
     renders into `goldens/<platform>/`, and a failed run's renders and diffs into `build/golden_failures/`.

  In the Linux container, runs don't keep `/tmp`. So point `TMPDIR` into `build/`, at a folder that already exists
  (an earlier run's `mkdir` will do), and copy the renders out with `linux.py pull`, from the repository's root:

  ```sh
  python3 -I tool/linux/linux.py run -C rasterizer_gpu/example env TMPDIR=/work/rasterizer_gpu/example/build/tmp \
    flutter test integration_test/golden_test.dart -d linux --dart-define=UPDATE_GOLDENS=true
  python3 -I tool/linux/linux.py pull rasterizer_gpu/example/build/tmp/goldens_rasterizer_gpu_example
  ```

  Then move `build/tmp/goldens_rasterizer_gpu_example/linux_llvmpipe/` into `goldens/`.

  With `GOLDEN_RECORD=true`, the test also writes each frame's atlas pages, core frames and lists, which
  `tool/pull_goldens.py` copies into `build/golden_record/`. `../tool/compare_frames.py` reads them, to tell the
  core's variation from one run to the next apart from a rendering change.

## Other tests

```sh
flutter test integration_test/self_test_test.dart -d <device>    # the OpenGL ES self-test, and its fallbacks
flutter test integration_test/switch_test.dart -d <device>       # canvas-first: the switch to the GPU renderer
flutter test integration_test/defer_test.dart -d <device>        # a deferred first frame
flutter test integration_test/atlas_test.dart -d <device>        # atlas pages shrinking after viewport changes
flutter test integration_test/mesh_test.dart -d <device>         # the mesh renderer's draws, paints and targets
flutter test integration_test/projective_test.dart -d <device>   # perspective, with each renderer
flutter test integration_test/opacity_test.dart -d <device>      # entries' opacities, with each renderer
flutter test integration_test/edge_test.dart -d <device>         # entries near a run's edges, with each renderer
flutter test integration_test/run_paint_test.dart -d <device>    # a GPU run's paint, and entries' color transforms
flutter test integration_test/upload_test.dart -d <device>       # the GPU renderer's upload buffers growing, shrinking
```

`mesh_test` checks the mesh renderer through its API, read back through a canvas: paint order, instances with their
opacities and tints, opaque meshes drawn without blending, gradients against their formulas, holes, strokes, 32-bit
indices, multisampled edges with 4 samples and aliased ones with 1, and its run targets. `self_test_test`,
`switch_test` and `opacity_test` test the mesh renderer too.

`atlas_test` turns the viewport between portrait and landscape every 150 frames, while heavy frames, which spill onto a
second page, alternate with light ones. It compares the frames around each shrink with a fresh renderer's. It also
checks that the pages shrink back, are released when unused, and are trimmed.

On OpenGL ES (`IMPELLER_BACKEND=opengles` on the emulator), the tests check:

- `RasterizerGpu.initialize`, and its fallbacks to `r16g16b16a16Float` and to the canvas renderer;
- that scenes and renderers made without a backend draw with the canvas renderer until the self-test passes, then
  switch, and render as a plain GPU renderer does;
- the same of the mesh renderer's own self-test, in its own file;
- that the self-test waits while the app is in the background, and that the first-frame wait lasts as long as the
  first frame is deferred, past their timeouts.

Elsewhere, they check the self-test itself, and that nothing switches. `self_test_test` and `switch_test` also check
what the self-test remembers across launches (`RasterizerGpu.rememberSelfTest`), and `self_test_test` its probation
after the switch.

To run them all, with the goldens, on the emulator's Vulkan and OpenGL ES, on macOS and on web, run
`python3 -I tool/matrix.py > matrix.txt` from the repository's root, in the background. Follow it with
`python3 -I tool/follow.py matrix.txt 'STALL|FAIL|passed|failed|FINISHED' FINISHED`. Each `flutter test` runs under a
watchdog (`tool/device_tests.py`), which kills a run that's silent for 2 minutes, as a GPU app hung on the emulator
would be. It keeps each run's output in the repository's `build/test_logs/`.

This app's `tool/release_launches.py [build]` checks the crash guard. It launches a release build's atlas page, which
renders every frame, on the emulator with adb. It kills the app during the self-test, during the probation after the
switch, and after the probation, in the foreground and in the background.

On web, `flutter test` doesn't run integration tests. `tool/device_tests.py`'s `chrome` device runs them in headless
Chrome, with `flutter drive` and the app's `test_driver/integration_test.dart`. For example,
`python3 -I tool/matrix.py web_goldens_js web_goldens_wasm` runs the golden tests with CanvasKit and with skwasm.

- This example's web steps in the matrix are the golden tests, which test the canvas renderer against the `macos` set,
  `opacity_test` and `edge_test`.
- They need Chrome for Testing's chromedriver for the installed Chrome's version, unzipped into the repository's
  `build/chromedriver/` (on an Apple silicon Mac, `chromedriver-mac-arm64/chromedriver`).
- flutter drive reports only widget tests' failures there: a plain `test` that fails passes. So the tests that run on
  web use `testWidgets` there (`integration_test/web_test.dart`).
- The tests' lines, and the golden tests' failing images, go to flutter drive's response data. The tool saves it as
  the repository's `build/test_logs/<step>.json`, and the images into `build/test_logs/<step>/`.

In the Linux container (`tool/linux/`, at the repository's root, with Docker), the same tests run with `-d linux`, on
Impeller's OpenGL ES, on Mesa's llvmpipe. For example:

```sh
python3 -I tool/linux/linux.py run -C rasterizer_gpu/example flutter test integration_test/self_test_test.dart -d linux
```

The self-test's file is then in the container's `~/.cache`, which a run doesn't keep. To keep it across launches, as
the crash guard's kill tests need, set `XDG_CACHE_HOME` into `build/`. The app's `linux/` runner was generated in the
container, as the Mac's Flutter doesn't build for Linux, and turns Flutter GPU on in `linux/runner/my_application.cc`.

`tiger.svg` and its renders are separately licensed: see `assets/tiger/README.md`.
