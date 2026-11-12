//
//  RasterizerRenderer.hpp without Metal: the frame buffer is malloc'd, & a host uploads it to the GPU itself. Its
//  dispatch_apply blocks are ra_portable.h's raParallelFor, which is GCD on Apple. Everything else is as in Rasterizer's
//  Package/Sources/RasterizerCpp/include/RasterizerRenderer.hpp (https://github.com/mindbrix/Rasterizer, commit 2be4bc16)
//

#pragma once

#include <algorithm>
#include <chrono>
#include <new>
#include <assert.h>
#include <float.h>      // Which the original gets from Metal.h, & Rasterizer.hpp needs
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "Rasterizer.hpp"


struct RenderBuffer {
    ~RenderBuffer() {
        free(buffer.base);
    }
    void allocHeader(size_t n) {
        header = 0, resize(n), header = n;
    }
    void allocContextSlices(size_t n) {
        resize(n);
    }
    size_t size() const {
        return capacity;
    }
    bool willShrink(size_t n) const {
        return header && size() > 1000000 && size() / n > 5;
    }
    void resize(size_t n) {
        if (size() < n || willShrink(n)) {
            size_t length = n * 4 / 3;
            uint8_t *newBase = (uint8_t *)calloc(length, 1);     // Zeroed, like a new MTLBuffer, so padding matches the native frames
            if (newBase == nullptr)
                throw std::bad_alloc();     // Keeping the old buffer, for ra_render to fail
            if (header && header <= size())
                memcpy(newBase, buffer.base, header);
            free(buffer.base);
            buffer.base = newBase, capacity = length;
        }
    }
    size_t header = 0, capacity = 0;
    Ra::Buffer buffer;
};


struct RasterizerRenderer {
    RasterizerRenderer() {
        contexts.resize(raProcessorCount());
    }

    // A frame uses enough contexts for about kContextSeconds of drawList work each, judged by the last frame's, as each adds a
    // fixed cost, so small scenes are faster with few. Two at least, as one is slower, & all of them for the first frame
    static constexpr double kContextSeconds = 100e-6;

    // Returns the frame's size, the bytes from the buffer's base a host must upload
    size_t renderList(const Ra::SceneList& list, float scale, float w, float h, RenderBuffer *renderBuffer) {
        Ra::Buffer *buffer = & renderBuffer->buffer;
        size_t contextCount = drawListSeconds == 0.0 ? contexts.size() : std::min(contexts.size(), std::max(size_t(2), size_t(ceil(drawListSeconds / kContextSeconds))));
        list.prepare();
        buffer->prepare(list, scale);
        renderBuffer->allocHeader(buffer->headerSize);

        auto divisions = (size_t *)RA_ALLOCA((contextCount + 1) * sizeof(size_t));
        auto seconds = (double *)RA_ALLOCA(contextCount * sizeof(double));
        writeDivisions(list, contextCount, divisions);
        raParallelFor(contextCount, [&](size_t i) {
            auto t0 = std::chrono::steady_clock::now();
            contexts[i].drawList(list, scale, w, h, divisions[i], divisions[i + 1], buffer);
            seconds[i] = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        });
        drawListSeconds = 0.0;
        for (size_t i = 0; i < contextCount; i++)
            drawListSeconds += seconds[i];
        auto begins = (size_t *)RA_ALLOCA(contextCount * sizeof(size_t));
        size_t size = Ra::resizeBuffer(list, & contexts[0], contextCount, begins, *buffer);
        bool willShrink = renderBuffer->willShrink(size);
        renderBuffer->allocContextSlices(size);

        Ra::writeOpaques(list, & contexts[0], contextCount, begins, *buffer);
        Ra::coalescePasses(& contexts[0], contextCount);
        raParallelFor(contextCount, [&](size_t i) {
            Ra::writeContextToBuffer(list, & contexts[0] + i, begins[i], i, contextCount, *buffer);
        });
        Ra::writeEntries(& contexts[0], contextCount, *buffer);
        size_t end = buffer->entries.end == 0 ? 0 : buffer->entries.back().end;
        assert(size >= end);

        auto colors = (Ra::Color *)(buffer->base + buffer->colors);
        colors[buffer->pathsCount] = buffer->params.clearColor;

        if (willShrink)
            reset();
        return size;
    }

    // Split the list into contiguous draw ranges of equal prepared weight
    static void writeDivisions(const Ra::SceneList& list, size_t count, size_t *divisions) {
        size_t total = 0, pathsCount = list.pathsCount(), sum = 0, base = 0, j = 0, target;
        for (auto& scene : list.scenes)
            total += scene->weight;
        divisions[0] = 0, divisions[count] = pathsCount;
        for (size_t i = 1; i < count; i++) {
            if (total == 0) {
                divisions[i] = i * pathsCount / count;
                continue;
            }
            for (target = total * i / count; j < list.scenes.size() && sum + list.scenes[j]->weight < target; j++)
                sum += list.scenes[j]->weight, base += list.scenes[j]->count();
            if (j == list.scenes.size())
                divisions[i] = pathsCount;
            else {
                const Ra::Scene& scene = *list.scenes[j].ptr;
                divisions[i] = base + (std::lower_bound(scene.weights.base, scene.weights.base + scene.count(), target - sum) - scene.weights.base);
            }
        }
    }

    void reset() {
        for (auto& ctx : contexts)
            ctx.reset();
    }

    std::vector<Ra::Context> contexts;
    double drawListSeconds = 0.0;   // The last frame's total
 };
