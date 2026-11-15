// Checks how the GPU renderer groups a run's entries into parts, without
// textures. From this package's folder:
//   flutter test test/atlas_parts_test.dart
//
// Each entry has a rectangle. An entry whose rectangle overlaps a part's
// joins that part, whose rectangle is its entries' union. So entries in
// different parts never overlap. The rectangles themselves, each entry's
// bounds with a margin, are checked by
// example/integration_test/atlas_test.dart.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/atlas_parts.dart';

/// A rectangle, from its least x and y to its greatest.
typedef _Box = ({int minX, int minY, int maxX, int maxY});

void main() {
  /// Groups [rects] into parts. Returns each entry's part, as an index, and
  /// each part's rectangle.
  ({List<int> entryParts, List<_Box> parts}) group(List<_Box> rects) {
    final flat = Int32List(4 * rects.length);
    for (var i = 0; i < rects.length; i++) {
      final (minX: lx, minY: ly, maxX: ux, maxY: uy) = rects[i];
      flat.setAll(4 * i, [lx, ly, ux, uy]);
    }
    final parts = <_Box>[];
    final entryParts = List.filled(rects.length, -1);
    AtlasParts().group(flat, [for (var i = 0; i < rects.length; i++) i], (
      lx,
      ly,
      ux,
      uy,
    ) {
      parts.add((minX: lx, minY: ly, maxX: ux, maxY: uy));
      return parts.length - 1;
    }, (id, part) => entryParts[id] = part);
    return (entryParts: entryParts, parts: parts);
  }

  bool overlap(_Box a, _Box b) =>
      a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY;

  test('disjoint entries are parts of their own', () {
    final (entryParts: entries, :parts) = group([
      (minX: 500, minY: 0, maxX: 600, maxY: 100),
      (minX: 0, minY: 0, maxX: 100, maxY: 100),
      (minX: 0, minY: 500, maxX: 100, maxY: 600),
    ]);
    expect(parts.length, 3);
    expect(entries.toSet().length, 3);
    for (var i = 0; i < 3; i++) {
      expect(
        parts[entries[i]],
        [
          (minX: 500, minY: 0, maxX: 600, maxY: 100),
          (minX: 0, minY: 0, maxX: 100, maxY: 100),
          (minX: 0, minY: 500, maxX: 100, maxY: 600),
        ][i],
      );
    }
  });

  test('entries that only touch are apart', () {
    final (entryParts: entries, :parts) = group([
      (minX: 0, minY: 0, maxX: 100, maxY: 100),
      (minX: 100, minY: 0, maxX: 200, maxY: 100),
    ]);
    expect(parts.length, 2);
    expect(entries[0], isNot(entries[1]));
  });

  test('a chain of overlapping entries is one part, their union', () {
    final (entryParts: entries, :parts) = group([
      for (var k = 0; k < 10; k++)
        (minX: 50 * k, minY: 10 * k, maxX: 50 * k + 60, maxY: 10 * k + 30),
    ]);
    expect(parts, [(minX: 0, minY: 0, maxX: 510, maxY: 120)]);
    expect(entries, everyElement(0));
  });

  test('a nested entry is in its container\'s part', () {
    final (entryParts: entries, :parts) = group([
      (minX: 0, minY: 0, maxX: 400, maxY: 400),
      (minX: 100, minY: 100, maxX: 120, maxY: 120),
    ]);
    expect(parts, [(minX: 0, minY: 0, maxX: 400, maxY: 400)]);
    expect(entries, [0, 0]);
  });

  test('an entry joining two parts merges them, and those their union then '
      'overlaps', () {
    // D joins A and B, which are apart. C is apart from all three, but E
    // overlaps both A and C, so all five make one part.
    final (entryParts: entries, :parts) = group([
      (minX: 0, minY: 0, maxX: 100, maxY: 100), // A
      (minX: 200, minY: 0, maxX: 300, maxY: 100), // B
      (minX: 150, minY: 190, maxX: 250, maxY: 250), // C
      (minX: 90, minY: 40, maxX: 210, maxY: 60), // D
      (minX: 0, minY: 95, maxX: 160, maxY: 200), // E
    ]);
    expect(parts, [(minX: 0, minY: 0, maxX: 300, maxY: 250)]);
    expect(entries, everyElement(0));
  });

  test('entries in different parts never overlap, whatever their layout', () {
    final random = math.Random(26);
    for (var round = 0; round < 200; round++) {
      final n = 1 + random.nextInt(60);
      final rects = [
        for (var i = 0; i < n; i++)
          () {
            final x = random.nextInt(2000), y = random.nextInt(1200);
            return (
              minX: x,
              minY: y,
              maxX: x + 1 + random.nextInt(300),
              maxY: y + 1 + random.nextInt(300),
            );
          }(),
      ];
      final (entryParts: entries, :parts) = group(rects);
      for (var i = 0; i < n; i++) {
        final p = parts[entries[i]];
        // Each entry is within its part.
        expect(
          p.minX <= rects[i].minX &&
              p.minY <= rects[i].minY &&
              p.maxX >= rects[i].maxX &&
              p.maxY >= rects[i].maxY,
          isTrue,
        );
        for (var j = i + 1; j < n; j++) {
          if (entries[i] != entries[j]) {
            expect(overlap(rects[i], rects[j]), isFalse, reason: '$i, $j');
          }
        }
      }
      // Each part is its entries' union.
      for (var q = 0; q < parts.length; q++) {
        final members = [
          for (var i = 0; i < n; i++)
            if (entries[i] == q) rects[i],
        ];
        expect(members, isNotEmpty);
        expect(parts[q], (
          minX: members.map((r) => r.minX).reduce(math.min),
          minY: members.map((r) => r.minY).reduce(math.min),
          maxX: members.map((r) => r.maxX).reduce(math.max),
          maxY: members.map((r) => r.maxY).reduce(math.max),
        ));
      }
    }
  });

  test('a thousand entries piled up are one part, quickly', () {
    final random = math.Random(1);
    final rects = [
      for (var i = 0; i < 1000; i++)
        () {
          final x = random.nextInt(400), y = random.nextInt(400);
          return (minX: x, minY: y, maxX: x + 100, maxY: y + 100);
        }(),
    ];
    final watch = Stopwatch()..start();
    final parts = group(rects).parts;
    expect(parts.length, 1);
    expect(watch.elapsedMilliseconds, lessThan(50));
  });
}
