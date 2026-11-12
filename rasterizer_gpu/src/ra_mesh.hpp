//
//  Meshes: an SVG imported once into triangles in its own coordinates, y down, which the mesh renderer uploads once &
//  draws under each component's transform. NanoSVG parses it & RasterizerSVG.hpp writes each shape's Geometry, as for a
//  scene. Its curves are flattened once, within a tolerance. Fills are tessellated by libtess2 with their winding rule, &
//  strokes outlined, with their joins, caps & dashes, as strips of triangles, or where a strip overlaps itself, libtess2's
//  non-zero union of it. So the triangles are each path's coverage, holes, overlaps & self-crossings included, & never
//  overlap within a path. Plain paths come flattened already, as polylines (ra_paths.hpp), & import the same way.
//  A stroke's strip also holds each vertex's offset from the polyline point it's built around, for the vertex shader to
//  hold the stroke at a least width on screen. A union's crossings come from no point, so an opaque stroke that overlaps itself
//  keeps its strip too, in a second list of indices, for the instances drawn without an opacity, whose overlaps can't show.
//  A path can glow, as a neon tube: a halo, a ribbon around it of triangles with a per-vertex falloff, a path of the mesh
//  painted before all the others, & a core, another over each draw, that turns near white down its middle, a path of the mesh
//  right after it. Both are in both lists of indices, so the instanced draw that paints each instance's path paints them too.
//

#pragma once

#include <float.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <atomic>
#include <unordered_map>
#include <vector>
#include "ra_capi.h"
#include "ra_paths.hpp"
#include "RasterizerSVG.hpp"
#include "tesselator.h"

struct RaMesh {
    std::vector<float> vertices;            // Per vertex x, y & its path's index, & in a mesh with strokes its offset, then a glow's
    uint32_t vertexFloats = 3;              // Per vertex: 3, 5 in a mesh with strokes, or 6 in a mesh with a glow
    std::vector<uint16_t> indices16;        // The triangles in paint order, in one of them: u16 when each index is below
    std::vector<uint32_t> indices32;        // 0xFFFF, some APIs' primitive restart, else u32
    std::vector<uint16_t> stripIndices16;   // The same with opaque overlapping strokes' strips for their unions, in one of
    std::vector<uint32_t> stripIndices32;   // them, u16 as above, if hasStrips
    bool hasStrips = false;
    std::vector<RaMeshPath> paths;
    std::vector<RaMeshStop> stops;
    Ra::Bounds bounds;
    RaBounds svgBounds = { 0.f, 0.f, 0.f, 0.f };
};

struct RasterizerMesh {
    static constexpr float kTolerancePixels = 0.25f;     // At maxSize
    static constexpr int kMaxCurveSegments = 1024;
    static constexpr float kMaxDashes = 1e5f;           // Per shape, past which its stroke is drawn undashed

    struct Point {
        float x, y;
    };
    struct StrokeVertex {
        Point p, u;     // Its position, & its offset from the polyline point it's built around, in half widths
    };
    struct VertexKey {
        uint64_t p, u;
        bool operator==(const VertexKey& other) const { return p == other.p && u == other.u; }
    };
    struct VertexKeyHash {
        size_t operator()(const VertexKey& key) const { return size_t(key.p ^ (key.u * 0x9E3779B97F4A7C15ull)); }
    };
    struct Subpath {
        std::vector<Point> points;  bool closed = false;    // A closed subpath doesn't repeat its first point
    };
    struct Drawn {
        bool painted = false, stroked = false;  float width = 0.f;  uint32_t color = 0;     // Of a path, by its draws
    };
    struct Stroker;
    struct Ribbon;

    // libtess2's sweep can run away on a path, adding crossings without end at gigabytes a second. So its tessellations draw on
    // a budget of live bytes: past it its allocations fail, its sweep gives up & the path isn't drawn. A sweep that gives up
    // leaves its dictionary & priority queue behind, so this owns every block, & frees what libtess2 didn't
    struct TessMemory {
        static constexpr size_t kLeastBudget = size_t(64) << 20;    // Some 190,000 crossings
        static constexpr size_t kBudgetPerPoint = 4096;             // Some 12 crossings
        struct Block {
            Block *prev, *next;  size_t size, unused;               // 32 bytes, so what follows is aligned as malloc's
        };
        Block blocks = { &blocks, &blocks, 0, 0 };
        size_t budget, used = 0;
        bool exceeded = false;
        TESSalloc alloc = TESSalloc();

        explicit TessMemory(size_t points) : budget(kLeastBudget + kBudgetPerPoint * points) {
            alloc.memalloc = allocate, alloc.memrealloc = reallocate, alloc.memfree = release, alloc.userData = this;
        }
        TessMemory(const TessMemory&) = delete;
        ~TessMemory() {
            for (Block *block = blocks.next, *next; block != &blocks; block = next)
                next = block->next, free(block);
        }
        bool fits(size_t size) {
            exceeded |= used + size > budget;
            return used + size <= budget;
        }
        static void *allocate(void *userData, unsigned int size) {
            TessMemory *self = static_cast<TessMemory *>(userData);
            Block *block = self->fits(size) ? static_cast<Block *>(malloc(sizeof(Block) + size)) : nullptr;
            if (block == nullptr)
                return nullptr;
            block->prev = &self->blocks, block->next = self->blocks.next, block->size = size;
            block->prev->next = block->next->prev = block;
            self->used += size;
            return block + 1;
        }
        static void *reallocate(void *userData, void *ptr, unsigned int size) {
            if (ptr == nullptr)
                return allocate(userData, size);
            TessMemory *self = static_cast<TessMemory *>(userData);
            size_t old = (static_cast<Block *>(ptr) - 1)->size;
            Block *block = self->fits(size > old ? size - old : 0) ? static_cast<Block *>(realloc(static_cast<Block *>(ptr) - 1, sizeof(Block) + size)) : nullptr;
            if (block == nullptr)
                return nullptr;
            block->prev->next = block->next->prev = block;
            block->size = size;
            self->used += size - old;
            return block + 1;
        }
        static void release(void *userData, void *ptr) {
            if (ptr == nullptr)
                return;
            TessMemory *self = static_cast<TessMemory *>(userData);
            Block *block = static_cast<Block *>(ptr) - 1;
            block->prev->next = block->next, block->next->prev = block->prev;
            self->used -= block->size;
            free(block);
        }
    };
    // The first tessellation in a process to pass its budget is reported, & with RASTERIZER_TESS_BUDGET_FILE set to a path,
    // its contours are written there, the coordinates as hex floats, so exactly, to reproduce it with
    static void reportExceeded(const TessMemory& memory, int windingRule, const std::vector<Subpath>& contours) {
        static std::atomic_flag reported = ATOMIC_FLAG_INIT;
        if (!memory.exceeded || reported.test_and_set())
            return;
        const char *name = getenv("RASTERIZER_TESS_BUDGET_FILE");
        if (name == nullptr || *name == '\0') {
            fprintf(stderr, "RasterizerMesh: a path passed libtess2's budget of %zu bytes, and wasn't drawn: set "
                "RASTERIZER_TESS_BUDGET_FILE to a path, such as rasterizer_tess_budget.txt in a temporary folder, to write "
                "its contours there\n", memory.budget);
            return;
        }
        fprintf(stderr, "RasterizerMesh: a path passed libtess2's budget of %zu bytes, and wasn't drawn: %s\n", memory.budget, name);
        FILE *file = fopen(name, "w");
        if (file == nullptr)
            return;
        fprintf(file, "budget %zu rule %d contours %zu\n", memory.budget, windingRule, contours.size());
        for (const Subpath& contour: contours) {
            fprintf(file, "%zu", contour.points.size());
            for (const Point& p: contour.points)
                fprintf(file, " %a %a", p.x, p.y);
            fputc('\n', file);
        }
        fclose(file);
    }
    static void reportExceeded(const TessMemory& memory, int windingRule, const std::vector<StrokeVertex>& strip) {
        if (!memory.exceeded)
            return;
        std::vector<Subpath> triangles(strip.size() / 3);
        for (size_t i = 0; i < triangles.size(); i++)
            triangles[i].points = { strip[3 * i].p, strip[3 * i + 1].p, strip[3 * i + 2].p };
        reportExceeded(memory, windingRule, triangles);
    }

    // Imports image's visible shapes, as RaSVG::addSvgImageToScene adds them to a scene: each shape's fill, then its stroke. The
    // curves are flattened to within kTolerancePixels device pixels at maxSize, the device pixels that the SVG's longer side is
    // drawn at, at most
    static RaMesh *createMesh(NSVGimage *image, RaBounds svgBounds, float maxSize) {
        RaMesh *mesh = new RaMesh();
        mesh->svgBounds = svgBounds;
        float side = fmaxf(svgBounds.ux - svgBounds.lx, svgBounds.uy - svgBounds.ly);
        if (!(side > 0.f)) {     // No viewBox, width or height, so the shapes' own
            Ra::Bounds b;
            for (NSVGshape *shape = image->shapes; shape != NULL; shape = shape->next)
                b.extend(shape->bounds[0], shape->bounds[1]), b.extend(shape->bounds[2], shape->bounds[3]);
            side = b.isNull() ? 1.f : fmaxf(1e-6f, fmaxf(b.ux - b.lx, b.uy - b.ly));
        }
        float tolerance = kTolerancePixels * side / maxSize;
        std::vector<Subpath> subpaths;
        for (NSVGshape *shape = image->shapes; shape != NULL; shape = shape->next) {
            if ((shape->flags & NSVG_FLAGS_VISIBLE) == 0)
                continue;
            Ra::Path path;
            RaSVG::writePathFromShape(shape, path);
            if (!path->isValid())
                continue;
            Ra::Bounds b = path->bounds;
            if (!isfinite(b.lx) || !isfinite(b.ly) || !isfinite(b.ux) || !isfinite(b.uy))
                continue;
            flatten(*path.ptr, tolerance, subpaths);
            RaMeshPath paint;  std::vector<RaMeshStop> stops;
            if (shape->fill.type != NSVG_PAINT_NONE && paintFromPaint(shape->fill, shape->opacity, paint, stops))
                addFill(subpaths, shape->fillRule == NSVG_FILLRULE_EVENODD, paint, stops, *mesh);
            if (shape->stroke.type != NSVG_PAINT_NONE && shape->strokeWidth > 0.f && paintFromPaint(shape->stroke, shape->opacity, paint, stops)) {
                Stroker stroker(shape->strokeWidth, shape->miterLimit, shape->strokeLineJoin, shape->strokeLineCap, tolerance);
                float pattern[2 * sizeof(shape->strokeDashArray) / sizeof(float)], length = 0.f, dashes = 0.f;
                int count = dashPattern(shape, pattern);
                if (count) {    // Undashed when the dashes would be too many
                    for (int i = 0; i < count; i++)
                        length += pattern[i];
                    for (Subpath& subpath: subpaths)
                        dashes += subpathLength(subpath) / length * float(count);
                }
                for (Subpath& subpath: subpaths)
                    if (count && dashes <= kMaxDashes)
                        dash(subpath, pattern, count, shape->strokeDashOffset, stroker);
                    else
                        stroker.addPolyline(subpath.points.data(), subpath.points.size(), subpath.closed, Point{ 1.f, 0.f });
                addStroke(stroker, paint, stops, *mesh);
            }
        }
        return finish(mesh);
    }

    // Imports draws of contours' paths, as createMesh imports an SVG's shapes, in paint order: each a fill with its rule,
    // which closes open contours, or a stroke, its round joins & caps within tolerance, in the paths' units, of their arcs. A glow
    // that shows puts its halos before all of them, & each draw's core right after it, so that a later draw still paints over it
    static RaMesh *createMeshFromPaths(const RaContours& contours, const RaPathDraw *draws, uint64_t count, RaBounds viewBox, float tolerance, const RaGlow *glow) {
        RaMesh *mesh = new RaMesh();
        mesh->svgBounds = viewBox;
        RasterizerPaths::Index index(contours);
        std::vector<Subpath> subpaths;
        const std::vector<RaMeshStop> stops;
        // Dart's PathMetric leaves corners that met a float step or two apart, & on edges so nearly collinear libtess2's sweep can
        // contradict itself: it gives up, spins or runs away, mostly on arm64, whose fused multiply-add keeps rounding errors that
        // would have been 0. So points go on a grid of at most 1/32 of tolerance, a power of 2 so that they land on it exactly
        const float grid = ldexpf(1.f, ilogbf(tolerance / 32.f));
        const bool glows = glow != nullptr && glow->radius > 0.f && isfinite(glow->radius) && glow->strength > 0.f;
        const std::vector<Drawn> drawn = glows ? addGlow(*glow, index, contours, draws, count, grid, *mesh) : std::vector<Drawn>();
        Ribbon core(*mesh, 1.f);
        for (uint64_t i = 0; i < count; i++) {
            const RaPathDraw& draw = draws[i];
            RaMeshPath paint = RaMeshPath();
            if (draw.path >= contours.pathCount || !setColor(draw.color, 1.f, paint) || !readContours(index, draw.path, grid, subpaths))
                continue;
            if (draw.strokeWidth > 0.f || draw.hairline) {
                Stroker stroker(draw.hairline ? 0.f : draw.strokeWidth, draw.miterLimit, char(draw.join), char(draw.cap), tolerance);
                for (Subpath& subpath: subpaths)
                    stroker.addPolyline(subpath.points.data(), subpath.points.size(), subpath.closed, Point{ 1.f, 0.f });
                addStroke(stroker, paint, stops, *mesh);
            } else
                addFill(subpaths, draw.evenOdd, paint, stops, *mesh);
            if (glows)
                addCore(draw, drawn[draw.path].stroked, glow->inWidths, subpaths, paint, stops, core, *mesh);
        }
        return finish(mesh);
    }
    // Writes path's contours to subpaths, their points on the grid. False if one of their points isn't finite
    static bool readContours(const RasterizerPaths::Index& index, uint64_t path, float grid, std::vector<Subpath>& subpaths) {
        subpaths.clear();
        return index.forEachContour(path, [&](const float *p, uint32_t n, bool closed) {
            subpaths.emplace_back();
            for (uint32_t k = 0; k < n; k++)
                addPoint(subpaths.back(), roundf(p[2 * k] / grid) * grid, roundf(p[2 * k + 1] / grid) * grid);
            subpaths.back().closed = closed;
            endSubpath(subpaths);
        });
    }
    // Makes mesh's vertices hold a glow, & appends a halo for each path that a draw paints, as a path of the mesh, before the
    // draws' own. Each is in the color of the path's last draw that paints, unless glow has its own. A path that any draw strokes
    // has its halo on both sides of its polylines, reaching a glow of 1 at the widest stroke's edge, & the widest stroke measures
    // a radius in line widths. Returns what's drawn of each path
    static std::vector<Drawn> addGlow(const RaGlow& glow, const RasterizerPaths::Index& index, const RaContours& contours, const RaPathDraw *draws, uint64_t count, float grid, RaMesh& mesh) {
        mesh.vertexFloats = 6;
        std::vector<Drawn> drawn(contours.pathCount);
        RaMeshPath paint = RaMeshPath();
        paint.halo = 1;
        for (uint64_t i = 0; i < count; i++) {
            const RaPathDraw& draw = draws[i];
            if (draw.path >= contours.pathCount || !setColor(draw.color, 1.f, paint))
                continue;
            Drawn& d = drawn[draw.path];
            d.painted = true, d.color = draw.color;
            if (draw.strokeWidth > 0.f || draw.hairline)
                d.stroked = true, d.width = fmaxf(d.width, draw.hairline ? 0.f : draw.strokeWidth);
        }
        std::vector<Subpath> subpaths;
        const std::vector<RaMeshStop> stops;
        Ribbon ribbon(mesh);
        for (uint64_t i = 0; i < contours.pathCount; i++) {
            const Drawn& d = drawn[i];
            if (!d.painted || !setColor(glow.hasColor ? glow.color : d.color, fminf(1.f, glow.strength), paint) || !readContours(index, i, grid, subpaths))
                continue;
            paint.indexBegin = uint32_t(mesh.indices32.size());
            ribbon.path = float(mesh.paths.size());
            float radius = glow.inWidths ? glow.radius * d.width : glow.radius, halfWidth = 0.5f * d.width;
            for (const Subpath& subpath: subpaths)
                if (d.stroked)
                    ribbon.addStroke(subpath, radius, radius > halfWidth ? radius / (radius - halfWidth) : 1.f);
                else
                    ribbon.addFill(subpath, glow.radius, glow.inWidths);
            if (mesh.indices32.size() > paint.indexBegin)
                endPath(paint, stops, mesh, true);
        }
        return drawn;
    }
    // Appends draw's core, which goes over it, to mesh as a path with paint & stops: along a stroke's polylines, as wide as it is,
    // or if inWidths, as then a fill is a line, inward of each of a fill's contours that's neither inside another nor around one,
    // as that may be a hole, which a core would paint. A hairline has no width for one, nor has a fill of a path that's stroked,
    // as its halo follows the polylines
    static void addCore(const RaPathDraw& draw, bool pathStroked, bool inWidths, const std::vector<Subpath>& subpaths, RaMeshPath paint, const std::vector<RaMeshStop>& stops, Ribbon& core, RaMesh& mesh) {
        const bool stroke = draw.strokeWidth > 0.f;
        if (draw.hairline || (!stroke && (pathStroked || !inWidths)))
            return;
        paint.indexBegin = uint32_t(mesh.indices32.size());
        core.path = float(mesh.paths.size());
        const std::vector<bool> nested = stroke ? std::vector<bool>() : nestedContours(subpaths);
        for (size_t i = 0; i < subpaths.size(); i++)
            if (stroke)
                core.addStroke(subpaths[i], 0.5f * draw.strokeWidth, Ribbon::kCoreGlow);
            else if (!nested[i])
                core.addCore(subpaths[i]);
        if (mesh.indices32.size() > paint.indexBegin)
            endPath(paint, stops, mesh, true);
    }
    // Which of contours are inside another of them, all of their points by the even-odd rule, or have another inside. Their
    // bounds rule most pairs out
    static std::vector<bool> nestedContours(const std::vector<Subpath>& contours) {
        std::vector<bool> nested(contours.size(), false);
        std::vector<Ra::Bounds> bounds(contours.size());
        for (size_t i = 0; i < contours.size(); i++)
            for (const Point& p: contours[i].points)
                bounds[i].extend(p.x, p.y);
        for (size_t i = 0; i < contours.size(); i++)
            for (size_t j = 0; j < contours.size(); j++) {
                const Ra::Bounds& a = bounds[i], &b = bounds[j];
                if (i != j && a.lx >= b.lx && a.ly >= b.ly && a.ux <= b.ux && a.uy <= b.uy && allInside(contours[i].points, contours[j].points))
                    nested[i] = nested[j] = true;
            }
        return nested;
    }
    static bool allInside(const std::vector<Point>& points, const std::vector<Point>& contour) {
        for (const Point& p: points) {
            bool inside = false;
            for (size_t i = 0, j = contour.size() - 1; i < contour.size(); j = i++)
                if ((contour[i].y > p.y) != (contour[j].y > p.y) && p.x < contour[j].x + (contour[i].x - contour[j].x) * (p.y - contour[j].y) / (contour[i].y - contour[j].y))
                    inside = !inside;
            if (!inside)
                return false;
        }
        return true;
    }
    // Appends subpaths' fill, with the even-odd rule or the non-zero one, to mesh as a path with paint & stops
    static void addFill(const std::vector<Subpath>& subpaths, bool evenOdd, RaMeshPath paint, const std::vector<RaMeshStop>& stops, RaMesh& mesh) {
        size_t points = 0;
        for (const Subpath& subpath: subpaths)
            points += subpath.points.size();
        TessMemory memory(points);
        TESStesselator *tess = tessNewTess(&memory.alloc);
        for (const Subpath& subpath: subpaths)
            if (subpath.points.size() > 2)
                tessAddContour(tess, 2, subpath.points.data(), sizeof(Point), int(subpath.points.size()));
        int windingRule = evenOdd ? TESS_WINDING_ODD : TESS_WINDING_NONZERO;
        addPath(tess, windingRule, paint, stops, mesh);
        reportExceeded(memory, windingRule, subpaths);
    }
    // Moves mesh's indices to u16 if they all fit
    static RaMesh *finish(RaMesh *mesh) {
        if (mesh->vertices.size() / mesh->vertexFloats <= 0xFFFF) {
            mesh->indices16.assign(mesh->indices32.begin(), mesh->indices32.end());
            mesh->indices32 = std::vector<uint32_t>();
            mesh->stripIndices16.assign(mesh->stripIndices32.begin(), mesh->stripIndices32.end());
            mesh->stripIndices32 = std::vector<uint32_t>();
        }
        return mesh;
    }

    // A paint as a path's: a premultiplied color, or a gradient's inverse transform & stops. False if it paints nothing
    static bool paintFromPaint(const NSVGpaint& paint, float opacity, RaMeshPath& path, std::vector<RaMeshStop>& stops) {
        path = RaMeshPath();
        stops.clear();
        if (paint.type == NSVG_PAINT_COLOR)
            return setColor(paint.color, opacity, path);
        const NSVGgradient *gradient = paint.gradient;
        if (gradient == nullptr || gradient->nstops == 0)
            return false;
        // NanoSVG's xform maps the gradient's space into the SVG's: its inverse is what a fragment shader needs
        const float *t = gradient->xform;
        float det = t[0] * t[3] - t[1] * t[2];
        if (gradient->nstops == 1 || !(fabsf(det) > 1e-12f) || !isfinite(det))     // As SVG says, the last stop's color
            return setColor(gradient->stops[gradient->nstops - 1].color, opacity, path);
        float a = t[3] / det, b = -t[1] / det, c = -t[2] / det, d = t[0] / det;
        path.type = paint.type == NSVG_PAINT_RADIAL_GRADIENT ? RA_PAINT_RADIAL : RA_PAINT_LINEAR;
        path.gradient = RaTransform{ a, b, c, d, -(a * t[4] + c * t[5]), -(b * t[4] + d * t[5]) };
        float offset = 0.f, maxAlpha = 0.f;
        for (int i = 0; i < gradient->nstops; i++) {
            unsigned int color = gradient->stops[i].color;
            offset = fmaxf(offset, fminf(1.f, gradient->stops[i].offset));     // As SVG says, never below the previous one's
            RaMeshStop stop = { offset, (color & 0xFF) / 255.f, (color >> 8 & 0xFF) / 255.f, (color >> 16 & 0xFF) / 255.f, (color >> 24) / 255.f * opacity };
            maxAlpha = fmaxf(maxAlpha, stop.a);
            stops.push_back(stop);
        }
        path.stopCount = uint32_t(stops.size());
        return maxAlpha > 0.f;
    }
    static bool setColor(unsigned int color, float opacity, RaMeshPath& path) {
        float a = (color >> 24) / 255.f * opacity;
        path.type = RA_PAINT_COLOR;
        path.r = (color & 0xFF) / 255.f * a, path.g = (color >> 8 & 0xFF) / 255.f * a, path.b = (color >> 16 & 0xFF) / 255.f * a, path.a = a;
        return a > 0.f;
    }

    // As Mesh.isOpaque in Dart: its color's alpha is 1, or each of its gradient's stops' is
    static bool isOpaque(const RaMeshPath& paint, const std::vector<RaMeshStop>& stops) {
        if (paint.type == RA_PAINT_COLOR)
            return paint.a == 1.f;
        for (const RaMeshStop& stop: stops)
            if (stop.a != 1.f)
                return false;
        return !stops.empty();
    }
    // Appends a stroke's strip to mesh as a path with paint & stops, unless it overlaps itself by more than float rounding: then
    // its non-zero union, as an opacity applied when drawing would show its overlaps. The union's crossings have no offsets, so
    // an opaque paint keeps the strip too, for instances drawn without one. A hairline's strip has no area to test, & stays
    static void addStroke(const Stroker& stroker, RaMeshPath paint, const std::vector<RaMeshStop>& stops, RaMesh& mesh) {
        static const TESSreal normal[3] = { 0.f, 0.f, 1.f };
        const std::vector<StrokeVertex>& strip = stroker.strip;
        if (strip.empty())
            return;
        addOffsets(mesh);
        paint.halfWidth = stroker.halfWidth();
        if (stroker.hairline)
            return addTriangles(strip, paint, stops, mesh);
        float extent = 0.f;
        for (const StrokeVertex& v: strip)
            extent = fmaxf(extent, fmaxf(fabsf(v.p.x), fabsf(v.p.y)));
        TessMemory memory(strip.size());
        TESStesselator *tess = tessNewTess(&memory.alloc);
        for (size_t i = 0; i < strip.size(); i += 3)
            tessAddContour(tess, 2, &strip[i], sizeof(StrokeVertex), 3);
        // The strip's triangles are counter-clockwise, so where they overlap, the winding is 2 or more. An overlap counts once
        // its region's width, 2 · area / perimeter, passes 16 ulps of the coordinates, float rounding's
        bool overlaps = false;
        if (tessTesselate(tess, TESS_WINDING_ABS_GEQ_TWO, TESS_BOUNDARY_CONTOURS, 0, 2, normal)) {
            const TESSreal *v = tessGetVertices(tess);
            const TESSindex *e = tessGetElements(tess);
            for (int i = 0, n = tessGetElementCount(tess); i < n && !overlaps; i++) {
                int base = e[2 * i], count = e[2 * i + 1];
                double area2 = 0.0, perimeter = 0.0;
                for (int k = 0; k < count; k++) {
                    const TESSreal *a = v + 2 * (base + k), *b = v + 2 * (base + (k + 1) % count);
                    area2 += double(a[0]) * b[1] - double(b[0]) * a[1];
                    perimeter += hypot(double(b[0]) - a[0], double(b[1]) - a[1]);
                }
                overlaps = fabs(area2) > 16.0 * double(extent) * FLT_EPSILON * perimeter;
            }
        }
        tessDeleteTess(tess);
        reportExceeded(memory, TESS_WINDING_ABS_GEQ_TWO, strip);
        if (!overlaps)
            return addTriangles(strip, paint, stops, mesh);
        // The union's boundary, then its triangles: tessellated at once, the triangles' crossings would stay as vertices
        tess = tessNewTess(&memory.alloc);
        for (size_t i = 0; i < strip.size(); i += 3)
            tessAddContour(tess, 2, &strip[i], sizeof(StrokeVertex), 3);
        TESStesselator *outline = tessNewTess(&memory.alloc);
        if (tessTesselate(tess, TESS_WINDING_NONZERO, TESS_BOUNDARY_CONTOURS, 0, 2, normal)) {
            const TESSreal *v = tessGetVertices(tess);
            const TESSindex *e = tessGetElements(tess);
            for (int i = 0, n = tessGetElementCount(tess); i < n; i++)
                tessAddContour(outline, 2, v + 2 * e[2 * i], 2 * sizeof(TESSreal), e[2 * i + 1]);
        }
        tessDeleteTess(tess);
        bool opaque = isOpaque(paint, stops);
        if (opaque && !mesh.hasStrips)
            mesh.hasStrips = true, mesh.stripIndices32 = mesh.indices32;
        size_t path = mesh.paths.size();
        addPath(outline, TESS_WINDING_NONZERO, paint, stops, mesh, !opaque);
        if (opaque && mesh.paths.size() > path)
            weld(strip, float(path), mesh, mesh.stripIndices32);
        reportExceeded(memory, TESS_WINDING_NONZERO, strip);
    }
    // Makes room for the offsets of mesh's vertices, 0 for those so far, as a mesh without strokes has none
    static void addOffsets(RaMesh& mesh) {
        if (mesh.vertexFloats >= 5)
            return;
        size_t count = mesh.vertices.size() / 3;
        mesh.vertices.resize(5 * count);
        for (size_t i = count; i-- > 0;) {
            float x = mesh.vertices[3 * i], y = mesh.vertices[3 * i + 1], path = mesh.vertices[3 * i + 2];
            mesh.vertices[5 * i] = x, mesh.vertices[5 * i + 1] = y, mesh.vertices[5 * i + 2] = path;
            mesh.vertices[5 * i + 3] = 0.f, mesh.vertices[5 * i + 4] = 0.f;
        }
        mesh.vertexFloats = 5;
    }
    static inline void addVertex(RaMesh& mesh, Point p, float path, Point u, float glow = 1.f) {
        mesh.vertices.insert(mesh.vertices.end(), { p.x, p.y, path });
        if (mesh.vertexFloats >= 5)
            mesh.vertices.insert(mesh.vertices.end(), { u.x, u.y });
        if (mesh.vertexFloats == 6)
            mesh.vertices.push_back(glow);
        mesh.bounds.extend(p.x, p.y);
    }
    // Appends triangles, 3 vertices each, to mesh with path's index, each distinct vertex once, & their indices to indices
    static void weld(const std::vector<StrokeVertex>& triangles, float path, RaMesh& mesh, std::vector<uint32_t>& indices) {
        std::unordered_map<VertexKey, uint32_t, VertexKeyHash> welded;
        for (const StrokeVertex& v: triangles) {
            VertexKey key;
            memcpy(&key.p, &v.p, sizeof(key.p)), memcpy(&key.u, &v.u, sizeof(key.u));
            auto found = welded.emplace(key, uint32_t(mesh.vertices.size() / mesh.vertexFloats));
            if (found.second)
                addVertex(mesh, v.p, path, v.u);
            indices.push_back(found.first->second);
        }
    }
    // Appends triangles, 3 vertices each, to mesh as a path with paint & stops
    static void addTriangles(const std::vector<StrokeVertex>& triangles, RaMeshPath paint, const std::vector<RaMeshStop>& stops, RaMesh& mesh) {
        if (triangles.empty())
            return;
        paint.indexBegin = uint32_t(mesh.indices32.size());
        weld(triangles, float(mesh.paths.size()), mesh, mesh.indices32);
        endPath(paint, stops, mesh, true);
    }
    // Ends mesh's path with paint & stops, whose indices were appended from paint.indexBegin, in the strips' list too if shared
    static void endPath(RaMeshPath paint, const std::vector<RaMeshStop>& stops, RaMesh& mesh, bool shared) {
        paint.indexCount = uint32_t(mesh.indices32.size()) - paint.indexBegin;
        paint.stopBegin = uint32_t(mesh.stops.size());
        mesh.stops.insert(mesh.stops.end(), stops.begin(), stops.end());
        mesh.paths.push_back(paint);
        if (shared && mesh.hasStrips)
            mesh.stripIndices32.insert(mesh.stripIndices32.end(), mesh.indices32.begin() + paint.indexBegin, mesh.indices32.end());
    }
    // Appends tess's contours, tessellated with windingRule, to mesh as a path with paint & stops, & deletes tess. Its vertices
    // have no offsets. Its indices are in the strips' list too if shared
    static void addPath(TESStesselator *tess, int windingRule, RaMeshPath paint, const std::vector<RaMeshStop>& stops, RaMesh& mesh, bool shared = true) {
        static const TESSreal normal[3] = { 0.f, 0.f, 1.f };
        if (tessTesselate(tess, windingRule, TESS_POLYGONS, 3, 2, normal) && tessGetElementCount(tess) > 0) {
            uint32_t base = uint32_t(mesh.vertices.size() / mesh.vertexFloats), count = uint32_t(tessGetVertexCount(tess));
            float index = float(mesh.paths.size());
            const TESSreal *vertices = tessGetVertices(tess);
            for (uint32_t i = 0; i < count; i++)
                addVertex(mesh, Point{ float(vertices[i * 2]), float(vertices[i * 2 + 1]) }, index, Point{ 0.f, 0.f });
            paint.indexBegin = uint32_t(mesh.indices32.size());
            const TESSindex *elements = tessGetElements(tess);
            for (int i = 0, n = tessGetElementCount(tess); i < n; i++, elements += 3)
                if (elements[0] != TESS_UNDEF && elements[1] != TESS_UNDEF && elements[2] != TESS_UNDEF)
                    mesh.indices32.insert(mesh.indices32.end(), { base + uint32_t(elements[0]), base + uint32_t(elements[1]), base + uint32_t(elements[2]) });
            endPath(paint, stops, mesh, shared);
        }
        tessDeleteTess(tess);
    }

    // Flattens geometry's subpaths, with Wang's formula for each curve's segment count, so each is within tolerance
    static void flatten(Ra::Geometry& geometry, float tolerance, std::vector<Subpath>& subpaths) {
        subpaths.clear();
        const uint8_t *types = geometry.types.base;
        for (size_t i = 0; i < geometry.types.end; i += Ra::Geometry::TypeSizes[types[i]]) {
            const float *p = geometry.points.base + 2 * i;
            if (types[i] == Ra::Geometry::kMove || subpaths.empty() || subpaths.back().closed) {
                // After a close, a subpath starts where the closed one did
                Point start = types[i] == Ra::Geometry::kMove || subpaths.empty() ? Point{ p[0], p[1] } : subpaths.back().points[0];
                endSubpath(subpaths);
                subpaths.emplace_back();
                subpaths.back().points.push_back(start);
                if (types[i] == Ra::Geometry::kMove)
                    continue;
            }
            Subpath& subpath = subpaths.back();
            Point p0 = subpath.points.back();
            switch (types[i]) {
                case Ra::Geometry::kLine:
                    addPoint(subpath, p[0], p[1]);
                    break;
                case Ra::Geometry::kQuadratic: {
                    float ax = p0.x - 2.f * p[0] + p[2], ay = p0.y - 2.f * p[1] + p[3];
                    int n = segmentCount(0.25f * sqrtf(ax * ax + ay * ay), tolerance);
                    for (int k = 1; k <= n; k++) {
                        float t = float(k) / float(n), u = 1.f - t;
                        addPoint(subpath, u * u * p0.x + 2.f * u * t * p[0] + t * t * p[2], u * u * p0.y + 2.f * u * t * p[1] + t * t * p[3]);
                    }
                    break;
                }
                case Ra::Geometry::kCubic: {
                    float ax = p0.x - 2.f * p[0] + p[2], ay = p0.y - 2.f * p[1] + p[3], bx = p[0] - 2.f * p[2] + p[4], by = p[1] - 2.f * p[3] + p[5];
                    int n = segmentCount(0.75f * sqrtf(fmaxf(ax * ax + ay * ay, bx * bx + by * by)), tolerance);
                    for (int k = 1; k <= n; k++) {
                        float t = float(k) / float(n), u = 1.f - t;
                        addPoint(subpath, u * u * u * p0.x + 3.f * u * t * (u * p[0] + t * p[2]) + t * t * t * p[4],
                                 u * u * u * p0.y + 3.f * u * t * (u * p[1] + t * p[3]) + t * t * t * p[5]);
                    }
                    break;
                }
                case Ra::Geometry::kClose:
                    subpath.closed = true;
                    break;
            }
        }
        endSubpath(subpaths);
    }
    static inline int segmentCount(float deviation, float tolerance) {
        return std::max(1, std::min(kMaxCurveSegments, int(ceilf(sqrtf(deviation / tolerance)))));
    }
    static inline void addPoint(Subpath& subpath, float x, float y) {
        if (subpath.points.empty() || subpath.points.back().x != x || subpath.points.back().y != y)
            subpath.points.push_back(Point{ x, y });
    }
    static void endSubpath(std::vector<Subpath>& subpaths) {
        if (subpaths.empty())
            return;
        Subpath& subpath = subpaths.back();
        std::vector<Point>& points = subpath.points;
        if (subpath.closed && points.size() > 1 && points.back().x == points[0].x && points.back().y == points[0].y)
            points.pop_back();
        if (points.empty())
            subpaths.pop_back();
    }
    static float subpathLength(const Subpath& subpath) {
        float length = 0.f;
        size_t n = subpath.points.size();
        for (size_t i = 0; i + 1 < n + subpath.closed; i++)
            length += distance(subpath.points[i], subpath.points[(i + 1) % n]);
        return length;
    }

    // The shape's dash pattern, repeated once if its count is odd, as SVG says, or 0 if it has none
    static int dashPattern(const NSVGshape *shape, float *pattern) {
        int count = shape->strokeDashCount;
        float length = 0.f;
        for (int i = 0; i < count; i++)
            length += (pattern[i] = pattern[i + count] = fmaxf(0.f, shape->strokeDashArray[i]));
        return length > 0.f && isfinite(length) ? count * (count % 2 + 1) : 0;
    }
    // Strokes subpath's dashes, from offset into the pattern. A closed subpath's first & last dashes are one when they meet at its
    // start, & a dash of no length is a dot, drawn with its caps
    static void dash(const Subpath& subpath, const float *pattern, int count, float offset, Stroker& stroker) {
        struct Dash {
            std::vector<Point> points;  Point direction;
        };
        if (subpath.points.size() < 2)
            return;
        std::vector<Dash> dashes;
        float length = 0.f, phase;
        for (int i = 0; i < count; i++)
            length += pattern[i];
        phase = fmodf(offset, length), phase += phase < 0.f ? length : 0.f;
        int index = 0;
        float left = pattern[0];
        while (phase > 0.f) {
            if (phase >= left)
                phase -= left, index = (index + 1) % count, left = pattern[index];
            else
                left -= phase, phase = 0.f;
        }
        bool on = index % 2 == 0, startsOn = on;
        const std::vector<Point>& points = subpath.points;
        size_t n = points.size(), segments = subpath.closed ? n : n - 1;
        Dash dash;
        if (on)
            dash.points.push_back(points[0]);
        for (size_t i = 0; i < segments; i++) {
            Point a = points[i], b = points[(i + 1) % n];
            float l = distance(a, b), t = 0.f;
            dash.direction = Point{ (b.x - a.x) / l, (b.y - a.y) / l };
            while (left <= l - t) {
                t += left;
                Point q = t < l ? Point{ a.x + dash.direction.x * t, a.y + dash.direction.y * t } : b;
                if (on)
                    dash.points.push_back(q), dashes.push_back(dash), dash.points.clear();
                else
                    dash.points.assign(1, q);
                on = !on, index = (index + 1) % count, left = pattern[index];
            }
            left -= l - t;
            if (on)
                dash.points.push_back(b);
        }
        if (on && dash.points.size() > 1) {
            if (subpath.closed && startsOn && !dashes.empty())     // The first dash goes on from the last
                dash.points.insert(dash.points.end(), dashes[0].points.begin() + 1, dashes[0].points.end()), dashes[0] = dash;
            else
                dashes.push_back(dash);
        }
        for (Dash& d: dashes) {
            std::vector<Point>& p = d.points;
            p.erase(std::unique(p.begin(), p.end(), [](Point u, Point v) { return u.x == v.x && u.y == v.y; }), p.end());
            stroker.addPolyline(p.data(), p.size(), false, d.direction);
        }
    }
    static inline float distance(Point a, Point b) {
        return sqrtf((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    }

    // Outlines polylines as a strip of triangles, counter-clockwise: a quad per segment, its sides' ends moved to the joins'
    // miters, the inner one's while within half of each segment, which round joins take while within tolerance of their
    // arc, else a fan from the inner miter, or the point, over the outer side's arc or bevel, & caps at open ends. Each vertex
    // records its offset from the polyline point it's built around. A hairline, of width 0, is outlined at a half width of 1 for
    // those offsets, & its vertices are the points themselves: as the width it's drawn at isn't known, its inner corners don't
    // move, & its arcs have as few segments as they can
    struct Stroker {
        // A stroke's width, 0 for a hairline, miter limit, & NanoSVG's join & cap
        Stroker(float width, float miterLimit, char join, char cap, float tolerance) : hairline(width == 0.f),
            hw(hairline ? 1.f : 0.5f * width), miterLimit(miterLimit), tolerance(hairline ? 1.f : tolerance), join(join), cap(cap) {}
        float halfWidth() const { return hairline ? 0.f : hw; }
        struct Ends {
            Point l0, l1, r0, r1;   // A segment's left & right sides' start & end
        };
        // A polyline of n distinct consecutive points. An open one of one point is a dot, drawn with its caps along direction
        void addPolyline(const Point *p, size_t n, bool closed, Point direction) {
            if (n == 0 || (closed && n < 2))
                return;
            if (n == 1) {
                center = p[0];
                if (cap == NSVG_CAP_ROUND)
                    arc.clear(), addArc(p[0], atan2f(direction.y, direction.x), 2.f * float(M_PI)), arc.back() = arc.front(), addFan(p[0]);
                else if (cap == NSVG_CAP_SQUARE) {
                    Point d = { direction.x * hw, direction.y * hw }, o = { -d.y, d.x };
                    addQuad({ p[0].x - d.x + o.x, p[0].y - d.y + o.y }, { p[0].x + d.x + o.x, p[0].y + d.y + o.y },
                            { p[0].x + d.x - o.x, p[0].y + d.y - o.y }, { p[0].x - d.x - o.x, p[0].y - d.y - o.y });
                }
                return;
            }
            size_t segments = closed ? n : n - 1;
            ends.resize(segments);
            for (size_t i = 0; i < segments; i++) {
                Point a = p[i], b = p[(i + 1) % n], d = unit(a, b), o = { -d.y * hw, d.x * hw };
                ends[i] = { { a.x + o.x, a.y + o.y }, { b.x + o.x, b.y + o.y }, { a.x - o.x, a.y - o.y }, { b.x - o.x, b.y - o.y } };
            }
            for (size_t i = closed ? 0 : 1; i < (closed ? n : n - 1); i++)
                addJoin(p[(i + n - 1) % n], p[i], p[(i + 1) % n], ends[(i + segments - 1) % segments], ends[i % segments]);
            for (size_t i = 0; i < segments; i++) {
                const Ends& e = ends[i];
                Point a = p[i], b = p[(i + 1) % n];
                addTriangle(e.l0, e.l1, e.r1, a, b, b), addTriangle(e.l0, e.r1, e.r0, a, b, a);
            }
            if (!closed)
                addCap(p[0], unit(p[1], p[0])), addCap(p[n - 1], unit(p[n - 2], p[n - 1]));
        }
        // The join at b of the segments from a & to c, with ends e0 & e1
        void addJoin(Point a, Point b, Point c, Ends& e0, Ends& e1) {
            center = b;
            Point d0 = unit(a, b), d1 = unit(b, c);
            float cross = d0.x * d1.y - d0.y * d1.x, dot = d0.x * d1.x + d0.y * d1.y;
            Point o0 = { -d0.y * hw, d0.x * hw }, o1 = { -d1.y * hw, d1.x * hw }, m = { o0.x + o1.x, o0.y + o1.y };
            float ml = sqrtf(m.x * m.x + m.y * m.y);
            if ((fabsf(cross) < 1e-6f && dot < 0.f) || !(ml > 1e-6f * hw)) {
                // A turn back has no miter, & its quads overlap. A round join is the half disc ahead
                if (join == NSVG_JOIN_ROUND)
                    arc.clear(), addArc(b, atan2f(o0.y, o0.x), -float(M_PI)), arc.front() = e0.l1, arc.back() = e0.r1, addFan(b);
                return;
            }
            // SVG's miter ratio 1 / sin(θ / 2), for an angle θ between the segments, is 1 / cos(φ / 2) for their turn φ
            float ratio = 1.f / sqrtf(fmaxf(1e-12f, 0.5f * (1.f + dot))), k = hw * ratio / ml;
            Point mk = { m.x * k, m.y * k };
            bool left = cross > 0.f;    // A turn towards the left side, the inner one
            // The inner miter is hw · tan(φ / 2) along each segment from b: past half of either, the quads keep their inner
            // corners & overlap, as a turn back's, rather than turn inside out, into a spike at a sharp turn
            bool overlap = hairline || hw * sqrtf(fmaxf(0.f, ratio * ratio - 1.f)) > 0.5f * fminf(distance(a, b), distance(b, c));
            Point inner = overlap ? b : left ? Point{ b.x + mk.x, b.y + mk.y } : Point{ b.x - mk.x, b.y - mk.y };
            Point outer = left ? Point{ b.x - mk.x, b.y - mk.y } : Point{ b.x + mk.x, b.y + mk.y };
            if (!overlap)
                (left ? e0.l1 : e0.r1) = inner, (left ? e1.l0 : e1.r0) = inner;
            Point &out0 = left ? e0.r1 : e0.l1, &out1 = left ? e1.r0 : e1.l0;
            if ((join == NSVG_JOIN_MITER && ratio <= miterLimit) || (join == NSVG_JOIN_ROUND && hw * (ratio - 1.f) <= tolerance)) {
                out0 = out1 = outer;
                return;
            }
            if (join == NSVG_JOIN_ROUND) {
                Point v0 = { out0.x - b.x, out0.y - b.y }, v1 = { out1.x - b.x, out1.y - b.y };
                arc.clear(), addArc(b, atan2f(v0.y, v0.x), atan2f(v0.x * v1.y - v0.y * v1.x, v0.x * v1.x + v0.y * v1.y));
                arc.front() = out0, arc.back() = out1, addFan(inner);
            } else
                addTriangle(inner, out0, out1);
        }
        // A cap at p, facing direction d, its corners the segment's
        void addCap(Point p, Point d) {
            center = p;
            Point o = { -d.y * hw, d.x * hw };
            if (cap == NSVG_CAP_ROUND)
                arc.clear(), addArc(p, atan2f(o.y, o.x), -float(M_PI)), arc.front() = { p.x + o.x, p.y + o.y },
                    arc.back() = { p.x - o.x, p.y - o.y }, addFan(p);
            else if (cap == NSVG_CAP_SQUARE)
                addQuad({ p.x + o.x, p.y + o.y }, { p.x + o.x + d.x * hw, p.y + o.y + d.y * hw },
                        { p.x - o.x + d.x * hw, p.y - o.y + d.y * hw }, { p.x - o.x, p.y - o.y });
        }
        // Appends to arc an arc of radius hw around o, from angle a0 through sweep, within tolerance, & at least a segment
        // per quarter turn
        void addArc(Point o, float a0, float sweep) {
            float step = 2.f * acosf(fmaxf(-1.f, 1.f - tolerance / hw));
            int n = std::max(int(ceilf(fabsf(sweep) / (0.5f * float(M_PI)) - 1e-3f)),
                             std::min(kMaxCurveSegments, int(ceilf(fabsf(sweep) / fmaxf(1e-3f, step)))));
            for (int k = 0; k <= n; k++) {
                float a = a0 + sweep * float(k) / float(n);
                arc.push_back(Point{ o.x + hw * cosf(a), o.y + hw * sinf(a) });
            }
        }
        void addFan(Point o) {
            for (size_t k = 0; k + 1 < arc.size(); k++)
                addTriangle(o, arc[k], arc[k + 1]);
        }
        void addQuad(Point a, Point b, Point c, Point d) {
            addTriangle(a, b, c), addTriangle(a, c, d);
        }
        // A triangle built around center
        void addTriangle(Point a, Point b, Point c) {
            addTriangle(a, b, c, center, center, center);
        }
        // Appends a triangle counter-clockwise, its points built around ca, cb & cc, unless it has no area
        void addTriangle(Point a, Point b, Point c, Point ca, Point cb, Point cc) {
            float area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
            if (area == 0.f || !isfinite(area))
                return;
            if (area < 0.f)
                std::swap(b, c), std::swap(cb, cc);
            strip.insert(strip.end(), { vertex(a, ca), vertex(b, cb), vertex(c, cc) });
        }
        inline StrokeVertex vertex(Point p, Point c) const {
            return StrokeVertex{ hairline ? c : p, Point{ (p.x - c.x) / hw, (p.y - c.y) / hw } };
        }
        static inline Point unit(Point a, Point b) {
            float l = distance(a, b);
            return Point{ (b.x - a.x) / l, (b.y - a.y) / l };
        }

        bool hairline;  float hw, miterLimit, tolerance;  char join, cap;
        Point center = { 0.f, 0.f };    // The polyline point the triangles being added are built around
        std::vector<StrokeVertex> strip;    // The triangles, 3 vertices each
        std::vector<Point> arc;     // An arc's points
        std::vector<Ends> ends;
    };

    // Appends glows' ribbons' triangles to a mesh, indexed as they're built, each vertex once. A halo's glow is 0 on its outer
    // edge & 1 at the path's edge: on a fill's contour, or for a stroke's over 1 on its polyline, so that it's 1 at the stroke's
    // edge. A core's is 1 on its outer edge, the draw's own, & up to kCoreGlow in its middle. So a path's edge has no step in the
    // glow, which ra_mesh_glow.frag turns into one profile. Offsets are 0, so that a stroke's least width leaves ribbons alone.
    // Every case but a fill's core is a closed walk along points with the ribbon on its left: a fill's contour turned so that its
    // outside is, a closed polyline in both directions, & an open one there & back, so that its caps are turns back. Where the
    // walk turns left, its ribbon's on the inner side, & a miter as in the Stroker, while within half of each segment, else the
    // segments' quads overlap. Where it turns right, a round join, or a miter if it's a turn of at most one of the arc's steps
    struct Ribbon {
        static constexpr float kArcStep = float(M_PI) / 6.f, kArcStepCosine = 0.8660254f;
        static constexpr float kCoreGlow = 2.f;
        static constexpr float kLeastTaper = 0.05f;     // How much the ends of a quad can differ, relatively, for 2 triangles
        static constexpr float kLeastMiterCosine = 0.05f;   // Of a fill's core's corners: 1 + cos, so that a spike's stays near

        struct Stop {
            Point p;  float radius;  uint32_t vertex, in, out;   // On the polyline, then the outer edge's ends there, in & out of it
        };
        // A ribbon whose outer edges have a glow of edge
        explicit Ribbon(RaMesh& mesh, float edge = 0.f) : mesh(mesh), edge(edge) {}

        // A polyline's ribbon on both of its sides, with half discs around its ends if it's open, its glow on the polyline centre
        void addStroke(const Subpath& subpath, float radius, float centre) {
            const std::vector<Point>& p = subpath.points;
            size_t n = p.size();
            if (n < 2 || !(radius > 0.f))
                return;
            stops.clear();
            for (size_t i = 0; i < n; i++)
                stops.push_back(Stop{ p[i], radius, addVertex(p[i], centre), 0, 0 });
            if (subpath.closed) {
                addWalk(n);
                std::reverse(stops.begin(), stops.end());
                addWalk(0);
            } else {
                for (size_t i = n - 1; i-- > 1;)
                    stops.push_back(Stop(stops[i]));
                addWalk(n);
            }
        }
        // A contour's ribbon outward, as its signed area tells, closed as a fill closes it. Its radius is at each point inWidths
        // that many times the shorter of the edges there. A contour of no area has no outside
        void addFill(const Subpath& subpath, float radius, bool inWidths) {
            const std::vector<Point>& p = subpath.points;
            double area;
            size_t n = closedPoints(p, area);
            stops.resize(n);
            for (size_t i = 0; i < n; i++) {
                float r = inWidths ? radius * fminf(distance(p[(i + n - 1) % n], p[i]), distance(p[i], p[(i + 1) % n])) : radius;
                stops[area > 0.0 ? n - 1 - i : i] = Stop{ p[i], r, addVertex(p[i], 1.f), 0, 0 };
            }
            if (n > 0)
                addWalk(n);
        }
        // A fill's core inward of a contour, as its signed area tells: a glow of 1 on it, up to kCoreGlow where the contour's sides
        // meet in a thin shape, half of the shorter of the edges at each point in
        void addCore(const Subpath& subpath) {
            const std::vector<Point>& p = subpath.points;
            double area;
            size_t n = closedPoints(p, area);
            float side = area > 0.0 ? 1.f : -1.f;
            uint32_t base = uint32_t(mesh.vertices.size() / mesh.vertexFloats);
            for (size_t i = 0; i < n; i++) {
                Point a = p[(i + n - 1) % n], b = p[(i + 1) % n], d0 = Stroker::unit(a, p[i]), d1 = Stroker::unit(p[i], b);
                Point o0 = { -side * d0.y, side * d0.x }, o1 = { -side * d1.y, side * d1.x };
                float dot = d0.x * d1.x + d0.y * d1.y, k = 0.5f * fminf(distance(a, p[i]), distance(p[i], b)) / fmaxf(1.f + dot, kLeastMiterCosine);
                addVertex(p[i], 1.f), addVertex(Point{ p[i].x + k * (o0.x + o1.x), p[i].y + k * (o0.y + o1.y) }, kCoreGlow);
            }
            for (size_t i = 0; i < n; i++) {
                uint32_t j = uint32_t((i + 1) % n), k = uint32_t(i);
                float ra = distance(pointOf(base + 2 * k), pointOf(base + 2 * k + 1)), rb = distance(pointOf(base + 2 * j), pointOf(base + 2 * j + 1));
                addQuad(base + 2 * k, base + 2 * k + 1, base + 2 * j + 1, base + 2 * j, tapers(ra, rb));
            }
        }
        // How many of a contour's points to walk, without the repeat of its first at its end: 0 if it has under 3 or no area, as
        // then it has no sides. area is twice its signed one
        static size_t closedPoints(const std::vector<Point>& p, double& area) {
            size_t n = p.size();
            while (n > 1 && p[n - 1].x == p[0].x && p[n - 1].y == p[0].y)
                n--;
            area = 0.0;
            for (size_t i = 0; i < n; i++)
                area += double(p[i].x) * p[(i + 1) % n].y - double(p[(i + 1) % n].x) * p[i].y;
            return n < 3 || area == 0.0 ? 0 : n;
        }
        // The ribbon on the left of the closed walk along stops. Only the first rounded stops round a turn back, as a walk that
        // passes it twice would paint its half disc twice
        void addWalk(size_t rounded) {
            size_t n = stops.size();
            for (size_t i = 0; i < n; i++) {
                Stop& s = stops[i];
                Point a = stops[(i + n - 1) % n].p, b = stops[(i + 1) % n].p, d0 = Stroker::unit(a, s.p), d1 = Stroker::unit(s.p, b);
                Point o0 = { -d0.y, d0.x }, o1 = { -d1.y, d1.x };
                float r = s.radius, cross = d0.x * d1.y - d0.y * d1.x, dot = d0.x * d1.x + d0.y * d1.y;
                bool back = fabsf(cross) < 1e-6f && dot < 0.f, inner = !back && cross > 0.f;
                // tan(φ / 2) of the turn φ is cross / (1 + dot), which the inner miter is r times along each segment
                if (!back && (inner ? r * cross <= 0.5f * (1.f + dot) * fminf(distance(a, s.p), distance(s.p, b)) : dot >= kArcStepCosine)) {
                    float k = r / (1.f + dot);
                    s.in = s.out = addVertex(Point{ s.p.x + k * (o0.x + o1.x), s.p.y + k * (o0.y + o1.y) }, edge);
                    continue;
                }
                s.in = addVertex(Point{ s.p.x + r * o0.x, s.p.y + r * o0.y }, edge);
                s.out = addVertex(Point{ s.p.x + r * o1.x, s.p.y + r * o1.y }, edge);
                if (!inner && (!back || i < rounded))
                    addFan(s, atan2f(o0.y, o0.x), back ? -float(M_PI) : atan2f(cross, dot));
            }
            for (size_t i = 0; i < n; i++) {
                const Stop& s = stops[i], &next = stops[(i + 1) % n];
                addQuad(s.vertex, s.out, next.in, next.vertex, tapers(s.radius, next.radius));
            }
        }
        // The fan around s, of its arc from its in vertex, at angle a0, through sweep to its out vertex
        void addFan(const Stop& s, float a0, float sweep) {
            int n = std::max(1, int(ceilf(fabsf(sweep) / kArcStep - 1e-3f)));
            uint32_t last = s.in;
            for (int k = 1; k <= n; k++) {
                float a = a0 + sweep * float(k) / float(n);
                uint32_t next = k < n ? addVertex(Point{ s.p.x + s.radius * cosf(a), s.p.y + s.radius * sinf(a) }, edge) : s.out;
                addTriangle(s.vertex, last, next);
                last = next;
            }
        }
        static bool tapers(float ra, float rb) {
            return fabsf(ra - rb) > kLeastTaper * fmaxf(ra, rb);
        }
        // The quad from a's inner & outer vertices to b's outer & inner ones. One that tapers is a fan around its centre, as a
        // diagonal would make its glow lopsided, differently on a line's two sides
        void addQuad(uint32_t ai, uint32_t ao, uint32_t bo, uint32_t bi, bool tapered) {
            if (!tapered) {
                addTriangle(ai, ao, bo), addTriangle(ai, bo, bi);
                return;
            }
            const Point p = pointOf(ai), q = pointOf(ao), r = pointOf(bo), s = pointOf(bi);
            const float glow = 0.25f * (glowOf(ai) + glowOf(ao) + glowOf(bo) + glowOf(bi));
            uint32_t c = addVertex(Point{ 0.25f * (p.x + q.x + r.x + s.x), 0.25f * (p.y + q.y + r.y + s.y) }, glow);
            addTriangle(c, ai, ao), addTriangle(c, ao, bo), addTriangle(c, bo, bi), addTriangle(c, bi, ai);
        }
        Point pointOf(uint32_t k) const {
            return Point{ mesh.vertices[mesh.vertexFloats * k], mesh.vertices[mesh.vertexFloats * k + 1] };
        }
        float glowOf(uint32_t k) const {
            return mesh.vertices[mesh.vertexFloats * k + mesh.vertexFloats - 1];
        }
        uint32_t addVertex(Point p, float glow) {
            uint32_t index = uint32_t(mesh.vertices.size() / mesh.vertexFloats);
            RasterizerMesh::addVertex(mesh, p, path, Point{ 0.f, 0.f }, glow);
            return index;
        }
        void addTriangle(uint32_t a, uint32_t b, uint32_t c) {
            mesh.indices32.insert(mesh.indices32.end(), { a, b, c });
        }

        RaMesh& mesh;
        float edge;                 // The glow on its outer edges
        float path = 0.f;           // The index of the path being added
        std::vector<Stop> stops;    // The walk
    };
};
