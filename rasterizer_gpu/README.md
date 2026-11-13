# rasterizer_gpu

Renders SVG scenes, and scenes of plain `dart:ui` paths (see [Paths](#paths)), with one of three renderers behind the
same API:

- **The GPU renderer**, also called the atlas renderer, runs Rasterizer's C++ core with Flutter GPU. It draws on
  Impeller's Metal backend (iOS, macOS) and Vulkan backend (Android). On Impeller's OpenGL ES backend (Android, Linux),
  it draws only for apps that opt in, once a self-test passes: see [OpenGL ES](#opengl-es). Once per frame, it renders
  all of the frame's runs of scenes into one atlas image. It then draws each run from its parts' rectangles with
  `Canvas.drawImageRect`, at the run's place in the app's paint order, so vector content keeps its z-order among other
  content.
- **The mesh renderer**, for games, draws wherever the GPU renderer does. It imports each SVG once into triangles, which
  stay in GPU buffers. Each frame then only writes its entries' transforms, and renders each run into an image of its
  own with instanced draws, 4× multisampled by default. See [The mesh renderer](#the-mesh-renderer).
- **The canvas renderer** is the fallback everywhere else: on Skia, Windows and web, and on Impeller's OpenGL ES unless
  the app opted in and the self-test passed. It parses scenes in Dart, and each run draws its scenes' paths with
  `Canvas.drawPath`, straight into the canvas it's drawn into. See [The canvas renderer](#the-canvas-renderer).

`RasterizerGpu.backend` is the GPU renderer where `RasterizerGpu.support` is `supported`, and the canvas renderer
otherwise. `RasterizerGpu.of(RasterizerBackend.mesh)` has the same members for the mesh renderer, which has its own
support, self-test and switch: its `backend` is `mesh` where it's supported, and `canvas` otherwise.

## Tested on

- macOS 26.7, on an M1 Mac.
- The iOS Simulator (iPhone 18 Pro, iOS 27.0).
- An iPhone 11 Pro (A13, iOS 26.7.2).
- The Android Emulator (API 37, arm64, with the Mac's GPU through gfxstream), on Impeller's Vulkan and OpenGL ES
  backends and on Skia; and API 28, where Flutter renders with Skia.
- Linux arm64 in a Docker container (the repository's `tool/linux/`): Debian trixie, with Mesa's llvmpipe, which renders
  on the CPU, on Xvfb. It uses Impeller's OpenGL ES backend, the only one Flutter's Linux embedder has.

On each, the example's golden tests pass with the GPU and canvas renderers:

- The iPhone's set matches macOS's within 1/255, except for the tiger sweep's frame 119, where at most 141 pixels
  differ, by up to 10/255. The emulator's Vulkan and OpenGL ES sets match macOS's within 1/255.
- On the iPhone and the iOS Simulator, the atlas, self-test and switch tests pass too.
- In the Linux container, the self-test, switch, defer and atlas tests pass on the GPU renderer, and so does the crash
  guard, tested with `kill -9`.
- On web, in headless Chrome with CanvasKit and with skwasm, the canvas renderer's golden tests pass against the
  `macos` set, and so does the opacity test.
- On Skia (`--no-enable-impeller`, or API 28), on macOS and the emulators, the canvas renderer's golden tests and the
  switch and opacity tests pass.

Not tested: other iPhone or iPad GPUs, physical Android devices, Linux on a GPU (Mesa's drivers or NVIDIA's), and
Windows.

The mesh renderer passes its own tests (`mesh_test`, `projective_test`, the self-test and switch tests, and the opacity
test) on macOS, on the iOS Simulator, in the Linux container, and on the emulator's Vulkan and OpenGL ES. On the
emulator's OpenGL ES, its self-test passes 4× multisampled. On the iPhone, its golden, mesh, opacity and projective
tests pass too, and on the iOS Simulator its golden tests pass against the `macos` set. Its goldens are recorded on
macOS, the iPhone, the emulator, and in the Linux container, where it draws on llvmpipe.

On the emulator's Vulkan with the Mac's GPU, Impeller can't draw a frame of more than about 800 draws, with or without
this package. The emulator reports a full descriptor pool as `ErrorFragmentedPool`. Impeller, as of Flutter 3.47.9,
doesn't replace the pool on that error, as it does on `ErrorOutOfPoolMemory`, so the app hangs or crashes. The canvas
renderer, which draws each path, reaches that limit with a few hundred SVGs. To test it there, use OpenGL ES, or the
emulator's software GPU (`emulator -avd <name> -gpu swiftshader_indirect`), whose Vulkan reports the full pool.

## App setup

- **iOS and macOS:** turn on Flutter GPU in the app's `Info.plist`, as a plugin can't:

  ```xml
  <key>FLTEnableFlutterGPU</key>
  <true/>
  ```

- **Android:** API 24 or later, and 64-bit. This package's manifest turns on Flutter GPU. The canvas renderer draws:
  - on 32-bit devices, which get no native code;
  - below API 29, where Flutter renders with Skia, without Impeller;
  - on OpenGL ES, unless the app opts in ([OpenGL ES](#opengl-es)).

  Impeller picks its backend itself: Vulkan where it can, else OpenGL ES. As of Flutter 3.47.9, Android uses OpenGL ES
  on emulators, on Adreno 650 and older GPUs, on older MediaTek, Exynos and PowerVR devices, on Huawei devices, and
  wherever a Vulkan 1.1 context can't be created. In debug and profile builds only, the app's manifest can ask for a
  backend, inside `<application>`, such as Vulkan to test on the emulator:

  ```xml
  <meta-data android:name="io.flutter.embedding.android.ImpellerBackend" android:value="vulkan" />
  ```

  Release builds ignore this key, and use the device's own backend. Debug and profile builds that set it get Impeller
  below API 29 too, where it can't start, so the app crashes at launch (`Could not create surface from invalid Android
  context`). Leave it out of builds that run there.

- **Linux:** turn on Flutter GPU in the app's runner, `linux/runner/my_application.cc`, where it makes its project:

  ```c
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_enable_flutter_gpu(project, TRUE);
  ```

  This works in release builds too, unlike the `FLUTTER_ENGINE_SWITCHES` environment variable. Flutter's Linux embedder
  always renders with OpenGL ES, so the GPU renderer only draws if the app opts in ([OpenGL ES](#opengl-es)), and the
  canvas renderer draws otherwise. The build hook builds the core with the clang that Flutter's Linux builds need,
  linked to the system's libstdc++. The app then runs on systems whose libstdc++ is as new as the build machine's, or
  newer, so build it on the oldest distribution it supports.

- **Web and Windows:** nothing to set up. Only the canvas renderer draws there, and the build hook builds no native
  code.

## Use

```dart
final renderer = await RasterizerRenderer.create(slots: 3);   // for RasterizerGpu.backend: gpu or canvas
final coin = RasterizerScene.fromSvg(bytes);       // parsed for the same backend; shared by any number of entries

// Once per frame, in device pixels, y down
final frame = renderer.beginFrame(widthPx, heightPx);
final background = frame.addRun()..add(coin, a, b, c, d, tx, ty)..add(coin, a2, b2, c2, d2, tx2, ty2);
final foreground = frame.addRun()..addMatrix(coin, matrix);
frame.render();                                    // one core render, upload and GPU submit per atlas page

// While painting, in order, with sprites in between
background.draw(canvas, scale: devicePixelRatio);
foreground.draw(canvas, scale: devicePixelRatio);
```

- **Entries:** an entry's transform maps its SVG's coordinates, y down, to the viewport's device pixels. Entries in one
  run overlap in the order they were added. Runs are drawn separately.
- **Opacity:** `add` and `addMatrix` take an `opacity`, 1 by default. It scales the alpha of each of the entry's paths,
  gradients included, so the SVG's overlapping paths show through each other. Entries with different opacities share a
  run. An entry whose opacity is 0 isn't added.
- **Color transforms:** `add` and `addMatrix` also take a `colorTransform`, a color filter applied to each of the
  entry's paths. It gives the same pixels as a layer with that filter around the entry, but entries with different
  ones share a run.
  - `RasterizerColorTransform.mode(color, mode)` and `.matrix(values)` make one, with its `ui.ColorFilter` in
    `filter`. They take `srcATop` (a tint), `dst` or `clear` with an sRGB color, and matrices whose alpha row is
    (0, 0, 0, 1, 0) and whose color rows' alpha column is 0: greyscale, sepia, hue rotations, saturation and offsets.
    They return null for other filters.
  - Filters that change alpha, such as `modulate`, `srcIn`, `dstIn` or `dstOut`, would let overlapping paths show
    through each other, as an opacity does, and other filters aren't linear. Those go on `draw`'s paint instead, one
    run each.
  - `RasterizerColorTransform.of(filter)` finds the transform that made a filter. It finds nothing for a filter made
    otherwise, even an equal one, as a `ui.ColorFilter`'s fields are private, and profile and release builds strip
    dart:ui's `toString()`.
  - A matrix's results are clamped per path rather than per pixel. That differs where paths that it takes out of range
    overlap translucently, antialiased edges between paths included. A hue rotation of 2 radians differs by up to
    40/255 on a few hundred edge pixels of a 40 px SVG, and sepia by up to 8/255 on 20 pixels. Tints are exact.
- **Paints:** `draw(canvas, paint: …)` applies the paint to the run as a whole, as to an image. The GPU renderer draws
  its parts' images with it, and the canvas renderer draws its paths in a layer with it. The GPU renderer still uses a
  layer in three cases: on Linux's OpenGL ES, for an image or mask filter (which is unbounded), and for a blend mode
  that changes what's under transparent pixels, such as `srcIn`, across several parts. A color filter that colors
  transparent pixels, such as a `srcOver` mode, colors each part's rectangle rather than the run's bounds.
- **Slots:** a frame's images are valid until `slots` frames later, when their textures are rendered into again.
- **Parts:** a run is drawn from its parts (`run.parts`). Entries whose bounds, grown by a 2 px margin, overlap in a
  chain share a part, made of their bounds within the viewport. Entries apart are in separate parts. So a run of
  entries scattered over the screen takes only their area of the atlas, and a run that covers the screen takes a
  screen's. Parts are packed on shelves about as wide as their area is square. Pages are up to 8192 px a side, or 4096
  on OpenGL ES. Parts that don't fit spill onto further pages, each another render.
- **Page sizes:** pages grow at once to a frame's needs. Every 120 frames, each page shrinks to the largest those frames
  needed, if that's below half its area. If the viewport changed size in those frames, as with a rotation or a window
  resize, it shrinks to that whatever it is. So a page shrinks at most once in 120 frames, and pages that no frame
  needed for 120 frames are released. Steady scenes and games rarely reallocate them, and a turned phone or a resized
  window gives back what the larger size took. With 3 `slots`, each page holds about 21 bytes a pixel, or 20 on OpenGL
  ES. `renderer.atlasBytes` gives the estimate, from the textures' formats. `renderer.trimAtlas()` shrinks pages to the
  last frame's needs and releases the rest at once. Call it when the app knows its frames got lighter, such as at a
  level change.
- **Disposing:** don't dispose of a scene between `add` and `render`, nor before a canvas run that draws it is drawn.
- **Backends:** a scene is parsed for one backend, and only that backend's renderers can draw it. `fromSvg` and
  `create` both default to `RasterizerGpu.backend`. Both take a `backend`, or a `gpu` whose choice they default to
  instead. With `gpu: RasterizerBackend.mesh`, that's the mesh renderer where it's supported, else the canvas renderer.
  A mesh scene needs a `maxSize`, whichever renderer is chosen (see [The mesh renderer](#the-mesh-renderer)). A scene
  of paths always needs one (see [Paths](#paths)).
- **Perspective:** `RasterizerRun.addProjective(scene, a, b, c, d, tx, ty, g, h, i)` adds an entry under a perspective,
  whose w is g x + h y + i, as `addMatrix` does with a `Matrix4`'s w row. The mesh and canvas renderers draw it
  exactly. The GPU renderer only takes a w that's the same everywhere, with g and h 0, and throws otherwise.
- **Rectangles:** a scene's `viewBox` is the SVG's own rectangle, in its paths' coordinates: its viewBox, or else its
  width and height. The core doesn't scale the paths to the width and height. `bounds` is the paths' bounds. `rect` is
  the rectangle the scene is drawn from, such as to fit it to a size: its `viewBox`, or its `bounds` for an SVG with
  neither a viewBox nor a size.
- **Drawing a scene directly:** `scene.drawPaths(canvas)` draws a canvas scene's paths into any canvas, such as a
  picture's, under any transform, with no frame or renderer. It throws for scenes of the other backends.
- **Outlines:** `SvgOutline.fromSvg(bytes)` gives an SVG's paths as one `dart:ui` `Path`, for hitboxes. It's parsed in
  Dart whatever the backend, in the SVG's coordinates. Filled paths have their contours closed, and stroked-only ones
  stay as they are. Its `rect` is the rectangle it's drawn from, as a scene's is.

To draw runs while painting, before the frame has rendered, as when each run must be drawn as it ends, place each run as
it ends, then render the frame before the painting is rasterized:

```dart
final frame = renderer.beginFrame(widthPx, heightPx);
final run = frame.addRun()..add(coin, a, b, c, d, tx, ty);
run.place();                                       // its parts are set now
run.draw(canvas, scale: devicePixelRatio);
// ... more runs, each placed as it ends
frame.render();                                    // before Flutter rasterizes the picture
```

Placed runs go onto atlas pages sized as earlier frames' runs needed, packed together, so a steady scene settles on the
same pages. A part that doesn't fit on a page goes to the next one, which is another render. A page that no earlier
frame sized is at least the viewport's size, until the next 120 frames shrink it.

`RasterizerCanvas` does this for a whole painting. It wraps a canvas for one frame: scenes drawn one after another with
`drawScene` make up a run, and everything else is drawn straight into the wrapped canvas. A run ends when anything else
is drawn, when the clip changes, or when a scene is drawn with another paint. Transforms don't end runs, as each entry
has its own. flame_rasterizer's `HasRasterizer` draws a game through it.

```dart
final frame = renderer.beginFrame(widthPx, heightPx);
rasterizerCanvas.begin(canvas, frame, devicePixelRatio);
rasterizerCanvas.drawScene(coin, 1, 0, 0, 1, x, y);
rasterizerCanvas.drawRect(rect, paint);            // ends the run
rasterizerCanvas.drawScene(coin, 1, 0, 0, 1, x2, y2);
rasterizerCanvas.end();
frame.render();
```

## Paths

A scene can also be made of plain `dart:ui` paths, each with its paint, in paint order, such as shapes built in code.
It's drawn as an SVG's scene is, with the same entries and runs:

```dart
final star = RasterizerScene.fromPaths([
  (path, Paint()..color = const Color(0xffffc107)),
  (path, Paint()..color = const Color(0xffff6f00)..style = PaintingStyle.stroke..strokeWidth = 4),
], maxSize: 128 * devicePixelRatio);
```

- **Drawn as SVG draws them:** a fill fills its path with the path's `fillType`, with open contours closed. A stroke
  strokes its path with its width, cap, join and miter limit, with open contours left open. The scene's coordinates are
  the paths', x right and y down. Its `viewBox` is their bounds without their strokes, and its `bounds` include half
  their strokes' widths. A mesh scene's `bounds` are its triangles'.
- **Imported once:** a `ui.Path` doesn't expose its commands, so the GPU renderers read its contours back with
  `computeMetrics`. They flatten them into polylines with a copy of Flame's contour sampler, to within 1/4 of a device
  pixel when the `viewBox`'s longer side, or the widest stroke if it's wider, spans `maxSize` device pixels. The
  tolerance is never finer than 16 float steps of the paths' farthest coordinate: finer, a tiny path's mesh could take
  seconds to tessellate, or never finish.
  - So `maxSize` is required, even for the atlas renderer, which draws an SVG's curves as curves.
  - A path counts as immutable: changing one after the import gives undefined results. The GPU renderers keep drawing
    it as it was. The canvas renderer, which draws the paths themselves, draws it as it was when it recorded it as a
    picture, or else as it is.
  - A path keeps its contours while it lives, so another scene of it with the same tolerance, such as one with other
    paints, doesn't flatten it again.
  - Flattening takes about 4 tangent lookups a vertex: at most 17 ms for the tiger's 301 paths, in a debug build.
- **Paints:** `RasterizerScene.canDraw(paint)` says whether the GPU renderers can draw a paint. They draw a fill, or a
  stroke of positive width, in an sRGB color, with `BlendMode.srcOver` and antialiasing. The paint can't have a shader,
  a color, mask or image filter, or `invertColors`. A hairline, of width 0, is a device pixel wide under any transform,
  so it can't be imported once. `fromPaths` throws for a paint the GPU renderers can't draw, whatever the backend, so
  that a scene draws the same with each. Draw those with a `Canvas`. The paints' fields are copied.
- **Strokes** are drawn as an SVG's are: the GPU renderer's have its fixed miter limit, and it draws bevel joins as
  miters. Contours of no length are left out, as `computeMetrics` leaves them out, so a dot drawn as a line of no
  length with round caps isn't drawn.
- **Glow:** `fromPaths(glow: RasterizerGlow(radius))` gives each path a neon tube's glow: a halo under its draws, which
  fades out from the path's edge, and a core over each stroke, near white down its middle. `RasterizerGlow.widths`
  measures the radius in line widths instead, and gives fills a core too. Only the mesh renderer draws a glow, as
  triangles made at import, with no layer or pass. The GPU and canvas renderers draw the same paths without it.
- **Below them:** the internal `lib/src/core.dart` has `PathContours`, the flattened contours, `PathDraw`, and
  `Scene.fromPaths` and `Mesh.fromPaths`, over the C API's `ra_scene_from_paths` and `ra_mesh_from_paths`.

## OpenGL ES

On Impeller's OpenGL ES backend, `RasterizerGpu.support` is `openGles`, and the canvas renderer draws, unless the app
opts in before parsing scenes or creating renderers:

```dart
void main() {
  RasterizerGpu.allowOpenGles = true;    // does nothing off OpenGL ES
  runApp(const MyApp());
}
```

Scenes and renderers made without a backend then draw with the canvas renderer from the first frame. They start
`RasterizerGpu.initialize`'s self-test, which renders a small scene with the GPU renderer, reads it back, and checks it
pixel by pixel. If it passes, they all switch to the GPU renderer, each renderer at its next `beginFrame`, and
`support` becomes `supported`. `await RasterizerGpu.settledBackend` tells when that's done, and which renderer draws.

- **The switch** can show once, as a faint change at edges, as the two renderers antialias differently. To start on
  the GPU renderer instead, with no switch but nothing drawn until the self-test is done, await
  `RasterizerGpu.initialize()` after `runApp`, before making scenes and renderers.
- **Pacing:** the self-test first waits for the app's first rasterized frame, as Flutter GPU only creates its shaders
  and pipelines on OpenGL ES once a frame has been drawn. It then compiles the GPU renderer's 8 pipelines, one per
  frame. Flutter GPU blocks the UI thread while one compiles, for 50–100 ms each on the Android emulator, so the app
  stutters a little meanwhile rather than freezing for half a second. Before the switch, scenes are parsed for the GPU
  renderer a few per frame, and keep their SVG's bytes until then.
- **Splash screens and the background:** the self-test waits for as long as the app defers its first frame, with
  `RendererBinding.deferFirstFrame`, as flutter_native_splash's `preserve()` does, or with asynchronous
  `Localizations`. It takes no step while the app isn't resumed, or, on desktop, inactive: a window without the focus,
  which is still drawn. It times out only after 10 s without a rasterized frame, or 20 s without a passing render,
  counting only time in the foreground with frames allowed. The canvas renderer then keeps drawing. Taking steps in the
  background would hang the app for good, as Flutter GPU's blocking calls wait on GL work that's only done while frames
  are drawn.
- **Formats:** the GPU renderer accumulates coverage in r32Float, else in r16g16b16a16Float. If neither passes, the
  canvas renderer keeps drawing. `RasterizerGpu.supportDetail` says which passed, or why neither did.
  `RasterizerGpu.openGles` tells whether Impeller renders with OpenGL ES at all.
- **Opt-in:** the self-test checks the renderer's output, not a driver's crashes or hangs (see the next point). It has
  only run on the Android Emulator's OpenGL ES, on the Mac's GPU and on its software renderer, and on Mesa's llvmpipe
  on Linux. Hence the opt-in. In a release build on the emulator, the switch comes 1–3.5 s after launch, much of it
  spent waiting for the app's first frame. In the Linux container, it comes after 0.5–1.3 s.
- **Remembered failures:** with `RasterizerGpu.rememberSelfTest`, on by default, a failure is remembered. Later
  launches skip the self-test and draw with the canvas renderer from the start, as without `allowOpenGles`.
  - A failure is either a failure of the self-test's checks, or the app crashing or hanging twice in a row during the
    self-test or its probation. The probation lasts from the switch until the GPU renderers have rendered
    `RasterizerGpu.probationFrames` frames: 1800 by default, about 30 s of drawing, or 0 to end it at the switch. It's
    there because a driver can pass the self-test, then crash on what the app draws next.
  - A launch counts as unfinished while it's in the self-test or probation with the app in the foreground. So a bad
    driver costs a user two crashes, not one per launch, and an app killed in the background doesn't count.
    `supportDetail` then says where the launches stopped, such as "after the switch to the GPU renderer, within its
    first 1800 frames, 2 launches in a row (after 10 frames, then after 100 frames)". Debug builds don't count
    launches, as stopping the app from an IDE kills it in the foreground.
  - Timeouts aren't remembered, and neither are passes: a passing device runs the self-test and its probation at each
    launch. `RasterizerGpu.onProbation` tells whether it's on probation.
  - The failure is kept in a small file in the app's code cache, which Android clears when the app or the platform is
    upgraded, so they try again. On Linux, it's in the user's cache, `$XDG_CACHE_HOME` or else `~/.cache`, in a folder
    named after the app's executable. It holds for one build of the app, identified by its compiled Dart code's time
    and size: a new build tries again, but Mesa updated on its own doesn't. `RasterizerGpu.forgetSelfTest()` tries
    again too, from the next launch.
- **Page size:** atlas pages are at most 4096 px a side on OpenGL ES, as Flutter GPU doesn't tell the device's maximum
  texture size.
- **The mesh renderer** has a self-test of its own. Scenes and renderers made with `gpu: RasterizerBackend.mesh` start
  `RasterizerGpu.of(RasterizerBackend.mesh).initialize()`'s, which renders a mesh scene, affine and under a
  perspective. They switch to the mesh renderer once it passes. Its failures are remembered in a file of their own
  (`rasterizer_gpu_gles_mesh.json`), its probation counts its own frames, and its `supportDetail` says
  `OpenGL ES, self-tested, 4× multisampled`, or `aliased`. `allowOpenGles`, `rememberSelfTest`, `probationFrames` and
  `forceCanvas` apply to both renderers.

## The mesh renderer

`RasterizerBackend.mesh` is for games, whose SVGs keep their geometry once loaded, and are drawn under new transforms:

```dart
final renderer = await RasterizerRenderer.create(gpu: RasterizerBackend.mesh);
final coin = RasterizerScene.fromSvg(bytes, gpu: RasterizerBackend.mesh, maxSize: 256 * devicePixelRatio);
```

- **Import, once per SVG** (`src/ra_mesh.hpp`): NanoSVG parses the SVG, skipping what the GPU renderer skips. Its
  curves are flattened once, to within 1/4 of a device pixel at `maxSize`. libtess2 triangulates its fills with their
  winding rule. Strokes are outlined as strips of triangles, with SVG's joins, caps, miter limits and dashes. A stroke
  whose strip overlaps itself, at a sharp turn or a crossing, is merged by libtess2 instead, so that it covers each
  pixel once. The triangles, and a texture of the paths' paints, are uploaded at the scene's first draw, and stay on
  the GPU until the scene is disposed of. A scene of paths is imported the same way, from its paths' polylines (see
  [Paths](#paths)).
- **`maxSize`** is the most that the SVG's longer side is drawn at, in device pixels. Pass the largest size it's drawn
  at, such as its component's size times the camera's largest zoom and the device pixel ratio. Its triangles are made
  for that size, and drawn at every size, with no level of detail. Drawn larger, curves show their segments. Drawn much
  smaller, each pixel pays for many triangles: on the Mac, 100 tigers at the example's zoom 0.25 cost the GPU 11.6 ms
  a frame, against 15.0 at zoom 1, with 16 times fewer pixels.
- **Each frame:** an entry is a record of its transform, perspective included, and of its color transform scaled by its
  opacity. Consecutive entries of the same scene make one instanced draw.
  - Each run is rendered into a target of its own: its entries' bounds, rounded out to pixels and clipped to the
    viewport, sized in 64 px steps so that moving entries keep their target. It's then drawn as the GPU renderer's runs
    are.
  - Targets are pooled per frame in flight, with a run's target the same size in all of them, so that they share one
    multisampled texture. They're sized as atlas pages are: they grow at once, and shrink every 120 frames to the
    largest those frames needed, if that's below 3/4 of their area, or after a viewport change. They're released after
    120 frames unused, shrink to the last frame's needs with `trimAtlas()`, and are reported by `atlasBytes` and
    `pageSizes`.
  - A mesh whose paints are all opaque, drawn opaque, isn't blended, so Apple's GPUs shade only its topmost fragments.
- **Samples:** `RasterizerRenderer.create(meshSamples:)`, 4 by default, multisamples the targets where Flutter GPU
  supports offscreen MSAA, else they're aliased. 1 makes them aliased everywhere, for less GPU time where many SVGs
  overlap: 23–40% less for a game's SVGs at zoom 1.
- **What it doesn't draw:** an SVG's clip paths, which no renderer applies: NanoSVG and the canvas renderer's import
  skip them, so the content is drawn unclipped. Neither GPU renderer draws a zero-length subpath's caps (a dot), as
  NanoSVG drops them.
- **How it differs from the GPU renderer**, as measured by the golden tests, whose mesh goldens are its own:
  - Antialiasing: 4× MSAA, against the core's exact coverage. At most 32 of 49,152 4×4 blocks differ by over 32/255.
  - Strokes thinner than a pixel on screen, such as the tiger's whiskers drawn small, come out dotted, as 4 samples a
    pixel catch or miss them. The core draws them as faint lines.
  - `bounds` are its triangles', tighter than the core's and the canvas renderer's: the tiger's are 474.2 × 490.0,
    against 478.5 × 506.9. So an SVG fitted by its bounds is placed differently by each renderer, while `viewBox` is the
    same.
  - Strokes are drawn as SVG says, where the GPU renderer's aren't. The core draws bevel joins as miters, and ignores
    `stroke-miterlimit` for a fixed limit of its own. It also blends a translucent stroke twice where it crosses or
    overlaps itself, though not at its joins: a loop, a star's crossings, a path that turns back, a circle stroked
    wider than its radius. That happens whether the SVG makes the stroke translucent or an entry's opacity fades it.
    Fixing those would be in the core, `src/core/`.

## The canvas renderer

Where the GPU renderer isn't supported, `RasterizerGpu.backend` is `canvas`. `RasterizerGpu.forceCanvas = true` picks it
everywhere, for scenes and renderers created after it's set.

- **Parsing:** [vector_graphics_compiler](https://pub.dev/packages/vector_graphics_compiler) parses SVGs in Dart, so on
  web too, through a trimmed copy of `SvgPaths`, a class written for flame_svg (`lib/src/svg_paths/`). Its scenes have
  the same `viewBox`, `bounds` and coordinates as the core's, so the same transforms place both renderers' output in
  the same place.
- **Drawing:** a run draws its entries when it's drawn (`RasterizerRun.draw`), each with its transform, clipped to the
  viewport, except with CanvasKit, on the web, which dropped some entries near the clip's edge. There's no atlas, no
  image, and nothing to render, so a frame's timings and `pageSizes` are empty, and a run has no `parts`. A canvas run
  draws its entries as they are when it's drawn, so only until the next `beginFrame`. Each scene is recorded once as a
  `Picture`, and drawn with `drawPicture`, which halved the UI thread's time in a benchmark.
  `RasterizerGpu.canvasPictures = false` draws its paths instead.
- **What it draws, as the core does:** paths, filled and stroked, with caps, joins, miter limits and dashes, even-odd
  fills, and linear and radial gradients.
  - Opacity is multiplied into each path's paint, as the core does, rather than drawn as a layer. Clips, masks,
    patterns, text and images aren't imported.
  - Consecutive paths with the same paint, whose bounds don't overlap, are merged into one, which keeps the paint
    order.
  - Paths without an area, such as a line with SVG's default fill, aren't filled, as SVG and the core don't fill them,
    where a canvas would paint a hairline.
  - An entry's opacity scales each paint's alpha as its paths are drawn, and its color transform's filter goes on each
    paint. Entries with an opacity below 1 or a color transform draw their paths rather than their picture.
- **How it differs from the GPU renderer**, as measured by the golden tests:
  - Antialiasing: Impeller's, with 4× MSAA on macOS, iOS and Android, against the core's exact coverage, so edge pixels
    differ by up to about 100/255.
  - Curves are always drawn as curves. `curves: false` only applies to the GPU renderer.
  - Sharp miter joins: the canvas draws SVG's miters, up to the miter limit, where the core's joins differ.
  - Diagonal or rotated linear gradients in `objectBoundingBox` units, SVG's default, on shapes that aren't square:
    vector_graphics_compiler maps the gradient's two ends to the shape's bounds, so its colour bands stay perpendicular
    to the gradient. SVG, Chrome and the core tilt them with the bounds' proportions.
  - Skews: vector_graphics_compiler reads `skewX` and `skewY` angles as radians rather than degrees, on shapes and
    gradients.
  - On the iOS Simulator, Impeller doesn't draw strokes painted with horizontal or vertical linear gradients, which
    macOS draws from the same calls.
  - On web, CanvasKit gives `Path.combine`'s result a nonzero fill type rather than an even-odd one, so a difference's
    holes are filled, as with Flutter's own `drawPath`. Set its `fillType` to `PathFillType.evenOdd` again.

## Layout

- `hook/build.dart` builds the shader bundle into `build/shaderbundles/`, and the core into a code asset. The bundle is
  listed as an asset, and loaded as `packages/rasterizer_gpu/build/shaderbundles/rasterizer.shaderbundle`.
- `src/core/` is the Rasterizer core: a patched copy of [Rasterizer](https://github.com/mindbrix/Rasterizer)'s, MIT
  licensed, edited here. Its `README.md` lists the patches.
- `src/ra_mesh.hpp` is the mesh renderer's import, with `ra_mesh_*` in the C API (`src/ra_capi.h`). `src/libtess2/` is
  its tessellator, [libtess2](https://github.com/memononen/libtess2), patched to compile as C++. `src/ra_paths.hpp`
  imports the polylines of paths flattened in Dart, for both GPU renderers.
- `shaders/` holds the GLSL port of the original's `Shaders.metal`, and the mesh renderer's `ra_mesh*` shaders.
- `lib/rasterizer_gpu.dart` is the API. It doesn't import `dart:ffi`, so it also compiles for web.
  - `lib/src/atlas.dart` is the GPU renderer, imported only where `dart:ffi` is available, with `lib/src/gpu_stub.dart`
    elsewhere. `lib/src/gpu_renderer.dart` is its Flutter GPU draw loop, and `lib/src/atlas_pages.dart` and
    `lib/src/atlas_parts.dart` size and pack its pages.
  - `lib/src/meshes.dart` is the mesh renderer, and `lib/src/mesh_gpu.dart` its buffers, targets and draws.
    `lib/src/image_run.dart` draws both GPU renderers' runs.
  - `lib/src/canvas_renderer.dart` is the canvas renderer, and `lib/src/svg_paths/` its SVG import.
  - `lib/src/paths/` has the scenes of paths: `path_contours.dart`, with the contour sampler copied from Flame, and
    `scene_paths.dart`, the paths and paints a scene is made of. `lib/src/canvas_paths.dart` is what the canvas
    renderer draws: an SVG's paths, or those.
  - `lib/src/self_test.dart` has the OpenGL ES self-test's scene and the pixels it checks,
    `lib/src/self_test_cache.dart` the remembered failures, and `lib/src/switching.dart` the scenes and renderers that
    switch from the canvas renderer to a GPU renderer.
  - `lib/src/rasterizer_canvas.dart` is `RasterizerCanvas`.
  - `lib/src/core.dart` is the core's FFI API, internal and native only, with the GPU renderer's debug hooks, for the
    renderers, the tests and the example. `lib/src/bindings.dart` declares its native functions, and
    `lib/src/geometry.dart` holds its transforms and bounds, without FFI.
- `android/` is an Android library with no code, for its manifest.
- `test/` runs with `flutter test`. Among its tests, `core_test.dart` tests the core through FFI, on generated scenes,
  `mesh_test.dart` the mesh import's triangles, `svg_paths_test.dart` the canvas renderer's SVG import, against the
  core's, and `path_contours_test.dart` and `path_scene_test.dart` the scenes of paths.
- `example/` is the example app, with the golden tests: see its `README.md` and `TESTING.md`.
- `tool/compare_frames.py` compares two of the core's frames, as the golden tests record them.
- `tool/make_patch.py` rewrites `src/core/upstream.patch` from a Rasterizer checkout.
- The repository's `tool/` has the tools shared with flame_rasterizer. `device_tests.py` and `matrix.py` run the
  integration tests on devices, and `web_shot.py` screenshots a web build in headless Chrome, as the web smoke check.

## Licences

MIT, © 2026 Dario Accornero (`LICENSE`).

- `src/core/`, `src/ra_frame.hpp`, `shaders/` and `lib/src/gpu_renderer.dart` are copied or ported from
  [Rasterizer](https://github.com/mindbrix/Rasterizer), MIT, © 2025 Nigel Timothy Barber. The core includes NanoSVG
  (zlib) and xxHash (BSD 2-clause).
- `src/libtess2/` is libtess2, under the SGI Free Software License B, version 2.0.
- `lib/src/paths/path_contours.dart` copies [Flame](https://github.com/flame-engine/flame)'s contour sampler, and
  `lib/src/svg_paths/` is based on `SvgPaths`, which this package's author wrote for flame_svg and Flame didn't merge:
  MIT, © 2021 Blue Fire.

`LICENSE` includes all these licences. The example's `tiger.svg` and its renders are separately licensed test data
(AGPL-3.0-or-later), and three of the SVGs in `test/svgs/` are CC0 1.0 (`test/svgs/README.md`). The repository's
`THIRD_PARTY_NOTICES.md` has the notices.
