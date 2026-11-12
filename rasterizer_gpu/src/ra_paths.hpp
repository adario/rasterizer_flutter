//
//  Paths: plain paths flattened into polylines in Dart (lib/src/paths/path_contours.dart), each drawn with its paint,
//  by scenes as their polylines' lines, & by meshes as their fills' & strokes' triangles
//

#pragma once

#include <math.h>
#include <stdint.h>
#include <vector>
#include "ra_capi.h"

struct RasterizerPaths {
    // Where each of a RaContours' paths' contours begin, & each contour's points
    struct Index {
        Index(const RaContours& contours) : contours(contours) {
            uint64_t contour = 0, point = 0;
            for (uint64_t i = 0; i < contours.pathCount; i++)
                pathContours.push_back(contour), contour += contours.contourCounts[i];
            pathContours.push_back(contour);
            for (uint64_t i = 0; i < contour; i++)
                contourPoints.push_back(point), point += contours.pointCounts[i];
            contourPoints.push_back(point);
        }
        // Calls f(const float *points, uint32_t count, bool closed) for each of path's contours with points, & returns false
        // without calling it if one of their points isn't finite
        template<typename F>
        bool forEachContour(uint64_t path, F f) const {
            uint64_t c0 = pathContours[path], c1 = pathContours[path + 1];
            for (uint64_t i = 2 * contourPoints[c0], end = 2 * contourPoints[c1]; i < end; i++)
                if (!isfinite(contours.points[i]))
                    return false;
            for (uint64_t c = c0; c < c1; c++)
                if (contours.pointCounts[c])
                    f(contours.points + 2 * contourPoints[c], contours.pointCounts[c], contours.closed[c] != 0);
            return true;
        }
        const RaContours& contours;
        std::vector<uint64_t> pathContours, contourPoints;
    };
};
