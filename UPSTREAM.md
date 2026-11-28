# Differences from upstream

[Rasterizer](https://github.com/mindbrix/Rasterizer), the upstream project, renders with Metal on Apple platforms, for
apps written in Swift or Objective-C. This port differs from it as follows.

## Rendering

- **Flutter GPU and GLSL replace Metal.** The build hook compiles upstream's `Shaders.metal`, ported to GLSL, into a
  shader bundle. The shaders read each frame from a data texture rather than from Metal buffers: the renderer copies the
  frame once into a host-visible buffer, then blits it into an `r32g32b32a32Float` texture, which the shaders read with
  `texelFetch`.
- **The atlas renderer, rasterizer_gpu's default, renders into an atlas.** It renders all of a frame's runs once, into
  atlas pages. A run is a sequence of SVGs that come one after another in the paint order. It then draws each run with
  `Canvas.drawImageRect` at its place in the paint order, so vector content keeps its z-order among the app's other
  content.
- **A mesh renderer, flame_rasterizer's default, is new.** It flattens each SVG once, for the largest size it's drawn
  at, and triangulates its fills and its strokes' outlines with libtess2. It draws the triangles 4× multisampled by
  default, where Flutter GPU supports offscreen multisampling. So a frame's CPU work doesn't depend on the SVGs' paths.
  Upstream works out most paths again each frame, in device space.
- **The atlas renderer works around two bugs in Impeller's Vulkan backend.** The backend reuses a texture's first render
  pass, with its load actions, for all its later passes. It also starts every depth attachment in an undefined layout,
  so depth never carries over from one pass to the next. So the atlas renderer clears its targets by drawing over them,
  and in each new pass redraws the depth of the opaque paths drawn so far.

## The core

This port patches Rasterizer's C++ core, copied from upstream's `Package/Sources/RasterizerCpp` at commit `2be4bc16`
(2026-10-15). `rasterizer_gpu/src/core/README.md` lists each patch:

- **Portability:** `std::thread` and other replacements for Grand Central Dispatch and Apple-only calls, so the core
  builds on other platforms.
- **Device clips:** a rectangle in device pixels per scene, which the atlas needs for each run. It also cuts off strokes
  and antialiasing that reach past it, as the device's edges do upstream.
- **Opacity and colour transforms per scene,** as Flame's `HasPaint` applies them to a component.
- **NanoSVG, the SVG parser,** keeps the SVG's viewBox, which it otherwise drops. It skips the elements that
  vector_graphics_compiler skips, so the GPU and canvas renderers draw the same shapes.
- **Gradients drawn as SVG and Chrome draw them.** The core maps gradients laid out on the shape's bounding box, SVG's
  default, to the shape's bounds. Upstream paints most of them in their last stop's colour. Fill and stroke opacity also
  apply to gradients, which upstream draws opaque.
- **Numbers read the same in any locale.** NanoSVG read opacities, lengths and the viewBox with the C locale's decimal
  point, so under a locale with a decimal comma, `0.5` read as 0.
- **Geometry kept across entries and frames:** the core writes the geometry of a scene's small fills once per frame,
  rather than once per entry, and caches stroke outlines.

## Platforms

- **The GPU renderers run on Metal, Android's Vulkan, and Android's, Linux's and Windows' OpenGL ES.** They don't run
  on 32-bit Android, where the package builds no native code.
- **The canvas renderer draws everywhere else:** on Skia and on web, and on OpenGL ES if the app turns
  `RasterizerGpu.allowOpenGles` off. It parses SVGs in Dart with vector_graphics_compiler, through a trimmed copy of
  `SvgPaths`, a class written for flame_svg.
- **The canvas renderer has known differences,** which come from vector_graphics_compiler:
  - on a shape that isn't square, a diagonal or rotated linear gradient laid out on its bounding box keeps its bands
    perpendicular to the gradient, rather than slanting them with the shape's proportions, as SVG does;
  - vector_graphics_compiler reads `skewX` and `skewY` angles as radians, rather than degrees;
  - antialiasing is Impeller's or Skia's, not the core's exact coverage.

## Scope

- **Not ported:** clip masks, blend modes, images, text, PDF, and the API that edits a scene's draws.
- **Added:** a Flame integration, flame_rasterizer.

## Tests

The tests render generated scenes and compare them with goldens, one set per platform, rather than with upstream's
renderer. The goldens were checked against upstream's Metal renderer, given the same frames, then against Chrome for
the gradient patches. Upstream's Metal renderer isn't in this repository.
