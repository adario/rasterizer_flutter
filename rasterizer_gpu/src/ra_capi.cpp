//
//  The C API over the Rasterizer core, src/core: see its README.md
//

#include <memory>
#include <stddef.h>
#include "ra_capi.h"
#include "ra_frame.hpp"
#include "ra_mesh.hpp"
#include "ra_paths.hpp"
#include "RasterizerSVG.hpp"

struct RaScene { Ra::SceneRef scene; RaBounds svgBounds = { 0.f, 0.f, 0.f, 0.f }; };
struct RaList { Ra::SceneList list;  std::vector<Ra::ColorMatrix> colorMatrices; };
struct RaRenderer { RasterizerRenderer renderer; };
struct RaFrameBuffer { RenderBuffer buffer; };

static_assert(sizeof(RaTransform) == sizeof(Ra::Transform), "RaTransform mirrors Ra::Transform");
static_assert(sizeof(RaBounds) == sizeof(Ra::Bounds), "RaBounds mirrors Ra::Bounds");
static_assert(sizeof(RaParams) == sizeof(Ra::Params) && offsetof(Ra::Params, clearColor) == offsetof(RaParams, clearB), "RaParams mirrors Ra::Params");
static_assert(sizeof(RaEntry) == sizeof(Ra::Buffer::Entry) && sizeof(Ra::Buffer::Type) == sizeof(uint32_t), "RaEntry mirrors Ra::Buffer::Entry");
static_assert(offsetof(RaEntry, begin) == offsetof(Ra::Buffer::Entry, begin) && offsetof(RaEntry, end) == offsetof(Ra::Buffer::Entry, end), "RaEntry mirrors Ra::Buffer::Entry");
static_assert(sizeof(RaListEntry) == 56 && offsetof(RaListEntry, deviceClip) == 32 && offsetof(RaListEntry, opacity) == 48 && offsetof(RaListEntry, colorMatrix) == 52, "RaListEntry's layout, which Dart writes");
static_assert(sizeof(Ra::ColorMatrix) == 16 * sizeof(float), "Ra::ColorMatrix is 16 floats");
static_assert(sizeof(RaMeshPath) == 68 && offsetof(RaMeshPath, r) == 20 && offsetof(RaMeshPath, gradient) == 36, "RaMeshPath's layout, which Dart reads");
static_assert(sizeof(RaMeshData) == 120 && offsetof(RaMeshData, bounds) == 88, "RaMeshData's layout, which Dart reads");
static_assert(RA_ENTRY_BLEND_INSTANCES == Ra::Buffer::kBlendInstances && RA_ENTRY_OPAQUES == Ra::Buffer::kOpaques, "RA_ENTRY_* mirror Ra::Buffer::Type");
static_assert(sizeof(RaContours) == 40 && offsetof(RaContours, pathCount) == 32, "RaContours' layout, which Dart writes");
static_assert(sizeof(RaPathDraw) == 20 && offsetof(RaPathDraw, cap) == 16, "RaPathDraw's layout, which Dart writes");
static_assert(sizeof(RaGlow) == 16 && offsetof(RaGlow, hasColor) == 12, "RaGlow's layout, which Dart writes");
static_assert(RA_CAP_ROUND == NSVG_CAP_ROUND && RA_CAP_SQUARE == NSVG_CAP_SQUARE && RA_JOIN_ROUND == NSVG_JOIN_ROUND && RA_JOIN_BEVEL == NSVG_JOIN_BEVEL,
              "RA_CAP_* & RA_JOIN_* mirror NanoSVG's");

static constexpr Ra::ColorMatrix kIdentityMatrix = {{ 1.f, 0.f, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 0.f, 1.f }};

// C++ exceptions mustn't cross into Dart, where one aborts the process: the core's are of running out of memory, and an
// export that meets one fails as its result says, as a null handle or an empty frame, which Dart throws for
template<typename T, typename F>
static inline T guarded(T failed, F&& f) {
    try {
        return f();
    } catch (...) {
        return failed;
    }
}

static inline Ra::Transform transform(RaTransform t) {
    return Ra::Transform(t.a, t.b, t.c, t.d, t.tx, t.ty);
}
static inline RaBounds bounds(Ra::Bounds b) {
    return RaBounds{ b.lx, b.ly, b.ux, b.uy };
}

RaLayout ra_layout(void) {
    return RaLayout{
        sizeof(Ra::Color), sizeof(Ra::PathData), sizeof(Ra::Opaque), sizeof(Ra::Instance), sizeof(Ra::Edge), sizeof(Ra::Segment),
        sizeof(Ra::Point16), sizeof(Ra::Buffer::Entry),
        kColorTextureWidth, kMoleculesHeight, kFastSegments, uint32_t(kStripHeight)
    };
}

// The core parses without units, so the paths stay in the viewBox's coordinates, unscaled to the width & height
static RaBounds svgBounds(const NSVGimage *image) {
    const float *box = image->viewBox;
    return box[2] > 0.f && box[3] > 0.f ? RaBounds{ box[0], box[1], box[0] + box[2], box[1] + box[3] }
        : RaBounds{ 0.f, 0.f, image->width, image->height };
}
// nsvgParse needs a null-terminated string it can modify, & nsvgParseFromFile's arguments
static NSVGimage *parseSvgData(const char *data, uint64_t length) {
    std::vector<char> text(data, data + length);
    text.push_back('\0');
    return nsvgParse(text.data(), nullptr, 0);
}
// RaSVG::addSvgToScene, but failing when the SVG can't be parsed, & flipping its y onto its viewBox, as its paths are in
// the viewBox's coordinates, not around its height
static RaScene *sceneFromImage(NSVGimage *image, RaTransform *ctm) {
    if (image == nullptr)
        return nullptr;
    RaScene *scene = guarded<RaScene *>(nullptr, [&] {
        std::unique_ptr<RaScene> scene(new RaScene());
        RaSVG::addSvgImageToScene(image, scene->scene);
        return scene.release();
    });
    if (scene) {
        scene->svgBounds = svgBounds(image);
        if (ctm)
            *ctm = RaTransform{ 1.f, 0.f, 0.f, -1.f, 0.f, scene->svgBounds.ly + scene->svgBounds.uy };
    }
    nsvgDelete(image);
    return scene;
}
RaScene *ra_scene_from_svg(const char *path, RaTransform *ctm) {
    return sceneFromImage(nsvgParseFromFile(path, nullptr, 0), ctm);
}
RaScene *ra_scene_from_svg_data(const char *data, uint64_t length, RaTransform *ctm) {
    return sceneFromImage(guarded<NSVGimage *>(nullptr, [&] { return parseSvgData(data, length); }), ctm);
}
void ra_scene_release(RaScene *scene) {
    delete scene;
}
uint64_t ra_scene_count(const RaScene *scene) {
    return scene->scene->count();
}
RaBounds ra_scene_bounds(const RaScene *scene) {
    return bounds(scene->scene->bounds());
}
RaBounds ra_scene_svg_bounds(const RaScene *scene) {
    return scene->svgBounds;
}

RaList *ra_list_create(void) {
    return guarded<RaList *>(nullptr, [] { return new RaList(); });
}
void ra_list_release(RaList *list) {
    delete list;
}
// Empties the list, as one that couldn't be filled
static void clearList(RaList *list) {
    Ra::SceneList& l = list->list;
    l.scenes.clear(), l.ctms.clear(), l.clips.clear(), l.deviceClips.clear(), l.opacities.clear(), l.colorMatrices.clear();
}
static void addScene(RaList *list, RaScene *scene, RaTransform ctm) {
    Ra::SceneList& l = list->list;
    l.addScene(scene->scene, transform(ctm));
    if (!l.deviceClips.empty() && l.deviceClips.size() < l.scenes.size())     // Unclipped, after entries with device clips
        l.deviceClips.emplace_back(Ra::Bounds::huge());
    if (!l.opacities.empty() && l.opacities.size() < l.scenes.size())     // Opaque, after entries with opacities
        l.opacities.emplace_back(1.f);
    if (!l.colorMatrices.empty() && l.colorMatrices.size() < l.scenes.size())     // Untransformed, after entries with matrices
        l.colorMatrices.emplace_back(kIdentityMatrix);
}
void ra_list_add_scene(RaList *list, RaScene *scene, RaTransform ctm) {
    if (!guarded(false, [&] { addScene(list, scene, ctm); return true; }))
        clearList(list);
}
void ra_list_set_color_matrices(RaList *list, const float *matrices, uint64_t count) {
    if (!guarded(false, [&] { list->colorMatrices.resize(count); return true; })) {
        list->colorMatrices.clear();
        return;
    }
    if (count)
        memcpy(list->colorMatrices.data(), matrices, count * sizeof(Ra::ColorMatrix));
}
static void setEntries(RaList *list, const RaListEntry *entries, uint64_t count) {
    Ra::SceneList& l = list->list;
    clearList(list);
    bool transformed = false;
    for (uint64_t i = 0; i < count; i++)
        transformed = transformed || (entries[i].colorMatrix && entries[i].colorMatrix <= list->colorMatrices.size());
    for (uint64_t i = 0; i < count; i++) {
        const RaListEntry& e = entries[i];
        if (e.scene && e.scene->scene->count()) {
            l.addScene(e.scene->scene, transform(e.ctm));
            l.deviceClips.emplace_back(e.deviceClip.lx, e.deviceClip.ly, e.deviceClip.ux, e.deviceClip.uy);
            l.opacities.emplace_back(e.opacity);
            if (transformed)     // Lists without matrices have none, so cost nothing
                l.colorMatrices.emplace_back(e.colorMatrix && e.colorMatrix <= list->colorMatrices.size() ? list->colorMatrices[e.colorMatrix - 1] : kIdentityMatrix);
        }
    }
}
void ra_list_set_entries(RaList *list, const RaListEntry *entries, uint64_t count) {
    if (!guarded(false, [&] { setEntries(list, entries, count); return true; }))
        clearList(list);
}
void ra_list_set_ctm(RaList *list, RaTransform ctm) {
    list->list.ctm = transform(ctm);
}
void ra_list_set_params(RaList *list, RaParams params) {
    memcpy(& list->list.params, & params, sizeof(params));
}
RaParams ra_list_params(const RaList *list) {
    RaParams params;
    memcpy(& params, & list->list.params, sizeof(params));
    return params;
}
RaBounds ra_list_bounds(const RaList *list) {
    return bounds(list->list.bounds());
}

RaRenderer *ra_renderer_create(void) {
    return guarded<RaRenderer *>(nullptr, [] { return new RaRenderer(); });
}
void ra_renderer_release(RaRenderer *renderer) {
    delete renderer;
}
RaFrameBuffer *ra_frame_buffer_create(void) {
    return guarded<RaFrameBuffer *>(nullptr, [] { return new RaFrameBuffer(); });
}
void ra_frame_buffer_release(RaFrameBuffer *buffer) {
    delete buffer;
}

// An empty frame, its base null, if it couldn't be written
RaFrame ra_render(RaRenderer *renderer, const RaList *list, float w, float h, float scale, RaFrameBuffer *frameBuffer) {
    size_t size = guarded<size_t>(0, [&] { return renderer->renderer.renderList(list->list, scale, w, h, & frameBuffer->buffer); });
    if (size == 0)
        return RaFrame{};
    const Ra::Buffer& buffer = frameBuffer->buffer.buffer;
    RaFrame frame = {
        buffer.base, size,
        (const RaEntry *)buffer.entries.base, buffer.entries.end,
        buffer.colors, buffer.paths, buffer.texStrips, buffer.p16s,
        buffer.pathsCount, buffer.texCount, buffer.headerSize
    };
    memcpy(& frame.params, & buffer.params, sizeof(frame.params));
    return frame;
}

RaMesh *ra_mesh_from_svg_data(const char *data, uint64_t length, float maxSize) {
    if (!(maxSize > 0.f) || !isfinite(maxSize))
        return nullptr;
    NSVGimage *image = guarded<NSVGimage *>(nullptr, [&] { return parseSvgData(data, length); });
    if (image == nullptr)
        return nullptr;
    RaMesh *mesh = guarded<RaMesh *>(nullptr, [&] { return RasterizerMesh::createMesh(image, svgBounds(image), maxSize); });
    nsvgDelete(image);
    return mesh;
}
RaMeshData ra_mesh_data(const RaMesh *mesh) {
    bool small = mesh->indices32.empty();
    return RaMeshData{
        mesh->vertices.data(), mesh->vertices.size() / mesh->vertexFloats,
        small ? (const void *)mesh->indices16.data() : (const void *)mesh->indices32.data(),
        small ? mesh->indices16.size() : mesh->indices32.size(), small ? 2u : 4u, mesh->vertexFloats,
        small ? (const void *)mesh->stripIndices16.data() : (const void *)mesh->stripIndices32.data(),
        small ? mesh->stripIndices16.size() : mesh->stripIndices32.size(),
        mesh->paths.data(), mesh->paths.size(),
        mesh->stops.data(), mesh->stops.size(),
        bounds(mesh->bounds), mesh->svgBounds
    };
}
void ra_mesh_release(RaMesh *mesh) {
    delete mesh;
}

static RaScene *sceneFromPaths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox) {
    RasterizerPaths::Index index(*contours);
    // Each path's, written once, so a fill & a stroke of it share its geometry, as an SVG shape's do
    std::vector<Ra::Path> paths(contours->pathCount, Ra::Path(nullptr));
    std::vector<bool> written(contours->pathCount, false);
    std::unique_ptr<RaScene> scene(new RaScene());
    scene->svgBounds = viewBox;
    for (uint64_t i = 0; i < drawCount; i++) {
        const RaPathDraw& draw = draws[i];
        if (draw.path >= contours->pathCount || draw.hairline)
            continue;
        if (!written[draw.path]) {
            written[draw.path] = true;
            Ra::Path path;
            bool finite = index.forEachContour(draw.path, [&](const float *p, uint32_t count, bool closed) {
                path->moveTo(p[0], p[1]);
                for (uint32_t k = 1; k < count; k++)
                    path->lineTo(p[2 * k], p[2 * k + 1]);
                if (closed)
                    path->close();
            });
            if (finite && path->isValid())
                paths[draw.path] = path;
        }
        const Ra::Path& path = paths[draw.path];
        if (path.ptr == nullptr)
            continue;
        bool stroked = draw.strokeWidth > 0.f;
        int flags = stroked ? (draw.cap == RA_CAP_ROUND ? Ra::Draw::kRoundCap : draw.cap == RA_CAP_SQUARE ? Ra::Draw::kSquareCap : 0)
                | (draw.join == RA_JOIN_ROUND ? Ra::Draw::kRoundJoin : 0)
            : draw.evenOdd ? Ra::Draw::kFillEvenOdd : 0;
        scene->scene->addPath(path, Ra::Transform(), Ra::Color(draw.color), stroked ? draw.strokeWidth : 0.f, flags);
    }
    return scene.release();
}
RaScene *ra_scene_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox) {
    return guarded<RaScene *>(nullptr, [&] { return sceneFromPaths(contours, draws, drawCount, viewBox); });
}
RaMesh *ra_mesh_from_paths(const RaContours *contours, const RaPathDraw *draws, uint64_t drawCount, RaBounds viewBox, float tolerance, const RaGlow *glow) {
    if (!(tolerance > 0.f) || !isfinite(tolerance))
        return nullptr;
    return guarded<RaMesh *>(nullptr, [&] {
        return RasterizerMesh::createMeshFromPaths(*contours, draws, drawCount, viewBox, tolerance, glow);
    });
}
