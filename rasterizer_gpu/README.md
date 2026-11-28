# rasterizer_gpu

Renders SVG scenes, and scenes of plain `dart:ui` paths (see [Paths](#paths)), with one of three renderers behind the
same API. Each frame holds runs: groups of scenes, each with its own transform, that are drawn as one unit at one place
in the app's paint order.

- **The GPU renderer**, also called the atlas renderer, runs Rasterizer's C++ core with Flutter GPU. It draws on
  Impeller's Metal backend (iOS, macOS), Vulkan backend (Android) and OpenGL ES backend (Android, Linux, Windows): see
  [OpenGL ES](#opengl-es). Once per frame, it renders all of the frame's runs into an atlas: a few large textures,
  called pages. It then draws each run from its rectangles in the atlas with `Canvas.drawImageRect`, at the run's place
  in the paint order, so vector content keeps its z-order among other content.
- **The mesh renderer**, made for games, draws wherever the GPU renderer does. It imports each SVG once into triangles,
  which stay in GPU buffers. Each frame then only writes its entries' transforms, and renders each run into its own
  image with instanced draws, 4× multisampled by default. See [The mesh renderer](#the-mesh-renderer).
- **The canvas renderer** is the fallback everywhere else: on Skia, on the web, and on Impeller's OpenGL ES if the app
  turns `RasterizerGpu.allowOpenGles` off. It parses scenes in Dart, and each run draws its scenes' paths with
  `Canvas.drawPath`, straight into the canvas it's drawn into. See [The canvas renderer](#the-canvas-renderer).

`RasterizerGpu.backend` is the GPU renderer where `RasterizerGpu.support` is `supported`, and the canvas renderer
otherwise, or when the app sets `RasterizerGpu.forceCanvas`. `RasterizerGpu.of(RasterizerBackend.mesh)` has the same
members for the mesh renderer: its `backend` is `mesh` where it's supported, and `canvas` otherwise.

For Flame games, the flame_rasterizer package draws components with these renderers.

## Tested on

- macOS 26.7, on an M1 Mac.
- The iOS Simulator (iPhone 18 Pro, iOS 27.0).
- An iPhone 11 Pro (A13, iOS 26.7.2).
- The Android Emulator (API 37, arm64, with the Mac's GPU through gfxstream), on Impeller's Vulkan and OpenGL ES
  backends and on Skia; and API 28, where Flutter renders with Skia.
- Linux arm64 in a Docker container (the repository's `tool/linux/`): Debian trixie, with Mesa's llvmpipe, which renders
  on the CPU, on X11 (Xvfb) and on Wayland (weston). It uses Impeller's OpenGL ES backend, the only one Flutter's Linux
  embedder has.

On each, the example's golden tests pass with the GPU and canvas renderers:

- The iPhone's set matches macOS's within 1/255, except in the tiger sweep's frame 119, where at most 141 pixels
  differ, by up to 10/255. The emulator's Vulkan and OpenGL ES sets match macOS's within 1/255.
- On macOS, the iPhone, the iOS Simulator, the emulator's Vulkan and OpenGL ES, and in the Linux container, the format
  probe, defer and atlas tests pass too.
- On web, in headless Chrome with CanvasKit and with skwasm, the canvas renderer's golden tests pass against the
  `macos` set, and so does the opacity test.
- On Skia (`--no-enable-impeller`, or API 28), on macOS and the emulators, the canvas renderer's golden tests and the
  opacity test pass.

Not tested: other iPhone or iPad GPUs, physical Android devices, Linux on a GPU (Mesa's drivers or NVIDIA's), and
Windows, where the examples build on GitHub's Windows runners (`.github/workflows/windows.yml`) but haven't run.

The mesh renderer passes its own tests (`mesh_test`, `projective_test`, the opacity test and the defer test) on macOS,
on the iOS Simulator, in the Linux container, and on the emulator's Vulkan and OpenGL ES. On the emulator's OpenGL ES,
it draws 4× multisampled. On the iPhone, its golden, mesh, opacity and projective tests pass, and on the iOS Simulator
its golden tests pass against the `macos` set. Its goldens were recorded on macOS, the iPhone, the emulator, and in the
Linux container, where it draws on llvmpipe.

On the emulator's Vulkan with the Mac's GPU, the canvas renderer, which draws each path, can't draw the heaviest frames.
Emulator 37.3 runs that Vulkan on Metal: through KosmicKrisp where the Mac supports Metal 4, and through MoltenVK
otherwise, or with `ANDROID_EMU_VK_SELECT_ICD=moltenvk`.

- With KosmicKrisp, frames of about 1,500 paths draw. But 100 of the example's tigers, of 301 paths each, take seconds
  per frame and never reach the screen, while the emulator's memory grows. A dropdown opened over 100 SVGs on the
  canvas renderer has hung the Mac's GPU: macOS resets it, and the emulator quits on the lost Vulkan device.
- With MoltenVK, frames of a few hundred paths or more don't reliably draw. The emulator reports a full descriptor pool
  as `ErrorFragmentedPool`. Flutter 3.47.9's Impeller doesn't replace the pool on that error, as it does on
  `ErrorOutOfPoolMemory`, so a frame of more than about 800 draws hangs or crashes the app, with or without this
  package. Flutter 3.50.0's Impeller replaces it, but such frames come out empty or wrong, on screen and in `toImage`.
  The heaviest, such as 100 tigers, make the emulator's memory grow by gigabytes within seconds.

The emulator's OpenGL ES and its software GPU (`emulator -avd <name> -gpu swiftshader_indirect`), whose Vulkan reports
the full pool, draw these frames. To test the canvas renderer on the emulator, use either.

## App setup

- **iOS and macOS:** turn on Flutter GPU in the app's `Info.plist`, as a plugin can't:

  ```xml
  <key>FLTEnableFlutterGPU</key>
  <true/>
  ```

- **Android:** API 24 or later. This package's manifest turns on Flutter GPU. The GPU renderers need a 64-bit device
  with Impeller. The canvas renderer draws instead:
  - on 32-bit devices, which get no native code;
  - below API 29, where Flutter renders with Skia, not Impeller;
  - on OpenGL ES, if the app turns `RasterizerGpu.allowOpenGles` off ([OpenGL ES](#opengl-es)).

  Impeller picks its backend itself: Vulkan where it can, else OpenGL ES. As of Flutter 3.47.9, Android uses OpenGL ES
  on emulators, on Adreno 650 and older GPUs, on older MediaTek, Exynos and PowerVR devices, on Huawei devices, and
  wherever a Vulkan 1.1 context can't be created. In debug and profile builds only, the app's manifest can ask for a
  backend, inside `<application>`, such as Vulkan to test on the emulator:

  ```xml
  <meta-data android:name="io.flutter.embedding.android.ImpellerBackend" android:value="vulkan" />
  ```

  Release builds ignore this key and let Impeller pick. Debug and profile builds that set it get Impeller below API 29
  too, where it can't start, so the app crashes at launch (`Could not create surface from invalid Android context`).
  Leave it out of builds that run there.

- **Linux:** turn on Flutter GPU in the app's runner, `linux/runner/my_application.cc`, where it creates its project:

  ```c
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_enable_flutter_gpu(project, TRUE);
  ```

  This works in release builds too, unlike the `FLUTTER_ENGINE_SWITCHES` environment variable. Flutter's Linux embedder
  always renders with OpenGL ES, so the GPU renderer draws there unless the app turns `RasterizerGpu.allowOpenGles` off
  ([OpenGL ES](#opengl-es)). The build hook builds the core with the clang that Flutter's Linux builds need, linked to
  the system's libstdc++. The app then runs on systems whose libstdc++ is as new as the build machine's, or newer, so
  build it on the oldest distribution it supports.

- **Windows:** turn on Flutter GPU in the app's runner, `windows/runner/main.cpp`, where it creates its project:

  ```cpp
  flutter::DartProject project(L"data");
  project.set_enable_flutter_gpu(true);
  ```

  Flutter's Windows embedder renders with Impeller's OpenGL ES backend only, through ANGLE on Direct3D 11, so the GPU
  renderer draws there unless the app turns `RasterizerGpu.allowOpenGles` off ([OpenGL ES](#opengl-es)). The build
  hook builds the core with MSVC, from Visual Studio's "Desktop development with C++" workload, which Flutter's
  [Windows setup](https://docs.flutter.dev/platform-integration/windows/setup) installs. Not tested on Windows yet.

- **Web:** nothing to set up. Only the canvas renderer draws there, and the build hook builds no native code.

## Use

```dart
final renderer = await RasterizerRenderer.create(slots: 2);   // for RasterizerGpu.backend: gpu or canvas
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
  run overlap in the order the app added them. Runs are drawn separately.
- **Opacity:** `add` and `addMatrix` take an `opacity`, 1 by default. It scales the alpha of each of the entry's paths,
  gradients included, so the SVG's overlapping paths show through each other. Entries with different opacities share a
  run. `add` and `addMatrix` skip an entry whose opacity is 0.
- **Color transforms:** `add` and `addMatrix` also take a `colorTransform`, a color filter applied to each of the
  entry's paths. It gives the same pixels as a layer with that filter around the entry, but entries with different
  color transforms can share a run.
  - `RasterizerColorTransform.mode(color, mode)` and `.matrix(values)` create one, with its `ui.ColorFilter` in
    `filter`. They accept the modes `srcATop` (a tint), `dst` and `clear` with an sRGB color, and matrices whose alpha
    row is (0, 0, 0, 1, 0) and whose color rows have 0 in the alpha column: greyscale, sepia, hue rotations,
    saturation and offsets. They return null for other filters.
  - Filters that change alpha, such as `modulate`, `srcIn`, `dstIn` or `dstOut`, would let overlapping paths show
    through each other, as an opacity does, and other filters aren't linear. Put those on `draw`'s paint instead, with
    a run for each filter.
  - `RasterizerColorTransform.of(filter)` finds the transform that created a filter. It finds nothing for a filter
    created otherwise, even an equal one, as a `ui.ColorFilter`'s fields are private, and profile and release builds
    strip dart:ui's `toString()`.
  - The renderers clamp a matrix's results per path rather than per pixel. So they differ from a layer's where paths
    that the matrix takes out of range overlap translucently, including at antialiased edges between paths. A hue
    rotation of 2 radians differs by up to 40/255 on a few hundred edge pixels of a 40 px SVG, and sepia by up to 8/255
    on 20 pixels. Tints are exact.
- **Paints:** `draw(canvas, paint: …)` applies the paint to the run as a whole, as to an image. The GPU renderer draws
  its parts' images with it, and the canvas renderer draws its paths in a layer with it. The GPU renderer still uses a
  layer in two cases: for an image or mask filter, which can reach outside the images, and, across several parts, for a
  blend mode that changes what's under transparent pixels, such as `srcIn`. A color filter that colors transparent
  pixels, such as a `srcOver` mode, colors each part's rectangle rather than the run's bounds.
- **Slots:** a frame's images are valid until `slots` frames later, when the renderer renders into their textures again.
  The default, 2, is enough, as Flutter rasterizes a frame before it builds the one after next. An app that takes an
  image of a frame later, such as with `RepaintBoundary.toImage` after the frame, needs 3.
- **Parts:** the GPU renderer draws a run from its parts (`run.parts`). Entries whose bounds, grown by a 2 px margin,
  overlap in a chain share a part: a rectangle around their bounds, within the viewport. Separate entries get separate
  parts. So a run of entries scattered over the screen takes only their area of the atlas, and a run that covers the
  screen takes a screen's. The renderer packs parts in rows about as wide as the side of a square of their total area.
  Pages are up to 8192 px a side, or 4096 on OpenGL ES. Parts that don't fit spill onto further pages, each rendered
  separately.
- **Page sizes:** pages grow at once to a frame's needs. Every 120 frames, each page shrinks to the largest size those
  frames needed, if that's below half its area. If the viewport changed size in those frames, as with a rotation or a
  window resize, the page shrinks to that size whatever its area. So a page shrinks at most once in 120 frames, and the
  renderer releases pages that no frame needed for 120 frames. Steady scenes and games rarely reallocate pages, and a
  turned phone or a resized window gives back what the larger size took. With 2 `slots`, each page takes about 17
  bytes a pixel, or 16 on OpenGL ES. `renderer.atlasBytes` gives the estimate, from the textures' formats.
  `renderer.trimAtlas()` shrinks pages to the last frame's needs and releases the rest at once. Call it when the app
  knows its frames got lighter, such as at a level change.
- **Disposing:** don't dispose of a scene between `add` and `render`, nor before drawing a canvas run that draws it.
- **Backends:** a scene is parsed for one backend, and only that backend's renderers can draw it. `fromSvg` and
  `create` both default to `RasterizerGpu.backend`. Both take a `backend`, or else a `gpu`, `RasterizerBackend.gpu` by
  default or `RasterizerBackend.mesh`, which picks that renderer where it's supported and the canvas renderer
  elsewhere. A mesh scene needs a `maxSize`, whichever renderer is chosen (see [The mesh renderer](#the-mesh-renderer)).
  A scene of paths always needs one (see [Paths](#paths)).
- **Perspective:** `RasterizerRun.addProjective(scene, a, b, c, d, tx, ty, g, h, i)` adds an entry under a perspective,
  whose w is g x + h y + i, as `addMatrix` does with a `Matrix4`'s w row. The mesh and canvas renderers draw it
  exactly. The GPU renderer only takes a w that's the same everywhere, with g and h 0, and throws an `ArgumentError`
  otherwise.
- **Rectangles:** a scene's `viewBox` is the SVG's own rectangle, in its paths' coordinates: its viewBox, or else its
  width and height. The core doesn't scale the paths to the width and height. `bounds` is the paths' bounds. `rect` is
  the rectangle the scene is drawn from, such as to fit it to a size: its `viewBox`, or its `bounds` for an SVG with
  neither a viewBox nor a size.
- **Drawing a scene directly:** `scene.drawPaths(canvas)` draws a canvas scene's paths into any canvas, such as a
  picture's, under any transform, with no frame or renderer. It throws a `StateError` for scenes of the other backends.
- **Outlines:** `SvgOutline.fromSvg(bytes)` gives an SVG's paths as one `dart:ui` `Path`, for hitboxes. `fromSvg`
  parses the SVG in Dart whatever the backend, and gives the path in the SVG's coordinates. Filled paths have their
  contours closed, and stroked-only ones stay as they are. Its `rect` is the rectangle it's drawn from, as a scene's is.

To draw runs while painting, before the frame has rendered, place each run as it ends, and render the frame before
Flutter rasterizes the painting:

```dart
final frame = renderer.beginFrame(widthPx, heightPx);
final run = frame.addRun()..add(coin, a, b, c, d, tx, ty);
run.place();                                       // its parts are set now
run.draw(canvas, scale: devicePixelRatio);
// ... more runs, each placed as it ends
frame.render();                                    // before Flutter rasterizes the picture
```

Placed runs go onto atlas pages sized as earlier frames' runs needed, packed together, so a steady scene settles on the
same pages. A part that doesn't fit on a page goes to the next one, which costs another render. A page that no earlier
frame sized is at least the viewport's size, until the next 120 frames shrink it.

`RasterizerCanvas` does this for a whole painting. It wraps a canvas for one frame: scenes drawn one after another with
`drawScene` make up a run, and it draws everything else straight into the wrapped canvas. A run ends when
`RasterizerCanvas` draws anything else, when the clip changes, or when it draws a scene with another paint. Transforms
don't end runs, as each entry has its own.

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
  (path: path, paint: Paint()..color = const Color(0xffffc107)),
  (path: path, paint: Paint()..color = const Color(0xffff6f00)..style = PaintingStyle.stroke..strokeWidth = 4),
], maxSize: 128 * devicePixelRatio);
```

- **Drawn as SVG draws them:** a fill fills its path with the path's `fillType`, with open contours closed. A stroke
  strokes its path with its width, cap, join and miter limit, with open contours left open. The scene's coordinates are
  the paths', x right and y down. Its `viewBox` is their bounds without their strokes, and its `bounds` include half
  their strokes' widths. A mesh scene's `bounds` are its triangles'.
- **Imported once:** a `ui.Path` doesn't expose its commands, so the GPU renderers read its contours back with
  `computeMetrics`. They flatten them into polylines with a contour sampler copied from Flame, to within 1/4 of a
  device pixel when the `viewBox`'s longer side, or the widest stroke if it's wider, spans `maxSize` device pixels. The
  tolerance is never finer than 16 float steps of the paths' farthest coordinate: a finer one could make a tiny path's
  mesh take seconds to tessellate, or never finish.
  - So `fromPaths` requires `maxSize` for every renderer, even the GPU renderer, which draws an SVG's curves as curves.
  - Treat paths as immutable: changing one after the import gives undefined results. The GPU renderers keep drawing it
    as it was. The canvas renderer, which draws the paths themselves, draws it as it was when it recorded it as a
    picture, or else as it is.
  - A path keeps its contours while it lives, so another scene of it with the same tolerance, such as one with other
    paints, doesn't flatten it again.
- **Paints:** `RasterizerScene.canDraw(paint)` says whether the GPU renderers can draw a paint. They draw a fill, or a
  stroke of positive width, in an sRGB color, with `BlendMode.srcOver` and antialiasing. The paint can't have a shader,
  a color, mask or image filter, or `invertColors`. A hairline, of width 0, is a device pixel wide under any transform,
  so it can't be imported once. `fromPaths` throws for a paint the GPU renderers can't draw, whatever the backend, so
  that a scene draws the same with each. Draw those with a `Canvas`. `fromPaths` copies the paints' fields.
- **Strokes** are drawn as an SVG's are: the GPU renderer's have its fixed miter limit, and it draws bevel joins as
  miters. Contours of no length are left out, as `computeMetrics` leaves them out, so a dot drawn as a line of no
  length with round caps isn't drawn.
- **Glow:** `fromPaths(glow: RasterizerGlow(radius))` gives each path a neon tube's glow: a halo under its draws, which
  fades out from the path's edge, and a core over each stroke, near white down its middle. `RasterizerGlow.widths`
  measures the radius in line widths instead, and gives fills a core too. Only the mesh renderer draws a glow, as
  triangles made at import, with no layer or pass. The GPU and canvas renderers draw the same paths without it.
- **Polygons:** `RasterizerPolygons` is a shape made of polygons, which a scene draws as it draws a path. Polygons have
  no curves, so the GPU renderers draw them without first flattening them into lines, as they must do with a path. It
  holds the vertices in a `Float32List`, x then y, and the number of vertices of each polygon.
  `RasterizerScene.fromPolygons` makes a scene of them, as `fromPaths` does of paths. The canvas renderer draws their
  `path`. Fills use the non-zero rule. Use polygons for shapes that an app rebuilds often, such as every frame. With
  `separate: true`, the mesh renderer fills each polygon on its own instead of filling their union: a convex polygon as
  a fan of triangles, and any other polygon tessellated on its own. That's much faster for many polygons (see
  [Measurements](#measurements)). Where polygons overlap, their triangles overlap too, and the overlap shows through an
  opacity, or through colors or glows that aren't opaque. The other renderers ignore `separate`.
- **Below them:** the internal `lib/src/core.dart` has `PathContours`, the flattened contours, `PathDraw`, and
  `Scene.fromPaths` and `Mesh.fromPaths`, over the C API's `ra_scene_from_paths` and `ra_mesh_from_paths`.

## OpenGL ES

On Impeller's OpenGL ES backend, the GPU renderers draw from the first frame, as on Metal and Vulkan, as
`RasterizerGpu.allowOpenGles` is on by default. An app that turns it off before parsing scenes or creating renderers
gets the canvas renderer there instead, and `RasterizerGpu.support` is then `openGles`:

```dart
void main() {
  RasterizerGpu.allowOpenGles = false;    // does nothing off OpenGL ES
  runApp(const MyApp());
}
```

`RasterizerGpu.openGles` tells whether Impeller renders with OpenGL ES at all.

- **Pipelines:** each renderer compiles all of its pipelines when it's created, rather than in the first frame that
  draws with each, as a compile stalls the thread that runs it. Part of the work runs on the UI thread as the renderer
  is created, the rest on the raster thread right after, and `RasterizerRenderer.create` completes once both are done.
  So creating a renderer takes longer, once (see [Measurements](#measurements)), and its first frame doesn't stall: an
  app can show a loader until it's created. If the pipelines haven't compiled within `RasterizerGpu.warmUpTimeout`, 5 s
  by default, `create` makes the canvas renderer instead, and that GPU renderer's support becomes
  `RasterizerSupport.warmUpTimeout`, so scenes created afterwards are for the canvas renderer too. Create scenes after
  the renderer, as those created before can't switch.
- **Formats:** the GPU renderer accumulates coverage in r32Float, which an OpenGL ES driver may not blend into. The
  first GPU renderer created starts a format probe: it renders a small scene in r32Float, reads it back through a
  canvas alongside the app's frames, and checks it pixel by pixel. If that fails, renderers accumulate in
  r16g16b16a16Float from their next frame. The switch happens at once where an r32Float texture can't be created, and
  otherwise once the probe has read the pixels back, so the first frames may be wrong. The probe then checks
  r16g16b16a16Float the same way. If that fails too, the renderers keep drawing, wrongly. `RasterizerGpu.supportDetail`
  says which format they use, and what the probe found.
- **No other checks:** nothing else checks what the renderers draw, or guards against a driver's crashes. A driver that
  draws wrongly draws wrongly, and one that crashes crashes the app. The GPU renderers have only drawn on the Android
  Emulator's OpenGL ES, on the Mac's GPU and on its software renderer, and on Mesa's llvmpipe on Linux.
- **Before `runApp`:** nothing waits for a frame. With Flutter 3.50.0, on the emulator's OpenGL ES and on llvmpipe,
  release builds included, renderers can be made and render before the app's first frame.
- **Page size:** atlas pages are at most 4096 px a side on OpenGL ES, as Flutter GPU doesn't report the device's
  maximum texture size. OpenGL ES only guarantees 2048, so the support check first creates a texture 4096 px wide.
  Where Flutter GPU can't, support is `RasterizerSupport.smallTextures`, and the canvas renderer draws.
- **The mesh renderer** runs no probe: its `supportDetail` says `OpenGL ES, 4× multisampled` or `OpenGL ES, aliased`.
  `allowOpenGles` and `forceCanvas` apply to both GPU renderers.

## The mesh renderer

`RasterizerBackend.mesh` is for games and other apps whose SVGs keep their shapes once loaded, and are drawn under new
transforms each frame:

```dart
final renderer = await RasterizerRenderer.create(gpu: RasterizerBackend.mesh);
final coin = RasterizerScene.fromSvg(bytes, gpu: RasterizerBackend.mesh, maxSize: 256 * devicePixelRatio);
```

- **Import, once per SVG** (`src/ra_mesh.hpp`): NanoSVG parses the SVG, skipping what the GPU renderer skips. The import
  flattens the SVG's curves once, to within 1/4 of a device pixel at `maxSize`. libtess2 triangulates the fills with
  their winding rule. The import outlines strokes as strips of triangles, with SVG's joins, caps, miter limits and
  dashes. Where a stroke's strip overlaps itself, at a sharp turn or a crossing, libtess2 merges it instead, so that it
  covers each pixel once. The renderer uploads the triangles, and a texture of the paths' paints, at the scene's first
  draw, and they stay on the GPU until the app disposes of the scene. `fromPaths` imports a scene of paths the same way,
  from its paths' polylines (see [Paths](#paths)).
- **`maxSize`** is the largest size that the SVG's longer side is drawn at, in device pixels, such as its size on
  screen at the largest zoom, times the device pixel ratio. The import makes its triangles for that size, and the
  renderer draws them at every size, with no level of detail. Drawn larger, curves show their segments. Drawn much
  smaller, each pixel pays for many triangles, so a smaller draw saves the GPU much less time than it saves pixels.
- **Each frame:** an entry is a record of its transform, perspective included, and of its color transform scaled by its
  opacity. Consecutive entries of the same scene make one instanced draw.
  - Each run is rendered into a target of its own: its entries' bounds, rounded out to pixels and clipped to the
    viewport, sized in 64 px steps so that moving entries keep their target. It's then drawn as the GPU renderer's runs
    are.
  - The renderer pools targets per frame in flight, with a run's target the same size in all of them, so that they
    share one multisampled texture. They're sized as atlas pages are: they grow at once, and shrink every 120 frames to
    the largest those frames needed, if that's below 3/4 of their area, or after a viewport change. The renderer
    releases them after 120 frames unused, `trimAtlas()` shrinks them to the last frame's needs, and `atlasBytes` and
    `pageSizes` report them.
  - The renderer draws the entries of a mesh whose paints are all opaque without blending, where they keep full
    opacity, so Apple's GPUs shade only the topmost fragments. For a mesh without strokes or gradients, fewer than 8
    such entries in a row join the blended draw around them, as an extra draw costs more than blending them.
- **Samples:** `RasterizerRenderer.create(meshSamples:)`, 4 by default, multisamples the targets where Flutter GPU
  supports offscreen MSAA, else they're aliased. 1 makes them aliased everywhere, for less GPU time where many SVGs
  overlap.
- **What it doesn't draw:** an SVG's clip paths, which no renderer applies: NanoSVG and the canvas renderer's import
  skip them, so the content is drawn unclipped. Neither GPU renderer draws a zero-length subpath's caps (a dot), as
  NanoSVG drops them.
- **How it differs from the GPU renderer**, as measured by the golden tests, whose mesh goldens are its own:
  - Antialiasing: 4× MSAA, against the core's exact coverage. At most 32 of 49,152 4×4 blocks differ by over 32/255.
  - Strokes thinner than a pixel on screen, such as the tiger's whiskers drawn small, are widened to a least width,
    about half a pixel with 4× MSAA and a pixel when aliased, so that the samples don't break them into dots. The core
    draws them as faint lines. Entries faded by an opacity below 1 draw each stroke as one merged shape instead, so
    that it blends once, and that shape isn't widened.
  - `bounds` are its triangles', tighter than the core's and the canvas renderer's: the tiger's are 474.2 × 490.0,
    against 478.5 × 506.9. So an SVG fitted by its bounds is placed differently by each renderer, while `viewBox` is the
    same.
  - The mesh renderer draws strokes as SVG says, where the GPU renderer doesn't. The core draws bevel joins as miters,
    and ignores `stroke-miterlimit` for a fixed limit of its own. It also blends a translucent stroke twice where it
    crosses or overlaps itself, though not at its joins: a loop, a star's crossings, a path that turns back, a circle
    stroked wider than its radius. That happens whether the SVG makes the stroke translucent or an entry's opacity fades
    it. Fixing those needs changes in the core, `src/core/`.

## The canvas renderer

Where the GPU renderer isn't supported, `RasterizerGpu.backend` is `canvas`. `RasterizerGpu.forceCanvas = true` picks it
everywhere, for scenes and renderers created without a `backend` after the app sets it.

- **Parsing:** [vector_graphics_compiler](https://pub.dev/packages/vector_graphics_compiler) parses SVGs in Dart, so on
  web too, through a trimmed copy of `SvgPaths`, a class written for flame_svg (`lib/src/svg_paths/`). Its scenes have
  the same `viewBox`, `bounds` and coordinates as the core's, so the same transforms place both renderers' output in
  the same place.
- **Drawing:** a run draws its entries when it's drawn (`RasterizerRun.draw`), each with its transform, clipped to the
  viewport. The exception is CanvasKit, on the web, which dropped some entries near the clip's edge, so runs draw there
  without the clip. A run skips the entries that paint nothing in the viewport, strokes included. Without the clip, it
  skips them only if the run's paint has no image or mask filter, which could spread them into the viewport. There's
  no atlas, no image, and nothing to render, so a frame's timings are 0, its `pageSizes` are empty, and a run has no
  `parts`. A canvas run draws its entries as they are when it's drawn, so draw it before the next `beginFrame`. The
  renderer records each scene once as a `Picture`, and draws it with `drawPicture`, which takes less of the UI thread's
  time. `RasterizerGpu.canvasPictures = false` draws its paths instead.
- **What it draws, as the core does:** paths, filled and stroked, with caps, joins, miter limits and dashes, even-odd
  fills, and linear and radial gradients.
  - It multiplies opacity into each path's paint, as the core does, rather than drawing a layer. Its import skips
    clips, masks, patterns, text and images.
  - It merges consecutive paths with the same paint, whose bounds don't overlap, into one, which keeps the paint
    order.
  - It doesn't fill paths without an area, such as a line with SVG's default fill, as SVG and the core don't fill
    them, where a canvas would paint a hairline.
  - An entry's opacity scales each paint's alpha as its paths are drawn, and its color transform's filter goes on each
    paint. Entries with an opacity below 1 or a color transform draw their paths rather than their picture.
- **How it differs from the GPU renderer**, as measured by the golden tests:
  - Antialiasing: Impeller's, with 4× MSAA on macOS, iOS and Android, against the core's exact coverage, so edge pixels
    differ by up to about 100/255.
  - It always draws curves as curves. `curves: false` only applies to the GPU renderer.
  - Sharp miter joins: the canvas draws SVG's miters, up to the miter limit, where the core's joins differ.
  - Diagonal or rotated linear gradients in `objectBoundingBox` units, SVG's default, on shapes that aren't square:
    vector_graphics_compiler maps the gradient's two ends to the shape's bounds, so its colour bands stay perpendicular
    to the gradient. SVG, Chrome and the core tilt them with the bounds' proportions.
  - Skews: vector_graphics_compiler reads `skewX` and `skewY` angles as radians rather than degrees, on shapes and
    gradients.
  - On iOS, on devices and in the Simulator, Impeller draws only the inner half of a stroked rectangle whose horizontal
    or vertical linear gradient ends on the rectangle's bounds, as SVG's default gradients do. macOS draws the whole
    stroke from the same calls.
  - On web, CanvasKit gives `Path.combine`'s result a nonzero fill type rather than an even-odd one, so a difference's
    holes are filled, as with Flutter's own `drawPath`. Set the result's `fillType` to `PathFillType.evenOdd` again.

## Layout

- `hook/build.dart` builds the shader bundle into `build/shaderbundles/`, and the core into a code asset.
  `pubspec.yaml` lists the bundle as an asset, and the package loads it as
  `packages/rasterizer_gpu/build/shaderbundles/rasterizer.shaderbundle`.
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
  - `lib/src/format_probe.dart` has the OpenGL ES format probe's SVG and the pixels it checks, and
    `src/ra_probe_scene.hpp` builds that SVG's shapes without parsing it, so that the probe checks the GPU alone.
  - `lib/src/rasterizer_canvas.dart` is `RasterizerCanvas`.
  - `lib/src/core.dart` is the core's FFI API, internal and native only, with the GPU renderer's debug hooks, for the
    renderers, the tests and the example. `lib/src/bindings.dart` declares its native functions, and
    `lib/src/geometry.dart` holds its transforms and bounds, without FFI.
- `android/` is an Android library with no code, for its manifest.
- `test/` runs with `flutter test`. Among its tests, `core_test.dart` tests the core through FFI, on generated scenes,
  `mesh_test.dart` the mesh import's triangles, `svg_paths_test.dart` the canvas renderer's SVG import, against the
  core's, `path_contours_test.dart` and `path_scene_test.dart` the scenes of paths, `probe_scene_test.dart` that the
  format probe's built scene is its SVG's, and `svg_locale_test.dart` that SVGs read the same whatever the C locale.
- `example/` is the example app, with the golden tests: see its `README.md` and `TESTING.md`.
- `tool/compare_frames.py` compares two of the core's frames, as the golden tests record them.
- `tool/make_patch.py` rewrites `src/core/upstream.patch` from a Rasterizer checkout.
- The repository's `tool/` has the tools that its packages share. `device_tests.py` and `matrix.py` run the
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

## Measurements

Figures measured during development, for the sections above. No Flutter version was recorded for them.

| What | Where measured | Result |
|---|---|---|
| Flattening paths ([Paths](#paths)) | The tiger's 301 paths, debug build | At most 17 ms, with about 4 tangent lookups a vertex |
| Polygons rebuilt every frame, mesh renderer ([Paths](#paths)) | A tube of about 600 overlapping quads, M1 Mac, profile build | 9.4 ms a frame as a path, against 0.25 ms as separate polygons |
| Polygons rebuilt every frame, atlas renderer ([Paths](#paths)) | The same tube, M1 Mac, profile build | 2.9 ms a frame as a path, mostly to flatten it, against too little to measure as polygons |
| Pipelines compiled up front, GPU renderer ([OpenGL ES](#opengl-es)) | Mesa's llvmpipe, release build, no shader cache | About 550 ms on the UI thread, then 150 ms on the raster thread |
| Pipelines compiled up front, mesh renderer ([OpenGL ES](#opengl-es)) | Mesa's llvmpipe, release build, no shader cache | 230 ms on the UI thread, then 870 ms on the raster thread |
| Pipelines compiled up front, GPU renderer ([OpenGL ES](#opengl-es)) | Android emulator's OpenGL ES, release build, no shader cache | About 110 ms on the UI thread, then 50–90 ms on the raster thread |
| Pipelines compiled up front, mesh renderer ([OpenGL ES](#opengl-es)) | Android emulator's OpenGL ES, release build, no shader cache | 60 ms on the UI thread, then 30 ms on the raster thread |
| Mesh drawn below its `maxSize` ([The mesh renderer](#the-mesh-renderer)) | GPU time, 100 of the example's tigers, Mac | 11.6 ms a frame at zoom 0.25, against 15.0 ms at zoom 1, with 16 times fewer pixels |
| `meshSamples: 1` ([The mesh renderer](#the-mesh-renderer)) | GPU time, a game's SVGs at zoom 1 | 23–40% less than with 4 samples |
| Skipping entries outside the viewport ([The canvas renderer](#the-canvas-renderer)) | UI thread, an example zoomed in on 455 SVGs, 21 of them in view, macOS | 1 ms a frame saved |
| Skipping entries outside the viewport ([The canvas renderer](#the-canvas-renderer)) | Main thread, the same example, web with CanvasKit | 2 ms of 7.5 ms a frame saved |
| Scenes drawn as pictures ([The canvas renderer](#the-canvas-renderer)) | UI thread, a benchmark | Half the time of drawing the paths |
