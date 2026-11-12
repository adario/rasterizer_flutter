# Third-party notices

This repository's own code is under the MIT licence in `LICENSE`. It also holds code and data from the projects below,
under their own licences. rasterizer_gpu's `LICENSE` includes the licences of the code it bundles, for Flutter's
license registry.

## Rasterizer

https://github.com/mindbrix/Rasterizer, at commit `2be4bc16` (2026-10-15). MIT licence, also in
`rasterizer_gpu/src/core/LICENSE.txt`.

- `rasterizer_gpu/src/core/`: a patched copy of its C++ core, `Package/Sources/RasterizerCpp` (the patches are listed in
  `rasterizer_gpu/src/core/README.md`, and `upstream.patch` is the diff).
- `rasterizer_gpu/src/ra_frame.hpp`: its `RasterizerRenderer.hpp` without Metal.
- `rasterizer_gpu/shaders/`: a GLSL port of its `Shaders.metal`.
- `rasterizer_gpu/lib/src/gpu_renderer.dart`: a Dart and Flutter GPU port of its `RasterizerLayer` draw loop.

```
MIT License

Copyright 2025 Nigel Timothy Barber - nigel@mindbrix.co.uk

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## NanoSVG

https://github.com/memononen/nanosvg, as copied into Rasterizer: `rasterizer_gpu/src/core/nanosvg.h` and `nanosvg.cc`,
patched here (`rasterizer_gpu/src/core/README.md`, patches 3 to 5). zlib licence, also in the header.

```
Copyright (c) 2013-14 Mikko Mononen memon@inside.org

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

The SVG parser is based on Anti-Grain Geometry 2.4 SVG example
Copyright (C) 2002-2004 Maxim Shemanarev (McSeem) (http://www.antigrain.com/)

Arc calculation code based on canvg (https://code.google.com/p/canvg/)

Bounding box calculation based on http://blog.hackers-cafe.net/2009/06/how-to-calculate-bezier-curves-bounding.html
```

## xxHash

https://github.com/Cyan4973/xxHash, as copied into Rasterizer: `rasterizer_gpu/src/core/xxhash.h` and `xxhash.c`. BSD
2-clause licence, also in the headers.

```
xxHash - Extremely Fast Hash algorithm
Copyright (C) 2012-2020 Yann Collet

BSD 2-Clause License (https://www.opensource.org/licenses/bsd-license.php)

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
     notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
     copyright notice, this list of conditions and the following disclaimer
     in the documentation and/or other materials provided with the
     distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## libtess2

https://github.com/memononen/libtess2, at commit `8dbd648` (2025-10-15): `rasterizer_gpu/src/libtess2/`, patched to
compile as C++ (`rasterizer_gpu/src/libtess2/README.md`). SGI Free Software License B, version 2.0, also in
`rasterizer_gpu/src/libtess2/LICENSE.txt`.

```
** SGI FREE SOFTWARE LICENSE B (Version 2.0, Sept. 18, 2008) 
** Copyright (C) [dates of first publication] Silicon Graphics, Inc.
** All Rights Reserved.
**
** Permission is hereby granted, free of charge, to any person obtaining a copy
** of this software and associated documentation files (the "Software"), to deal
** in the Software without restriction, including without limitation the rights
** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
** of the Software, and to permit persons to whom the Software is furnished to do so,
** subject to the following conditions:
** 
** The above copyright notice including the dates of first publication and either this
** permission notice or a reference to http://oss.sgi.com/projects/FreeB/ shall be
** included in all copies or substantial portions of the Software. 
**
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
** INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
** PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL SILICON GRAPHICS, INC.
** BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
** TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
** OR OTHER DEALINGS IN THE SOFTWARE.
** 
** Except as contained in this notice, the name of Silicon Graphics, Inc. shall not
** be used in advertising or otherwise to promote the sale, use or other dealings in
** this Software without prior written authorization from Silicon Graphics, Inc.
```

## Flame

https://github.com/flame-engine/flame. MIT licence.

- `rasterizer_gpu/lib/src/paths/path_contours.dart`: Flame's contour sampler, `PathMetricExtension.walkContour`
  (`packages/flame/lib/src/extensions/path.dart`), at commit `8fa5abf04` (2026-10-14), changed as the file's header
  lists.
- `rasterizer_gpu/lib/src/svg_paths/`: `SvgPaths` and its conversions from vector_graphics_compiler's types, written by
  this repository's author for flame_svg (`packages/flame_svg/`), under its licence, and not merged into Flame; trimmed
  and changed as `svg_paths.dart`'s documentation lists.

```
MIT License

Copyright (c) 2021 Blue Fire

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## SVG Repo's SVGs: CC0

`rocket_ship.svg`, `missile.svg` and `spaceship_game.svg`, in `flame_rasterizer/example/assets/svgs/` (and their white
versions in `wireframe/`) and in `rasterizer_gpu/test/svgs/`, come from SVG Repo (https://www.svgrepo.com), under CC0
1.0, a public domain dedication: https://creativecommons.org/publicdomain/zero/1.0/. They need no attribution.

## The Ghostscript tiger (test data only)

`rasterizer_gpu/example/assets/tiger/tiger.svg`, and its renders in `rasterizer_gpu/example/goldens/*/*tiger*.png`, are
licensed separately, under the **AGPL-3.0-or-later**, as Wikimedia Commons lists the artwork
(https://commons.wikimedia.org/wiki/File:Ghostscript_Tiger.svg). They're test data for the example app only, and aren't
part of either package. See `rasterizer_gpu/example/assets/tiger/README.md`. The same file is one of
flame_rasterizer's example's SVGs, `flame_rasterizer/example/assets/svgs/tiger.svg`, under the same licence: see
`flame_rasterizer/example/assets/README.md`. It's also the scene of flame_rasterizer's benchmark's `--svgs tiger`,
`flame_rasterizer/benchmark/assets/tiger.svg`, under the same licence too.
