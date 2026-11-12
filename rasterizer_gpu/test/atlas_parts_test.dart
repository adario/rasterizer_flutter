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

void main() {
  /// Groups [rects] into parts. Returns each entry's part, as an index, and
  /// each part's rectangle.
  (List<int>, List<(int, int, int, int)>) group(
    List<(int, int, int, int)> rects,
  ) {
    final flat = Int32List(4 * rects.length);
    for (var i = 0; i < rects.length; i++) {
      final (lx, ly, ux, uy) = rects[i];
      flat.setAll(4 * i, [lx, ly, ux, uy]);
    }
    final parts = <(int, int, int, int)>[];
    final entryParts = List.filled(rects.length, -1);
    AtlasParts().group(flat, [for (var i = 0; i < rects.length; i++) i], (
      lx,
      ly,
      ux,
      uy,
    ) {
      parts.add((lx, ly, ux, uy));
      return parts.length - 1;
    }, (id, part) => entryParts[id] = part);
    return (entryParts, parts);
  }

  bool overlap((int, int, int, int) a, (int, int, int, int) b) =>
      a.$1 < b.$3 && b.$1 < a.$3 && a.$2 < b.$4 && b.$2 < a.$4;

  test('disjoint entries are parts of their own', () {
    final (entries, parts) = group([
      (500, 0, 600, 100),
      (0, 0, 100, 100),
      (0, 500, 100, 600),
    ]);
    expect(parts.length, 3);
    expect(entries.toSet().length, 3);
    for (var i = 0; i < 3; i++) {
      expect(
        parts[entries[i]],
        [(500, 0, 600, 100), (0, 0, 100, 100), (0, 500, 100, 600)][i],
      );
    }
  });

  test('entries that only touch are apart', () {
    final (entries, parts) = group([(0, 0, 100, 100), (100, 0, 200, 100)]);
    expect(parts.length, 2);
    expect(entries[0], isNot(entries[1]));
  });

  test('a chain of overlapping entries is one part, their union', () {
    final (entries, parts) = group([
      for (var k = 0; k < 10; k++) (50 * k, 10 * k, 50 * k + 60, 10 * k + 30),
    ]);
    expect(parts, [(0, 0, 510, 120)]);
    expect(entries, everyElement(0));
  });

  test('a nested entry is in its container\'s part', () {
    final (entries, parts) = group([(0, 0, 400, 400), (100, 100, 120, 120)]);
    expect(parts, [(0, 0, 400, 400)]);
    expect(entries, [0, 0]);
  });

  test('an entry joining two parts merges them, and those their union then '
      'overlaps', () {
    // D joins A and B, which are apart. C is apart from all three, but E
    // overlaps both A and C, so all five make one part.
    final (entries, parts) = group([
      (0, 0, 100, 100), // A
      (200, 0, 300, 100), // B
      (150, 190, 250, 250), // C
      (90, 40, 210, 60), // D
      (0, 95, 160, 200), // E
    ]);
    expect(parts, [(0, 0, 300, 250)]);
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
              x,
              y,
              x + 1 + random.nextInt(300),
              y + 1 + random.nextInt(300),
            );
          }(),
      ];
      final (entries, parts) = group(rects);
      for (var i = 0; i < n; i++) {
        final p = parts[entries[i]];
        // Each entry is within its part.
        expect(
          p.$1 <= rects[i].$1 &&
              p.$2 <= rects[i].$2 &&
              p.$3 >= rects[i].$3 &&
              p.$4 >= rects[i].$4,
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
          members.map((r) => r.$1).reduce(math.min),
          members.map((r) => r.$2).reduce(math.min),
          members.map((r) => r.$3).reduce(math.max),
          members.map((r) => r.$4).reduce(math.max),
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
          return (x, y, x + 100, y + 100);
        }(),
    ];
    final watch = Stopwatch()..start();
    final (_, parts) = group(rects);
    expect(parts.length, 1);
    expect(watch.elapsedMilliseconds, lessThan(50));
  });
}
