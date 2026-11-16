#pragma once
//
//  The OpenGL ES format probe's image: probeSvg in lib/src/format_probe.dart, built as NanoSVG parses it, without parsing it
//
//  So the probe checks the GPU renderer alone. Parsed, a parser's bug would fail it as if the GPU drew wrongly, as under a
//  locale whose decimal point is a comma, where NanoSVG read fill-opacity="0.5" as 0, and the translucent paths vanished.
//  test/probe_scene_test.dart checks that this image covers the probe's pixels with the same paths as the SVG.
//

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <new>
#include <vector>
#include "core/nanosvg.h"

namespace RaProbeScene {
    // nanosvg.h's, which only its implementation defines
    static constexpr float kKappa90 = 0.5522847493f;

    // NanoSVG's points: x0, y0, then each cubic's two control points & end point
    typedef std::vector<float> Points;

    // As nsvg__lineTo: a line is a cubic with its control points at its thirds
    static inline void lineTo(Points& p, float x, float y) {
        float px = p[p.size() - 2], py = p[p.size() - 1], dx = x - px, dy = y - py;
        p.insert(p.end(), { px + dx / 3.f, py + dy / 3.f, x - dx / 3.f, y - dy / 3.f, x, y });
    }
    // As nsvg__parseRect, & nsvg__addPath's closing line
    static inline Points rect(float x, float y, float w, float h) {
        Points p = { x, y };
        lineTo(p, x + w, y), lineTo(p, x + w, y + h), lineTo(p, x, y + h), lineTo(p, x, y);
        return p;
    }
    // As nsvg__parseCircle, & nsvg__addPath's closing line, which has no length
    static inline Points circle(float cx, float cy, float r) {
        const float k = r * kKappa90;
        Points p = { cx + r, cy };
        p.insert(p.end(), { cx + r, cy + k, cx + k, cy + r, cx, cy + r });
        p.insert(p.end(), { cx - k, cy + r, cx - r, cy + k, cx - r, cy });
        p.insert(p.end(), { cx - r, cy - k, cx - k, cy - r, cx, cy - r });
        p.insert(p.end(), { cx + k, cy - r, cx + r, cy - k, cx + r, cy });
        lineTo(p, cx + r, cy);
        return p;
    }

    // nsvgDelete frees the image with free(), so it's built with malloc. Each allocation throws if it fails, & the
    // image's builder deletes what it built so far
    template<typename T>
    static inline T *alloc(size_t count = 1) {
        T *t = (T *)calloc(count, sizeof(T));
        if (t == nullptr)
            throw std::bad_alloc();
        return t;
    }
    // A closed path, & its bounds: its points', which hold its curves, as each curve's control points lie on the
    // bounds of a rectangle or circle
    static NSVGpath *path(const Points& p, NSVGpath *next) {
        float *pts = alloc<float>(p.size());
        NSVGpath *path = (NSVGpath *)calloc(1, sizeof(NSVGpath));
        if (path == nullptr) {
            free(pts);
            throw std::bad_alloc();
        }
        path->next = next;
        path->pts = pts;
        memcpy(path->pts, p.data(), p.size() * sizeof(float));
        path->npts = int(p.size() / 2), path->closed = 1;
        path->bounds[0] = path->bounds[2] = p[0], path->bounds[1] = path->bounds[3] = p[1];
        for (size_t i = 2; i < p.size(); i += 2) {
            path->bounds[0] = fminf(path->bounds[0], p[i]), path->bounds[1] = fminf(path->bounds[1], p[i + 1]);
            path->bounds[2] = fmaxf(path->bounds[2], p[i]), path->bounds[3] = fmaxf(path->bounds[3], p[i + 1]);
        }
        return path;
    }
    // A filled shape, as nsvg__addShape makes one with NanoSVG's defaults: its fill-opacity in its color's alpha, as
    // (unsigned int)(opacity * 255), & its paths in reverse order, as NanoSVG prepends each one
    static NSVGshape *shape(NSVGimage *image, NSVGshape *last, std::initializer_list<Points> paths,
                            unsigned int rgb, float fillOpacity = 1.f, bool evenOdd = false) {
        NSVGshape *shape = alloc<NSVGshape>();
        (last ? last->next : image->shapes) = shape;
        shape->fill.type = NSVG_PAINT_COLOR;
        shape->fill.color = (rgb >> 16 & 0xFF) | (rgb & 0xFF00) | (rgb & 0xFF) << 16 | (unsigned int)(fillOpacity * 255) << 24;
        shape->stroke.type = NSVG_PAINT_NONE;
        shape->opacity = 1.f, shape->strokeWidth = 1.f, shape->miterLimit = 4.f;
        shape->strokeLineJoin = NSVG_JOIN_MITER, shape->strokeLineCap = NSVG_CAP_BUTT;
        shape->fillRule = evenOdd ? NSVG_FILLRULE_EVENODD : NSVG_FILLRULE_NONZERO;
        shape->flags = NSVG_FLAGS_VISIBLE;
        for (const Points& p : paths)
            shape->paths = path(p, shape->paths);
        shape->bounds[0] = shape->bounds[1] = 1e30f, shape->bounds[2] = shape->bounds[3] = -1e30f;
        for (NSVGpath *p = shape->paths; p; p = p->next) {
            shape->bounds[0] = fminf(shape->bounds[0], p->bounds[0]), shape->bounds[1] = fminf(shape->bounds[1], p->bounds[1]);
            shape->bounds[2] = fmaxf(shape->bounds[2], p->bounds[2]), shape->bounds[3] = fmaxf(shape->bounds[3], p->bounds[3]);
        }
        return shape;
    }

    // The image, 160 x 160, its shapes back to front as probeSvg's. NULL if it runs out of memory
    static NSVGimage *image() {
        NSVGimage *image = (NSVGimage *)calloc(1, sizeof(NSVGimage));
        if (image == nullptr)
            return nullptr;
        try {
            image->width = image->height = 160.f;
            image->viewBox[2] = image->viewBox[3] = 160.f;
            NSVGshape *s = nullptr;
            s = shape(image, s, { rect(8, 8, 144, 48) }, 0xFF0000);                                    // A
            s = shape(image, s, { circle(80, 60, 40) }, 0x0000FF, 0.5f);                               // B
            s = shape(image, s, { rect(96, 40, 44, 44) }, 0x00FF00);                                   // C
            s = shape(image, s, { circle(36, 124, 30), circle(36, 124, 15) }, 0xFF00FF, 1.f, true);    // D
            s = shape(image, s, { circle(126, 128, 26), circle(126, 128, 12) }, 0xFFFF00, 0.5f);       // E
            s = shape(image, s, { rect(72, 112, 16, 16) }, 0x00FFFF);                                  // F
            s = shape(image, s, { circle(80, 146, 10) }, 0xFFA500, 0.8f);                              // G
            return image;
        } catch (...) {
            nsvgDelete(image);
            return nullptr;
        }
    }
}
