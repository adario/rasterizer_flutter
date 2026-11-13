# rasterizer_gpu_example

[rasterizer_gpu](..)'s example app, for macOS, iOS, Android, Linux and web. It shows an SVG to pan and zoom, and runs
the atlas benchmark. [TESTING.md](TESTING.md) describes its tests, the golden tests among them.

To run it on an iPhone, first pick your development team in Xcode (Runner ▸ Signing & Capabilities): the project has
none.

## Pages

Pick a page with `--dart-define=PAGE=...`:

- `svg`, the default, shows an SVG asset fitted to the page. Drag, pinch or scroll to pan and zoom it, and double tap
  to reset it. Its settings:
  - `SVG` names the asset. The default is `assets/tiger/tiger.svg`.
  - `CURVES=false` draws curves as line segments.
  - `GRID=n` draws the SVG n×n times.
  - `SLOTS=n` sets the renderer's frames in flight.
  - `SWEEP=true` runs the sweep, a 180-frame pan and zoom, and logs its timings (`RASTERIZER_SWEEP`).

  The page logs the atlas pages' sizes and `atlasBytes` whenever they change (`RASTERIZER_PAGES`).
- `atlas` runs the atlas benchmark: `ENTRIES` entries (1000 by default) of 50 generated SVGs, moving and spinning, in
  `RUNS` runs (4 by default). It logs its timings (`RASTERIZER_ATLAS`) after `FRAMES` frames (300 by default).

Timings mean something only in a profile build: `flutter run --profile -d macos --dart-define=PAGE=atlas`.

## Renderers

- Both pages draw with the atlas renderer where it's supported, as `RasterizerGpu.backend` says. `BACKEND=canvas`
  forces the canvas renderer. `BACKEND=mesh` picks the mesh renderer instead of the atlas renderer, where it's
  supported. The SVG page then flattens the SVG's curves for the window's size zoomed in 20×, as far as the sweep
  zooms.
- On OpenGL ES, the app sets `RasterizerGpu.allowOpenGles`. So the page draws with the canvas renderer until the
  self-test passes, then with the GPU renderer. The app logs:
  - the result, in a `RASTERIZER_EXAMPLE support` line;
  - the frames while the self-test ran, and for as long again after it, in a `RASTERIZER_EXAMPLE startup` line: the
    longest time between frames, how many missed a vsync, and the UI thread's longest stall;
  - in the meantime, `RASTERIZER_EXAMPLE event` lines: the first rasterized frame, lifecycle changes, stalls over
    250 ms, and the backend it settled on.

  `DEFER_FIRST_FRAME=n` defers the first frame by n seconds, as a splash screen would.
- On Android, the app leaves Impeller's backend to Flutter, which picks OpenGL ES on the emulator and on devices whose
  Vulkan can't work. A debug or profile build with `IMPELLER_BACKEND=vulkan` or `IMPELLER_BACKEND=opengles` asks for
  that backend, through the manifest; release builds ignore it. A backend asked for crashes at launch where it can't
  start: Vulkan on some older GPUs, and any backend below API 29, where Flutter renders with Skia. There, the canvas
  renderer draws.
- On Linux, Impeller renders with OpenGL ES. The app's runner turns Flutter GPU on in `linux/runner/my_application.cc`.
- On web, only the canvas renderer draws: `flutter run -d chrome`, or `flutter build web [--wasm]`.

`tiger.svg` and its renders are separately licensed: see `assets/tiger/README.md`.
