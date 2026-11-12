# The Rasterizer core

These files are a copy of [Rasterizer](https://github.com/mindbrix/Rasterizer)'s C++ core,
`Package/Sources/RasterizerCpp`, at commit `2be4bc16` (2026-10-15), with the patches below. They're this package's own
sources, edited directly, and don't follow changes upstream.

Licences:
- Rasterizer: MIT, © 2025 Nigel Timothy Barber, in `LICENSE.txt`.
- NanoSVG (`nanosvg.h`): zlib, in the header.
- xxHash (`xxhash.h`, `xxhash.c`): BSD 2-clause, in the header.

`upstream.patch` is the unified diff from the upstream files to these, apart from each file's first comment lines.
After a change here, `python3 -I ../../tool/make_patch.py <Rasterizer checkout>` writes it again.

## Patches

1. **Portability**, to build off Apple platforms:
   - `#import` becomes `#include`, so the headers get `#pragma once`.
   - GCD, `sysconf`, `__sincos`, `always_inline` and `alloca` go through `../ra_portable.h`.
2. **Device clips**: `Ra::SceneList::deviceClips` holds either nothing or one rectangle per scene, in device pixels.
   - Each rectangle clips its scene, as the device bounds clip the whole list. The atlas needs one per run. A scene's
     own clip can't do that once its transform rotates, as that clip is in the scene's coordinates.
   - A device clip narrower than the device is also each path's soft clip, which the instances shader applies, unless
     the scene or draw has its own clip. Strokes and antialiasing reach past the clip bounds, and upstream relies on
     the device's edges to cut them off.
3. **The viewBox**: NanoSVG keeps the SVG's viewBox in `NSVGimage::viewBox`, rather than dropping it. The core parses
   without units, so the paths stay in the viewBox's coordinates, and `RasterizerScene.viewBox` needs it.
4. **Bounding box gradients**, in `nsvg__createGradient`: gradients whose `gradientUnits` are `objectBoundingBox`,
   SVG's default, are laid out in the unit square, then mapped to the shape's bounds, as SVG says. Upstream's NanoSVG:
   - read their plain numbers as user units, so `x2="1"` was 1 user unit rather than the shape's width, and painted
     most such shapes in their last stop's colour;
   - applied their `gradientTransform` after the bounds rather than before;
   - kept radial gradients circles on shapes that aren't square, rather than ellipses;
   - kept linear gradients' colour bands perpendicular to the gradient in user space, rather than in the bounds.

   A bounding box gradient on a shape with no width or height isn't painted, as SVG says.
5. **Gradient opacity**: `fill-opacity` and `stroke-opacity` scale a gradient's stops' alpha, as they do a colour's.
   NanoSVG applied them to colours only.
6. **Entry opacity**: `Ra::SceneList::opacities` holds either nothing or one opacity per scene, from 0 to 1. It scales
   the alpha of each of the scene's draws, as Flame's `HasPaint` opacity does a component's paths.
   - A draw's colour is premultiplied with its alpha times the opacity. A gradient's strip, already premultiplied, has
     all of its components scaled by the opacity as it's copied into the frame.
   - Only draws whose opacity is 1 can be opaque, as opaque draws are drawn before what's beneath them.
   - A scene whose opacity is 0 is skipped, as if its draws were invisible.
7. **Elements skipped as vector_graphics_compiler skips them**, in `nanosvg.h`, so that both renderers draw the same
   shapes. NanoSVG drew the shapes of clips, masks and the elements it doesn't know, in SVG's default black.
   - Comments and CDATA sections are skipped: a `>` in them ended a tag early, and the elements after it were parsed.
   - `clipPath`, `mask`, `pattern` and `symbol` are definitions, as `defs` is: their shapes are skipped, and their
     gradients parsed. Definitions nest, and a `g` in one doesn't pop its parent's attributes at its end.
   - Elements that vector_graphics_compiler doesn't handle are skipped with their content, gradients included:
     `clippath` (SVG is case-sensitive), `marker`, `switch`, `style`, and any other name.
   - `a` is a group, whose attributes its content inherits.
   - A self-closing tag's name ends at its `/`, as in `<defs/>`, which was otherwise a start without an end.
8. **Entry colour transform**: `Ra::SceneList::colorMatrices` holds either nothing or one `Ra::ColorMatrix` per scene:
   a 4 × 4 matrix on premultiplied RGBA. It transforms each of the scene's draws' colours, as a colour filter that keeps
   alpha, such as Flame's `tint`, would transform its composited pixels.
   - A draw's colour is transformed after its premultiplication and opacity. A gradient's strip is transformed texel by
     texel as it's copied into the frame. Each transformed colour is clamped from 0 to its alpha.
   - Only draws whose matrix keeps alpha can be opaque. A scene whose matrix clears alpha is skipped, as one whose
     opacity is 0 is.
9. **P16s once per scene** (geometry cache, part 1): a scene's P16s, the geometry of its small fills, are written to
   the frame once, at its first entry's base, and its other entries share them. `Ra::Buffer::p16bases` keeps that base
   for each entry. Upstream wrote them for each entry, so a list that drew one scene many times copied and uploaded them
   each time. In the frame of a ring of 101 tigers, those copies of the tiger's 55 KB were a quarter to a third of the
   frame.
10. **Cached stroke outlines** (geometry cache, part 2): `Ra::Scene::outlines(k)` caches its strokes' `Outliner` pieces,
    in scene space at scale 2^k, built once. `Context::writeCachedOutlines` transforms them into the frame's outline
    instances, rather than outlining each stroke every frame.
    - `Ra::Buffer::prepare`, now given the frame's scale, picks each entry's set: the power of 2 at or above its scale.
      Only cubics' piece counts depend on the scale, rising with its cube root. So they're drawn at least as precisely,
      with up to about 7.5% more pieces.
    - Only entries drawn with a similarity transform use them, as the `Outliner` splits curves by angle, which skews
      and unequal scales don't keep. Only unclipped strokes use them, as the `Outliner` splits clipped ones at the clip,
      which whole pieces don't draw as precisely at high zooms. Strokes of one-line subpaths are written directly, as
      upstream writes them.
    - A scene's `prepare()` clears them, as does an `update()` that makes a fill a stroke or changes a stroke's
      transform.
    - On a ring of tigers at zooms 0.5 and 1, the core's CPU time, summed over its threads, fell by a quarter to a
      third. The Flame benchmark's tiger mode didn't change measurably.
