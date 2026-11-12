# libtess2

These files are a copy of [libtess2](https://github.com/memononen/libtess2)'s `Source/` and `Include/`, at commit
`8dbd648` (2025-10-15): the GLU reference tessellator, refactored by Mikko Mononen. The mesh renderer tessellates SVG
fills and stroke outlines with it, once per SVG.

Licence: SGI Free Software License B, version 2.0, in `LICENSE.txt` and each file's header.

## Patches

1. **Compiled as C++**, as the build hook compiles every source:
   - `Source/dict.c` casts `dict->frame`, a `void *`, to `TESStesselator *` in its two calls of `dict->leq`. C converts
     it implicitly.
   - `Source/bucketalloc.c` includes `bucketalloc.h`, so that its functions get the C linkage that the header declares,
     which the other files call them with.
