# flame_rasterizer

Flame components that draw SVGs and paths with
[rasterizer_gpu](https://github.com/adario/rasterizer_flutter/tree/main/rasterizer_gpu)'s renderers.

A game with `HasRasterizer` draws its SVGs and paths with rasterizer_gpu's mesh renderer by default. The mesh renderer
imports each SVG or path once, into triangles that stay on the GPU. Each frame then sends only the components'
transforms, so its CPU cost doesn't depend on how many paths the SVGs have. Consecutive vector components form a run,
which the renderer draws as one image, at its place in the paint order. It renders that image at the device's
resolution, under the camera's transform, so vectors stay sharp at any zoom.

Two apps show the package, each with its own README:

- **[example](https://github.com/adario/rasterizer_flutter/tree/main/flame_rasterizer/example)** is a Widgetbook,
  laid out like Flame's examples. In each use case, a knob picks rasterizer_gpu's mesh, atlas or canvas renderer, or
  flame_svg:
  - a ring of up to 500 SVGs;
  - SVGs that collide through `SvgHitbox`es;
  - SVGs, or their outlines as paths, tinted while they collide;
  - SVG bodies in a `Forge2DGame`, which collide as the convex pieces of their outlines;
  - three games: a shooter drawn with SVGs, a tube shooter drawn with paths, and a pinball with SVG bodies.

  Each has live Zoom and Speed knobs, and a status bar with frame times and the renderer's numbers.
- **[benchmark](https://github.com/adario/rasterizer_flutter/tree/main/flame_rasterizer/benchmark)** has a demo, a
  benchmark against flame_svg, and a check that compares the Flame frame with the same frame composed directly with
  rasterizer_gpu.

## Setup

The app turns on Flutter GPU as rasterizer_gpu asks (see
[its README](https://github.com/adario/rasterizer_flutter/blob/main/rasterizer_gpu/README.md#app-setup)):

- **iOS and macOS:** `FLTEnableFlutterGPU` in the app's `Info.plist`.
- **Linux:** `fl_dart_project_set_enable_flutter_gpu` in the app's runner, `linux/runner/my_application.cc`.
- **Windows:** `project.set_enable_flutter_gpu(true)` in the app's runner, `windows/runner/main.cpp`.
- **Android:** nothing to set up. Debug and profile builds can ask for Vulkan or OpenGL ES with a key in the app's
  manifest.
- **Web:** nothing to set up. The canvas renderer draws there.

On OpenGL ES, which some Android devices and all of Linux and Windows use, the GPU renderer draws from the game's
first frame, as elsewhere. There, creating the game's renderer compiles its shaders, once: for the mesh renderer, that
takes about 0.1 s on the Android emulator and about 1 s on Linux's software renderer (see
[rasterizer_gpu's README](https://github.com/adario/rasterizer_flutter/blob/main/rasterizer_gpu/README.md#opengl-es)).
`rasterizerReady` completes once they've compiled. So a game that awaits it in `onLoad` shows `GameWidget`'s
`loadingBuilder` meanwhile, and its first frame doesn't wait for the shaders. If they haven't compiled within
`RasterizerGpu.warmUpTimeout`, 5 s by default, the canvas renderer draws instead.
To draw with the canvas renderer on OpenGL ES, set `RasterizerGpu.allowOpenGles` to false before `runApp`.

Where the game's GPU renderer isn't supported (`RasterizerGpu.of(RasterizerBackend.mesh).support` for the mesh
renderer), the canvas renderer draws instead, and debug and profile builds print a message that says why. The canvas
renderer draws each run's paths straight into the game's canvas, with no GPU image. To use it everywhere, set
`RasterizerGpu.forceCanvas` before loading the game's SVGs.

flame_rasterizer needs Flame's main branch (`flame: ^2.0.0-dev.1`) for `SvgHitbox`. So the game overrides `flame`, and
`flame_svg` if it uses it, with Flame's GitHub repository, as this repository's root `pubspec.yaml` does.

## Use

```dart
class MyGame extends FlameGame with HasRasterizer {
  @override
  Future<void> onLoad() async {
    // The asset's full path, as Flame.assets loads it. Any number of
    // components can share the SVG.
    final coin = await RasterizerSvg.load('assets/coin.svg');
    world.addAll([
      for (final p in positions)
        RasterizerSvgComponent(
          svg: coin,
          position: p,
          size: Vector2.all(64),
          anchor: Anchor.center,
        ),
    ]);
    // Optional: otherwise the vectors appear once the renderer is ready.
    // Meanwhile, GameWidget's loadingBuilder shows.
    await rasterizerReady;
  }
}
```

- **`HasRasterizer`** goes on a `FlameGame` with any world, such as a `Forge2DGame` with its `Forge2DWorld`, or a
  `FlameGame<MyWorld>`.
- **`RasterizerSvg.load`'s `maxSize`** is the largest size, in device pixels, at which the game draws the SVG's longer
  side. It defaults to the view's longer side, for a full-screen SVG. Pass the largest size the game draws it at, such
  as its component's longer side times the camera's largest zoom and the device pixel ratio:
  `RasterizerSvg.load('assets/coin.svg', maxSize: 64 * 4 * ratio)`. The mesh renderer flattens the SVG's curves once,
  for that size, to within 1/4 of a pixel. It then draws the same triangles at every size, with no level of detail.
  Drawn larger, the curves show their segments. Drawn far smaller, each pixel pays for many triangles.
- **`rasterizerGpu`**, overridden on the game, picks rasterizer_gpu's GPU renderer. `RasterizerBackend.mesh`, the mesh
  renderer, is the default. `RasterizerBackend.gpu` picks the atlas renderer, which rasterizes the SVGs each frame, and
  whose edges have the core's exact coverage. The game's SVGs must be loaded for the same renderer
  (`RasterizerSvg.load(..., gpu:)`): drawing one loaded for the other throws. Other members tune the renderer. The game
  reads `rasterizerGpu`, `rasterizerMeshSamples` and `rasterizerSlots` once, when it creates the renderer:
  - `rasterizerMeshSamples` is the mesh renderer's samples per pixel, 4 or 1. With 4, the default, it antialiases edges
    with MSAA, where the device supports offscreen MSAA. With 1, it draws them aliased, which costs less GPU time where
    many SVGs overlap.
  - `rasterizerSlots` is the number of frames in flight, 2 by default. Each one costs its own atlas pages or targets.
    An app that captures the game's frames after they're drawn, such as with `RepaintBoundary.toImage`, needs 3.
  - `rasterizerCurves`, a field that's true by default, has the atlas renderer draw curves as quadratics rather than
    line segments. The mesh renderer ignores it.
- **`SvgHitbox(svg.outline, size: size)`** is a Flame `PathHitbox` in the shape of the SVG's paths, for collisions that
  follow them rather than the SVG's rectangle. Add it to the `RasterizerSvgComponent`. The hitbox stretches to the
  component's size, as the SVG does, also when that size changes.
  - `svg.outline`, rasterizer_gpu's `SvgOutline`, holds the SVG's paths. The first time it's read, it parses them in
    Dart, whatever the renderer.
  - Filled paths collide over their area. Paths that are only stroked collide along the middle of the stroke, and their
    open contours don't collide at all.
  - Hitboxes made from the same outline at the same size share their polygons. The outline keeps the polygons of its
    last 8 sizes, so a game can make hitboxes over and over, as for spawned enemies, at almost no cost.
- **`RasterizerSvgComponent`** is a `PositionComponent` that draws its SVG's viewBox stretched to its size, as
  `SpriteComponent` draws a sprite. Its size defaults to the SVG's. Its name doesn't clash with flame_svg's
  `SvgComponent`, so a game can import both packages without a prefix. Any component can also draw an SVG from its own
  `render`, with `svg.render(canvas, size)`.
- **Paints and effects:** `RasterizerSvgComponent` has Flame's `HasPaint`, so `OpacityEffect`, `ColorEffect` and
  `HueEffect` work on it, as does its `paint:` argument. Any component can pass a paint with
  `svg.render(canvas, size, overridePaint: paint)`:
  - Its opacity fades each of the SVG's paths, so paths that overlap show through each other, unlike in a sprite.
    Components that differ only by opacity share a run, so fading many costs next to nothing.
  - Its tint (`tint`, `ColorEffect`) and hue (`HueEffect`) filter each of the SVG's paths, to the colors a sprite's
    pixels would get. Components that differ only by them share a run too, so tinting many costs next to nothing.
  - `RasterizerSvgComponent` makes those filters with `RasterizerColorTransform`, the only filters flame_rasterizer can
    read back. Another paint can take one too, such as a greyscale matrix:
    `paint.colorFilter = RasterizerColorTransform.matrix(…)!.filter`.
  - A matrix's results, such as a hue's, are clamped per path. Along the antialiased edges between paths, that differs
    from a sprite by up to 40/255, for a hue of 2 radians. A tint is exact.
  - The paint's other fields apply to the run's image, as to a sprite: other color filters (such as `modulate`, which
    changes alpha), an image filter (such as a blur), a blend mode, and inverted colors. Each different one starts a
    run.
- **`RasterizerPathComponent`** is a Flame `PathComponent` drawn in the game's runs, as `RasterizerSvgComponent`s are.
  It takes `PathComponent`'s parameters, and a `maxSize`. It draws as an SVG of its path would, with one `<path>` per
  paint layer, such as `RasterizerPathComponent(path: star, paintLayers: [fill, outline], scale: Vector2.all(2))`. The
  first time it's drawn, it imports its path, with its paint layers, for the game's renderer. Its polygons and
  `containsPoint` are `PathComponent`'s.
  - Its `maxSize` is the largest size, in device pixels, at which the game draws its path's longer side, as for
    `RasterizerSvg.load`: the path's longer side times its scale, the camera's largest zoom and the device pixel ratio.
  - Its path must not change: the GPU renderers flatten it once (see rasterizer_gpu's README, Paths).
  - Components made with the same `Path` object share an import while they draw it for the same renderer, with the
    same `maxSize`, glow and paint layers. Without paint layers, their paints must also match in the fields that draw
    as a layer's. So make a shape's components from one path, size them with `scale`, and they cost one import.
  - Its paint layers are the content, as an SVG's paths are. Changing one imports the path again, without flattening
    it again. It applies a layer's own color filter, if `RasterizerColorTransform` made it, to the layer's color.
  - It draws its `paint` over the layers, as a `RasterizerSvgComponent` does over its SVG. `OpacityEffect`,
    `ColorEffect`, `HueEffect` and `tint` fade and filter each layer in the run, with no new import, so faded and
    tinted components share runs and imports. The paint's other fields apply to an image, which starts a run.
  - Without paint layers, its paint does both jobs. Its color's RGB, style, strokes, antialiasing and shader are the
    content. Its alpha and other fields are drawn over it.
  - So it differs from Flame's `PathComponent`, which doesn't draw its `paint` when it has paint layers. Effects show on
    it with layers, and `hue` leaves the layers' own filters alone. Fade it with an `OpacityEffect` on the component,
    rather than on `opacityProviderOfList()`, which fades its layers and its paint, and imports the path each frame.
  - `glow: RasterizerGlow(radius)` adds a neon glow around its path: a halo, and a near-white core down its strokes.
    The glow is made at import, so its opacity and tint follow the component's. Only the mesh renderer draws it. The
    atlas and canvas renderers draw the path without it.
  - While the GPU renderers can't draw a layer (rasterizer_gpu's `RasterizerScene.canDraw`), such as one with another
    color filter, a shader, or a hairline stroke, the component draws its layers with `Canvas.drawPath`, as Flame's
    does, with its `paint` over them. That ends the run.
- **`RasterizerPolygonsComponent`** draws a `RasterizerPolygons`, rasterizer_gpu's shape made of polygons, the way a
  `RasterizerPathComponent` without paint layers draws a path. Use it for shapes that a game rebuilds often, such as
  every frame. The GPU renderers draw polygons without flattening them into lines, and the component doesn't make
  hit-test polygons, as Flame's `PathComponent` does. Its size is the size of the polygons' bounds. With
  `separate: true`, the mesh renderer fills each polygon on its own instead of filling their union. That's much faster,
  but where polygons overlap, the overlap shows through an opacity (see rasterizer_gpu's README, Paths). Components made
  with the same polygons share one import.
- **Runs** split only where the game draws something else between vector components, such as a sprite, text, or a path
  component drawn with `Canvas.drawPath`. A clip or a layer (`saveLayer`) between them splits them too, and so do paints
  that differ by more than opacity, tint and hue. Transforms don't split runs. So give vector components a priority
  above the canvas-drawn components they don't overlap, such as SVG bodies above a `Forge2DGame`'s balls and walls. They
  then draw in one run, rather than in one run each where the tree's order puts other bodies between them, as the
  example's Forge2D use case shows.
- **With the mesh renderer,** each run costs a render pass, and a target the size of its components' bounds on screen.
  Consecutive components that show the same SVG make one instanced draw. The renderer releases a target that no frame
  needed for 120 frames. A target whose run needed less than 3/4 of it for 120 frames shrinks to what the run needed.
  After a viewport change, every target shrinks to what its run needs at the end of the next 120 frames.
- **With the atlas renderer,** each run costs a rectangle of the atlas, the size of its components' bounds on screen.
  The whole frame costs one render per atlas page, usually one. Atlas pages grow at once to what a frame needs. They
  shrink after 120 frames that all needed less than half of them, or after a rotation or a window resize.
- **`rasterizer?.trimAtlas()`** shrinks the atlas pages to the last frame's needs at once, and frees the pages it
  didn't need. With the mesh renderer, it frees the run targets, which later frames make again as needed. Call it when
  the game knows its frames got lighter, such as at a level change (see rasterizer_gpu's README).

## How it works

While the game draws its tree, `HasRasterizer` wraps the game's canvas in a `RasterizerCanvas`. Vector components draw
nothing into it. Instead, each adds an entry to the current run, with the canvas's transform at that point. That
transform already includes Flame's component, parent and camera transforms, perspective included.

Anything else drawn ends the run first. The `RasterizerCanvas` then places the run, in its own target with the mesh
renderer, or in the atlas with the atlas renderer (rasterizer_gpu's `RasterizerRun.place`), and draws its image into the
real canvas, before the other draw. Clips, layers, and the restores that undo them end runs too, as the
`RasterizerCanvas` draws a run's image under the canvas state at the run's end.

After the tree, the mixin renders the frame once, before Flutter rasterizes the picture that draws the runs' images.
With the canvas renderer, each run draws its entries into the real canvas when it ends, and there's nothing to render.

## Limits

- **Pictures of their own:** vector components drawn into a picture of their own, as by a `Snapshot`, a camera's post
  process or a Flame `Layer`, draw their paths there with dart:ui, as the canvas renderer does, without a GPU image.
  With a GPU renderer, each SVG is first parsed in Dart for that. Drawing then costs what the canvas renderer's does,
  so a post process over thousands of SVGs is slower than the game's own canvas.
- **Perspective:** the mesh and canvas renderers draw vector components under perspective, such as from a
  `Rotate3DDecorator`, exactly, in their run. The atlas renderer draws each one in a run of its own, warped. It renders
  the image flat, at the perspective's scale at its center, then resamples it. So the image is a little softer than a
  flat one. And what the flat image would put outside the game's area isn't drawn, which can lose a sliver of a
  component turned strongly near the edge.
- **Off the pixel grid:** in a game placed off the device pixel grid, such as a `GameWidget` at a fractional offset, the
  GPU renderers snap the vectors to the nearest device pixel. They stay sharp, but up to half a pixel off from the
  game's other content. The canvas renderer doesn't snap. Full-screen games are on the grid.
- **Large games:** a game larger than its renderer allows (`rasterizer?.maxViewportSize`: 8192 device pixels a side, or
  4096 on OpenGL ES), such as a window over 4096 pixels wide on Linux, has its vectors rendered at a lower pixel ratio,
  to fit. Their images are then scaled up, so they look a little softer.
- **Drawing differences:** no renderer applies an SVG's clip paths. Neither GPU renderer draws the caps of a
  zero-length subpath (a dot). With the mesh renderer, strokes thinner than a pixel on screen come out dotted. The
  atlas renderer draws bevel joins as miters, with its own miter limit. It also blends a translucent or faded stroke
  twice where the stroke crosses itself. See rasterizer_gpu's README.
- **Changed paths:** changing a `RasterizerPathComponent`'s path after it's drawn is undefined. The GPU renderers keep
  drawing it as it was, and the canvas renderer as it was or as it is. Give a changed shape a new path, and a new
  component.

## Licence

MIT, © 2026 Dario Accornero (`LICENSE`). rasterizer_gpu, which it depends on, includes third-party code: see the
repository's `THIRD_PARTY_NOTICES.md`.
