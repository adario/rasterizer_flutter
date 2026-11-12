// Checks the sizes of the GPU renderer's atlas pages, and of the mesh
// renderer's targets, without textures. From this package's folder:
//   flutter test test/atlas_pages_test.dart
//
// Pages grow at once. They shrink at the end of a window of 120 frames, to
// what those frames needed, if that's below half their area or the viewport
// changed. A trim shrinks them too. Pages that no frame needed for 120 frames
// are released. The mesh renderer's targets grow in its own steps, and shrink
// below 3/4 of their area. The textures that follow these sizes are checked
// by example/integration_test/atlas_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/atlas_pages.dart';

void main() {
  const portrait = (1080, 2400), landscape = (2400, 1080);

  /// Plays a frame as the renderer does: grows each page to fit its entry in
  /// [needs], then ends the frame.
  void frame(AtlasPages pages, (int, int) viewport, List<(int, int)> needs) {
    for (var p = 0; p < needs.length; p++) {
      pages.fit(p, needs[p].$1, needs[p].$2);
    }
    pages.endFrame(viewport.$1, viewport.$2, needs);
  }

  List<(int, int)> sizes(AtlasPages pages) => [
    for (var p = 0; p < pages.length; p++) pages[p],
  ];

  test('pages grow at once, in steps, up to the maximum size', () {
    final pages = AtlasPages(4096);
    expect(pages.fit(0, 1080, 2400), (1280, 2560));
    expect(pages.fit(0, 1000, 2000), (1280, 2560));
    expect(pages.fit(0, 2400, 1080), (2560, 2560));
    expect(pages.fit(1, 1, 5000), (256, 4096));
    expect(pages.resizes, 3);
  });

  test('without a viewport change, pages shrink only below half', () {
    final pages = AtlasPages(8192);
    // Heavy and light frames alternate every 60 frames, as a game's zoom can
    // make them. Each window holds heavy frames, so the page never shrinks.
    for (var i = 0; i < 1000; i++) {
      frame(pages, portrait, [(1080, (i ~/ 60).isEven ? 5400 : 1600)]);
    }
    expect(sizes(pages), [(1280, 5632)]);
    expect(pages.resizes, 1);
  });

  test('after a viewport change, pages shrink once its 120 frames are done, to '
      'the largest they needed', () {
    final pages = AtlasPages(8192);
    frame(pages, portrait, [portrait]);
    for (var i = 0; i < 119; i++) {
      frame(pages, landscape, [landscape]);
    }
    expect(sizes(pages), [(2560, 2560)]);
    // The turn to landscape is a viewport change, so the page shrinks at the
    // window's end.
    frame(pages, landscape, [landscape]);
    expect(sizes(pages), [(2560, 1280)]);
    // Back in portrait, a heavy frame grows the page at once.
    for (var i = 0; i < 119; i++) {
      frame(pages, portrait, [(1080, i == 50 ? 2400 : 1200)]);
    }
    expect(sizes(pages), [(2560, 2560)]);
    frame(pages, portrait, [(1080, 1200)]);
    expect(sizes(pages), [(1280, 2560)]);
    // Without another viewport change, it doesn't shrink again.
    for (var i = 0; i < 500; i++) {
      frame(pages, portrait, [(1080, 1200)]);
    }
    expect(sizes(pages), [(1280, 2560)]);
    expect(pages.resizes, 5);
  });

  test('another change restarts the window', () {
    final pages = AtlasPages(8192);
    frame(pages, landscape, [landscape]);
    for (var i = 0; i < 100; i++) {
      frame(pages, (1080, 2300), [(1080, 2300)]);
    }
    for (var i = 0; i < 119; i++) {
      frame(pages, portrait, [portrait]);
    }
    expect(sizes(pages), [(2560, 2560)]);
    frame(pages, portrait, [portrait]);
    expect(sizes(pages), [(1280, 2560)]);
  });

  test('a shrink never grows a page past its size', () {
    final pages = AtlasPages(8192);
    frame(pages, landscape, [(2400, 1080)]);
    for (var i = 0; i < 120; i++) {
      frame(pages, portrait, [(1080, 2000)]);
    }
    // The width shrinks. The height grew at once, at the first portrait frame.
    expect(sizes(pages), [(1280, 2048)]);
  });

  test(
    'pages no frame needed for 120 frames are released, from the last one down',
    () {
      final pages = AtlasPages(8192);
      frame(pages, portrait, [portrait, portrait, (1080, 500)]);
      for (var i = 0; i < 119; i++) {
        frame(pages, portrait, [portrait]);
      }
      expect(pages.length, 3);
      frame(pages, portrait, [portrait]);
      expect(sizes(pages), [(1280, 2560)]);
      final resizes = pages.resizes;
      // A page needed again is a new page, so another reallocation.
      frame(pages, portrait, [portrait, portrait]);
      expect(pages.length, 2);
      expect(pages.resizes, resizes + 1);
      // With no runs at all, even the first page is released.
      for (var i = 0; i < 120; i++) {
        frame(pages, portrait, const []);
      }
      expect(pages.length, 0);
    },
  );

  test('a page used now and then stays', () {
    final pages = AtlasPages(8192);
    for (var i = 0; i < 1000; i++) {
      frame(pages, portrait, [portrait, if (i % 100 == 0) portrait]);
    }
    expect(pages.length, 2);
    expect(pages.resizes, 2);
  });

  test(
    'trim shrinks pages to the last frame\'s needs and releases the rest',
    () {
      final pages = AtlasPages(8192);
      frame(pages, portrait, [(1080, 5400), portrait]);
      frame(pages, portrait, [(1080, 1000)]);
      expect(sizes(pages), [(1280, 5632), (1280, 2560)]);
      pages.trim();
      expect(sizes(pages), [(1280, 1024)]);
      // A heavier frame grows the page again at once.
      frame(pages, portrait, [portrait]);
      expect(sizes(pages), [(1280, 2560)]);
    },
  );

  test('trim before any frame releases nothing it has, as it has nothing', () {
    final pages = AtlasPages(8192)..trim();
    expect(pages.length, 0);
  });

  test('without a viewport change, a page shrinks at the end of a window whose '
      'frames needed below half of it, to the largest they needed', () {
    final pages = AtlasPages(8192);
    frame(pages, portrait, [(1080, 5400)]);
    expect(sizes(pages), [(1280, 5632)]);
    // The first window holds the heavy frame, so the page doesn't shrink.
    for (var i = 0; i < 119; i++) {
      frame(pages, portrait, [(1080, i == 100 ? 2000 : 1000)]);
    }
    expect(sizes(pages), [(1280, 5632)]);
    for (var i = 0; i < 120; i++) {
      frame(pages, portrait, [(1080, i == 100 ? 2000 : 1000)]);
    }
    expect(sizes(pages), [(1280, 2048)]);
    // Then it doesn't shrink again while frames need half of it.
    for (var i = 0; i < 600; i++) {
      frame(pages, portrait, [(1080, 1024)]);
    }
    expect(sizes(pages), [(1280, 2048)]);
    // Exactly half isn't below it: 1000 rounds up to 1024. But 700 rounds up
    // to 768, which is, so the page shrinks at the end of the window.
    for (var i = 0; i < 120; i++) {
      frame(pages, portrait, [(1080, 1000)]);
    }
    expect(sizes(pages), [(1280, 2048)]);
    for (var i = 0; i < 119; i++) {
      frame(pages, portrait, [(1080, 700)]);
    }
    expect(sizes(pages), [(1280, 2048)]);
    frame(pages, portrait, [(1080, 600)]);
    expect(sizes(pages), [(1280, 768)]);
    expect(pages.resizes, 3);
  });

  test('a page shrinks at most once a window', () {
    final pages = AtlasPages(8192);
    frame(pages, portrait, [(4000, 4000)]);
    // Needs fall frame by frame, yet the page shrinks only at a window's end,
    // to that window's largest need.
    for (var i = 0; i < 240; i++) {
      frame(pages, portrait, [(4000 - 15 * i, 4000 - 15 * i)]);
      if (i == 118) {
        expect(sizes(pages), [(4096, 4096)]);
      }
    }
    expect(sizes(pages), [(2304, 2304)]);
    expect(pages.resizes, 2);
  });

  test('as the mesh renderer\'s targets, a page in 64 px steps shrinks at the '
      'end of a window whose frames needed below 3/4 of it', () {
    final pages = AtlasPages(8192, step: 64, shrinkBelow: 0.75);
    const window = (2880, 1620), tube = (1600, 1600);
    // A run that first covers the window, as stars around a tube do, then
    // only the tube.
    frame(pages, window, [window]);
    expect(sizes(pages), [(2880, 1664)]);
    for (var i = 0; i < 119; i++) {
      frame(pages, window, [tube]);
    }
    expect(sizes(pages), [(2880, 1664)]);
    // The tube needs 53% of the page: below 3/4, though not below half.
    for (var i = 0; i < 120; i++) {
      frame(pages, window, [tube]);
    }
    expect(sizes(pages), [(1600, 1600)]);
    // Then it doesn't shrink again for 92% of it.
    for (var i = 0; i < 240; i++) {
      frame(pages, window, [(1500, 1500)]);
    }
    expect(sizes(pages), [(1600, 1600)]);
    expect(pages.resizes, 2);
  });
}
