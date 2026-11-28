//
//  A flat C API over Ra::Scene, Ra::SceneList and Ra::Buffer, for Dart FFI.
//  Not thread safe: call it from one thread, or guard it.
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _MSC_VER
#define RA_EXPORT __declspec(dllexport)
#else
#define RA_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct RaScene RaScene;
typedef struct RaList RaList;
typedef struct RaRenderer RaRenderer;
typedef struct RaFrameBuffer RaFrameBuffer;

// Ra::Transform: x' = a * x + c * y + tx, y' = b * x + d * y + ty.
typedef struct {
    float a, b, c, d, tx, ty;
} RaTransform;

// Ra::Bounds. A null bounds has lx = ly = FLT_MAX.
typedef struct {
    float lx, ly, ux, uy;
} RaBounds;

// Ra::Params. Its clear color is BGRA, like Ra::Color.
typedef struct {
    bool useClips, useCurves, showOpaques, showOutlines;
    uint8_t clearB, clearG, clearR, clearA;
} RaParams;

// The values of Ra::Buffer::Type.
enum {
    RA_ENTRY_QUAD_EDGES, RA_ENTRY_FAST_EDGES, RA_ENTRY_FAST_MOLECULES, RA_ENTRY_QUAD_MOLECULES, RA_ENTRY_OPAQUES, RA_ENTRY_INSTANCES,
    RA_ENTRY_SEGMENTS_BASE, RA_ENTRY_INSTANCES_BASE, RA_ENTRY_DISABLE_CLIP, RA_ENTRY_ENABLE_CLIP, RA_ENTRY_CLIP_MASK,
    RA_ENTRY_BLEND_INSTANCES
};

// Ra::Buffer::Entry. begin and end are byte offsets into the frame, with two exceptions: an RA_ENTRY_INSTANCES_BASE entry's end
// is the number of accumulation rows its group uses, and an RA_ENTRY_CLIP_MASK entry's begin packs the mask's device bounds and
// its end is the mask's identity.
typedef struct {
    uint32_t type, _pad;
    uint64_t begin, end;
} RaEntry;

// One frame. It stays valid until the next ra_render into its RaFrameBuffer, or until that buffer is released.
typedef struct {
    const uint8_t *base;  uint64_t size;            // The bytes to upload
    const RaEntry *entries;  uint64_t entryCount;
    uint64_t colors, paths, texStrips, p16s;        // Section offsets: colors and paths are in the header, p16s after the strips
    uint64_t pathsCount, texCount, headerSize;
    RaParams params;
} RaFrame;

// The sizes of the structs that the shaders read, and the constants that the shaders depend on.
typedef struct {
    uint32_t color, pathData, opaque, instance, edge, segment, point16, entry;
    uint32_t colorTextureWidth, moleculesHeight, fastSegments, stripHeight;
} RaLayout;

RA_EXPORT RaLayout ra_layout(void);

// Parses an SVG file into a new scene, and writes to ctm the transform that maps the scene, which is y down, into a list's y-up
// space. ctm may be NULL. Returns NULL if the file can't be parsed or memory runs out.
RA_EXPORT RaScene *ra_scene_from_svg(const char *path, RaTransform *ctm);
// The same, from an SVG's bytes, for hosts that load them from assets. The bytes needn't be null-terminated.
RA_EXPORT RaScene *ra_scene_from_svg_data(const char *data, uint64_t length, RaTransform *ctm);
// The OpenGL ES format probe's scene: the scene that ra_scene_from_svg_data makes from probeSvg, but built without parsing, so
// that the probe tests only the GPU. Returns NULL if memory runs out.
RA_EXPORT RaScene *ra_scene_probe(RaTransform *ctm);
RA_EXPORT void ra_scene_release(RaScene *scene);
RA_EXPORT uint64_t ra_scene_count(const RaScene *scene);
RA_EXPORT RaBounds ra_scene_bounds(const RaScene *scene);
// The SVG's own rectangle in its paths' coordinates, y down: its viewBox, or if it has none, from 0, 0 to its width and height.
RA_EXPORT RaBounds ra_scene_svg_bounds(const RaScene *scene);

RA_EXPORT RaList *ra_list_create(void);
RA_EXPORT void ra_list_release(RaList *list);
// The list keeps its own reference to the scene. Empty scenes are skipped.
RA_EXPORT void ra_list_add_scene(RaList *list, RaScene *scene, RaTransform ctm);
RA_EXPORT void ra_list_set_ctm(RaList *list, RaTransform ctm);
RA_EXPORT void ra_list_set_params(RaList *list, RaParams params);
RA_EXPORT RaParams ra_list_params(const RaList *list);
// The scenes' bounds, transformed by their own transforms but not by the list's.
RA_EXPORT RaBounds ra_list_bounds(const RaList *list);

// One of a list's entries, which ra_list_set_entries sets in bulk. It holds a scene, its transform, the rectangle in device
// pixels that its draws are clipped to, its opacity from 0 to 1, which scales its draws' alpha, and its color matrix. colorMatrix
// is 0 for none, otherwise 1 plus the matrix's index in the list's color matrices. A colorMatrix past the last matrix also means
// none.
typedef struct {
    RaScene *scene;
    RaTransform ctm;
    RaBounds deviceClip;
    float opacity;
    uint32_t colorMatrix;
} RaListEntry;

// Sets the color matrices that the next entries refer to: count 4 x 4 matrices that act on premultiplied RGBA, 16 floats each,
// row by row, with rows and columns in r, g, b, a order. The list copies them. Each color a matrix transforms is clamped between
// 0 and its alpha.
RA_EXPORT void ra_list_set_color_matrices(RaList *list, const float *matrices, uint64_t count);
// Replaces the list's scenes with the entries' scenes, in order, so one call per frame sets them all. Null and empty scenes are
// skipped.
RA_EXPORT void ra_list_set_entries(RaList *list, const RaListEntry *entries, uint64_t count);

// A renderer keeps the per-thread contexts that frames reuse. A host keeps one RaFrameBuffer per frame in flight.
RA_EXPORT RaRenderer *ra_renderer_create(void);
RA_EXPORT void ra_renderer_release(RaRenderer *renderer);
RA_EXPORT RaFrameBuffer *ra_frame_buffer_create(void);
RA_EXPORT void ra_frame_buffer_release(RaFrameBuffer *buffer);

// Writes the list's frame for a w x h view in points, at scale device pixels per point, into the buffer. Returns an empty frame,
// with a null base, if it can't be written.
RA_EXPORT RaFrame ra_render(RaRenderer *renderer, const RaList *list, float w, float h, float scale, RaFrameBuffer *buffer);

// Meshes, for the mesh renderer: an SVG imported once into triangles, in its paths' coordinates, y down, like a scene's.
typedef struct RaMesh RaMesh;

// The values of RaMeshPath::type.
enum { RA_PAINT_COLOR, RA_PAINT_LINEAR, RA_PAINT_RADIAL };

// A gradient's stop: its offset, from 0 to 1 and never below the previous stop's, and its color, unpremultiplied, as SVG
// interpolates stops.
typedef struct {
    float offset, r, g, b, a;
} RaMeshStop;

// One of a mesh's paths, in paint order: a shape's fill or stroke, the indices of its triangles, and its paint. A color is r, g,
// b and a, premultiplied. A gradient's transform maps the SVG's coordinates into the gradient's own. There, a linear gradient's
// offset is y, a radial gradient's offset is the distance from 0, 0, and beyond the first and last stops the color is that
// stop's. Like scenes, meshes ignore a gradient's focal point and spread method. halfWidth is half a stroke's width, or 0 for a
// hairline or any path that isn't a stroke. halo is 1 for a glow's halo and 0 for every other path. A halo is always a color,
// and it covers what's under it as much as its strongest channel does.
typedef struct {
    uint32_t type, indexBegin, indexCount, stopBegin, stopCount;
    float r, g, b, a;
    RaTransform gradient;
    float halfWidth;
    uint32_t halo;
} RaMeshPath;

// A mesh's arrays, which stay valid until the mesh is released.
// Each vertex is vertexFloats floats. The first three are x, y and the index of the vertex's path, a float because OpenGL ES
// vertex attributes can't be integers. In a mesh with strokes (vertexFloats 5) or a glow (vertexFloats 6), the next two are the
// vertex's offset, x and y in half widths, from the point of its stroke's polyline that it's built around. The offset is 0 for
// the vertices of fills and of strokes' unions. In a mesh with a glow, the sixth float is the vertex's glow: 1 for a draw's own
// vertices, from 1 at a path's edge down to 0 at the outer edge of its halo, and from 1 up to 2 in the middle of a core.
// The indices are u16 (indexSize 2) or u32 (indexSize 4), 3 per triangle, in paint order. A stroke that overlaps itself is
// indexed as its union. stripIndices, if stripIndexCount isn't 0, are the same indices, except that opaque strokes that overlap
// themselves are indexed as their strips, for instances drawn without an opacity. bounds are the vertices' bounds, and svgBounds
// is as ra_scene_svg_bounds.
typedef struct {
    const float *vertices;  uint64_t vertexCount;
    const void *indices;  uint64_t indexCount;  uint32_t indexSize, vertexFloats;
    const void *stripIndices;  uint64_t stripIndexCount;
    const RaMeshPath *paths;  uint64_t pathCount;
    const RaMeshStop *stops;  uint64_t stopCount;
    RaBounds bounds, svgBounds;
} RaMeshData;

// Imports an SVG's bytes into a new mesh, flattening its curves to within 1/4 of a device pixel when its longer side is drawn
// maxSize device pixels long. The bytes needn't be null-terminated. Returns NULL if they can't be parsed, if maxSize isn't
// positive and finite, or if memory runs out.
RA_EXPORT RaMesh *ra_mesh_from_svg_data(const char *data, uint64_t length, float maxSize);
RA_EXPORT RaMeshData ra_mesh_data(const RaMesh *mesh);
RA_EXPORT void ra_mesh_release(RaMesh *mesh);

// Paths: plain paths, flattened into polylines in Dart, each drawn with its paint. These are the values of RaPathDraw::cap and
// join, which match NanoSVG's and Flutter's StrokeCap and StrokeJoin.
enum { RA_CAP_BUTT, RA_CAP_ROUND, RA_CAP_SQUARE };
enum { RA_JOIN_MITER, RA_JOIN_ROUND, RA_JOIN_BEVEL };

// Paths' polylines, y down. points holds x, y pairs, contour after contour. pointCounts holds each contour's number of points,
// closed whether each contour is closed (1) or open (0), and contourCounts each path's number of contours. A closed contour
// doesn't repeat its first point.
typedef struct {
    const float *points;
    const uint32_t *pointCounts;
    const uint8_t *closed;
    const uint32_t *contourCounts;
    uint64_t pathCount;
} RaContours;

// One draw of a path, in paint order.
// path is the index of its path in the contours. color is as NanoSVG's, unpremultiplied, with r in the low byte and a in the high
// one. strokeWidth, cap, join and miterLimit describe a stroke. A strokeWidth of 0 or less makes the draw a fill, which closes
// open contours. evenOdd picks a fill's rule: even-odd if set, otherwise non-zero. hairline makes the draw a stroke of width 0,
// whatever strokeWidth is; meshes import hairlines, and scenes skip them. separate makes a mesh fill each contour on its own,
// closed, instead of filling their union, and a convex contour as a fan, so that its triangles can overlap. Scenes ignore it.
typedef struct {
    uint32_t path, color;
    float strokeWidth, miterLimit;
    uint8_t cap, join, evenOdd, hairline, separate;
} RaPathDraw;

// A new scene of draws of paths, with their polylines drawn as lines. Its own rectangle (ra_scene_svg_bounds) is viewBox. Paths
// with points that aren't finite, and draws of paths that aren't in the contours, are skipped. As for SVGs, the GPU renderer's
// strokes have a fixed miter limit, and bevel joins are drawn as miters. Returns NULL if memory runs out.
RA_EXPORT RaScene *ra_scene_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox);

// The glow of a mesh's paths, like a neon tube's.
// A halo goes under all the draws and fades out over radius. For a stroked path, radius is measured from the stroke's centre
// line, and for a path that's only filled, from its contour. radius is in the paths' units, or if inWidths, in line widths:
// that many times the widest of the path's strokes, or for a fill, the shorter edge at each point of a contour. So with
// inWidths, a path whose only strokes are hairlines, which have no width, has no halo. On the path, the halo's alpha is
// strength, from 0 to 1, times the alpha of its color. That color is color, as RaPathDraw's, if hasColor, otherwise the color
// of the path's last draw that paints.
// A core over each draw turns near white down its middle, whatever strength and color are. Every stroke except a hairline has
// a core. If inWidths, so does a fill of a path that isn't stroked: its core reaches inward from each contour that is neither
// inside another contour nor around one, by half the shorter edge at each point.
typedef struct {
    float radius, strength;
    uint32_t color;
    uint8_t hasColor, inWidths;
} RaGlow;

// A new mesh of the same draws, imported as an SVG's are. Round joins and caps stay within tolerance of their arcs, in the paths'
// units. The mesh has glow unless glow is NULL, its radius isn't positive and finite, or its strength isn't positive. Each path
// that a draw paints gets one halo, a path of the mesh placed before all the draws' paths. The halo lies on both sides of the
// path's polylines if a draw strokes the path, otherwise outward from each contour, closed, on the side its orientation tells.
// Each core is a path of the mesh right after its draw's path. Returns NULL if tolerance isn't positive and finite, or if memory
// runs out.
RA_EXPORT RaMesh *ra_mesh_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox,
                                     float tolerance, const RaGlow *glow);

#ifdef __cplusplus
}
#endif
