//
//  A flat C API over Ra::Scene, Ra::SceneList & Ra::Buffer, for Dart FFI.
//  Not thread safe: call it from one thread, or guard it.
//

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RA_EXPORT __attribute__((visibility("default"))) __attribute__((used))

typedef struct RaScene RaScene;
typedef struct RaList RaList;
typedef struct RaRenderer RaRenderer;
typedef struct RaFrameBuffer RaFrameBuffer;

// Ra::Transform: x' = a * x + c * y + tx, y' = b * x + d * y + ty
typedef struct {
    float a, b, c, d, tx, ty;
} RaTransform;

// Ra::Bounds. A null bounds has lx = ly = FLT_MAX
typedef struct {
    float lx, ly, ux, uy;
} RaBounds;

// Ra::Params, whose clear color is BGRA, like Ra::Color
typedef struct {
    bool useClips, useCurves, showOpaques, showOutlines;
    uint8_t clearB, clearG, clearR, clearA;
} RaParams;

// Ra::Buffer::Type
enum {
    RA_ENTRY_QUAD_EDGES, RA_ENTRY_FAST_EDGES, RA_ENTRY_FAST_MOLECULES, RA_ENTRY_QUAD_MOLECULES, RA_ENTRY_OPAQUES, RA_ENTRY_INSTANCES,
    RA_ENTRY_SEGMENTS_BASE, RA_ENTRY_INSTANCES_BASE, RA_ENTRY_DISABLE_CLIP, RA_ENTRY_ENABLE_CLIP, RA_ENTRY_CLIP_MASK,
    RA_ENTRY_BLEND_INSTANCES
};

// Ra::Buffer::Entry: byte offsets into the frame, except for RA_ENTRY_INSTANCES_BASE, whose end is the accumulation rows its group
// uses, & RA_ENTRY_CLIP_MASK, whose begin packs device bounds & end is the mask's identity
typedef struct {
    uint32_t type, _pad;
    uint64_t begin, end;
} RaEntry;

// One frame, which stays valid until the next ra_render into its RaFrameBuffer, or its release
typedef struct {
    const uint8_t *base;  uint64_t size;            // The bytes to upload
    const RaEntry *entries;  uint64_t entryCount;
    uint64_t colors, paths, texStrips, p16s;        // Section offsets: colors & paths are in the header, & p16s follow the strips
    uint64_t pathsCount, texCount, headerSize;
    RaParams params;
} RaFrame;

// The sizes of the structs the shaders read, & the constants they depend on
typedef struct {
    uint32_t color, pathData, opaque, instance, edge, segment, point16, entry;
    uint32_t colorTextureWidth, moleculesHeight, fastSegments, stripHeight;
} RaLayout;

RA_EXPORT RaLayout ra_layout(void);

// Parses an SVG file into a new scene, & writes the transform that maps it, y down, into the y-up space of a list. NULL if it can't
// be parsed
RA_EXPORT RaScene *ra_scene_from_svg(const char *path, RaTransform *ctm);
// The same, from an SVG's bytes, which needn't be null-terminated, for hosts that load them from assets
RA_EXPORT RaScene *ra_scene_from_svg_data(const char *data, uint64_t length, RaTransform *ctm);
RA_EXPORT void ra_scene_release(RaScene *scene);
RA_EXPORT uint64_t ra_scene_count(const RaScene *scene);
RA_EXPORT RaBounds ra_scene_bounds(const RaScene *scene);
// The SVG's own rectangle in its paths' coordinates, y down: its viewBox, or else from 0, 0 to its width & height
RA_EXPORT RaBounds ra_scene_svg_bounds(const RaScene *scene);

RA_EXPORT RaList *ra_list_create(void);
RA_EXPORT void ra_list_release(RaList *list);
// The list keeps its own reference to the scene. Empty scenes are skipped
RA_EXPORT void ra_list_add_scene(RaList *list, RaScene *scene, RaTransform ctm);
RA_EXPORT void ra_list_set_ctm(RaList *list, RaTransform ctm);
RA_EXPORT void ra_list_set_params(RaList *list, RaParams params);
RA_EXPORT RaParams ra_list_params(const RaList *list);
// The scenes' bounds, through their transforms, but not the list's
RA_EXPORT RaBounds ra_list_bounds(const RaList *list);

// One of a list's entries, set in bulk: a scene, its transform, the rectangle in device pixels its draws are clipped to, its
// opacity, from 0 to 1, which scales its draws' alpha, & its color matrix: 0 for none, else 1 + its index in the list's color
// matrices
typedef struct {
    RaScene *scene;
    RaTransform ctm;
    RaBounds deviceClip;
    float opacity;
    uint32_t colorMatrix;
} RaListEntry;

// Sets the color matrices the next entries refer to: count 4 x 4 matrices on premultiplied RGBA, 16 floats each, row by row,
// their rows & columns r, g, b, a. Each color they transform is clamped from 0 to its alpha
RA_EXPORT void ra_list_set_color_matrices(RaList *list, const float *matrices, uint64_t count);
// Replaces the list's scenes with the entries', in order, so one call per frame sets them all. Empty scenes are skipped
RA_EXPORT void ra_list_set_entries(RaList *list, const RaListEntry *entries, uint64_t count);

// A renderer keeps the per-thread contexts that frames reuse. A host keeps one RaFrameBuffer per frame in flight
RA_EXPORT RaRenderer *ra_renderer_create(void);
RA_EXPORT void ra_renderer_release(RaRenderer *renderer);
RA_EXPORT RaFrameBuffer *ra_frame_buffer_create(void);
RA_EXPORT void ra_frame_buffer_release(RaFrameBuffer *buffer);

// Writes the list's frame for a w x h view in points, at scale device pixels per point, into the buffer
RA_EXPORT RaFrame ra_render(RaRenderer *renderer, const RaList *list, float w, float h, float scale, RaFrameBuffer *buffer);

// Meshes, for the mesh renderer: an SVG imported once into triangles in its paths' coordinates, y down, as a scene's
typedef struct RaMesh RaMesh;

// RaMeshPath::type
enum { RA_PAINT_COLOR, RA_PAINT_LINEAR, RA_PAINT_RADIAL };

// A gradient's stop: its offset, from 0 to 1 & never below the previous stop's, & its color, unpremultiplied, as SVG
// interpolates them
typedef struct {
    float offset, r, g, b, a;
} RaMeshStop;

// One of a mesh's paths, in paint order: a shape's fill or its stroke, its triangles' indices & its paint. A color is r, g, b & a,
// premultiplied. A gradient's transform maps the SVG's coordinates into the gradient's, where a linear gradient's offset is y,
// & a radial one's the distance from 0, 0, & its color is its first or last stop's beyond them; its focal point & spread
// method are ignored, as in scenes. halfWidth is a stroke's, 0 for a fill or a hairline. halo is 1 for a glow's halo, always a
// color, which covers what's under it as much as its strongest channel, & 0 for the others
typedef struct {
    uint32_t type, indexBegin, indexCount, stopBegin, stopCount;
    float r, g, b, a;
    RaTransform gradient;
    float halfWidth;
    uint32_t halo;
} RaMeshPath;

// A mesh's arrays, valid until its release. Each vertex is vertexFloats floats: x, y & its path's index, as OpenGL ES vertex
// attributes can't be integers, & in a mesh with strokes (vertexFloats 5) its offset from the point of its stroke's polyline it's
// built around, x & y in half widths, 0 for those of fills & of strokes' unions. In a mesh with a glow (vertexFloats 6) the offset
// is followed by its glow: 1 for a draw's own vertices, from 1 at a path's edge to 0 at the edge of its halo, & from 1 up to 2 in
// the middle of a core. The indices are u16 (indexSize 2) or u32 (4), 3 per triangle, in paint order, those of strokes that overlap themselves their unions'.
// stripIndices, if stripIndexCount isn't 0, are the same but for opaque strokes that overlap themselves, their strips', for
// instances drawn without an opacity. bounds are the vertices', & svgBounds as ra_scene_svg_bounds
typedef struct {
    const float *vertices;  uint64_t vertexCount;
    const void *indices;  uint64_t indexCount;  uint32_t indexSize, vertexFloats;
    const void *stripIndices;  uint64_t stripIndexCount;
    const RaMeshPath *paths;  uint64_t pathCount;
    const RaMeshStop *stops;  uint64_t stopCount;
    RaBounds bounds, svgBounds;
} RaMeshData;

// Imports an SVG's bytes, which needn't be null-terminated, into a new mesh, its curves flattened to within 1/4 of a device pixel
// when its longer side is maxSize device pixels. NULL if it can't be parsed, or maxSize isn't positive
RA_EXPORT RaMesh *ra_mesh_from_svg_data(const char *data, uint64_t length, float maxSize);
RA_EXPORT RaMeshData ra_mesh_data(const RaMesh *mesh);
RA_EXPORT void ra_mesh_release(RaMesh *mesh);

// Paths: plain paths, flattened into polylines in Dart, each drawn with its paint. RaPathDraw::cap & join, as NanoSVG's
// & Flutter's StrokeCap & StrokeJoin
enum { RA_CAP_BUTT, RA_CAP_ROUND, RA_CAP_SQUARE };
enum { RA_JOIN_MITER, RA_JOIN_ROUND, RA_JOIN_BEVEL };

// Paths' polylines, y down: their points, x & y, contour after contour, each contour's count of points & whether it's closed,
// 1, or open, 0, & each path's count of contours. A closed contour doesn't repeat its first point
typedef struct {
    const float *points;
    const uint32_t *pointCounts;
    const uint8_t *closed;
    const uint32_t *contourCounts;
    uint64_t pathCount;
} RaContours;

// One draw of a path, in paint order: the index of its path in the contours; its color, as NanoSVG's, r in the low byte & a in
// the high one, unpremultiplied; its stroke's width, cap, join & miter limit, or a width of 0 for a fill, which closes open
// contours; whether a fill is even-odd, else non-zero; & whether it's a hairline, a stroke of width 0, whatever strokeWidth is,
// which meshes import & scenes skip
typedef struct {
    uint32_t path, color;
    float strokeWidth, miterLimit;
    uint8_t cap, join, evenOdd, hairline;
} RaPathDraw;

// A new scene of draws of paths, their polylines drawn as lines, whose own rectangle (ra_scene_svg_bounds) is viewBox. Paths with
// points that aren't finite, & draws of paths that aren't in the contours, are skipped. As for SVGs, the GPU renderer's strokes
// have a fixed miter limit, & bevel joins are miters
RA_EXPORT RaScene *ra_scene_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox);

// The glow of a mesh's paths, as a neon tube's: a halo under all their draws, which fades out over radius: from a stroke's centre
// line, or a fill's contour, in the paths' units, or if inWidths, in line widths: that many times a stroke's width, the widest of a
// path's strokes, or a fill's shorter edge at each point of a contour, & a hairline, of no width, has none. Its alpha on the path is
// strength, from 0 to 1, of its color, as RaPathDraw's, if hasColor, else of the color of the path's last draw. A core over each draw
// turns near white down its middle, whatever strength & color: a stroke's, or if inWidths, a fill's that isn't of a stroked path,
// inward of each contour neither inside another nor around one, half of the shorter edge at each point. A hairline has none
typedef struct {
    float radius, strength;
    uint32_t color;
    uint8_t hasColor, inWidths;
} RaGlow;

// A new mesh of the same draws, as an SVG's: round joins & caps within tolerance of their arcs, in the paths' units, & with glow
// unless it's NULL, or its radius or strength isn't positive. A halo is a path of the mesh, before all the draws' paths, one per
// path drawn: on both sides of its polylines if a draw strokes it, else outward from each contour, closed, which its winding tells.
// A core is a path of the mesh right after its draw's. NULL if tolerance isn't positive
RA_EXPORT RaMesh *ra_mesh_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox,
                                     float tolerance, const RaGlow *glow);

#ifdef __cplusplus
}
#endif
