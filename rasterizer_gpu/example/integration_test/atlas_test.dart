// Checks that the GPU renderer's atlas pages shrink after viewport changes,
// and after trims, in the app:
//   flutter test integration_test/atlas_test.dart -d <device>
//
// The GPU renderer rasterizes entries into atlas pages: textures that it
// sizes to what recent frames needed. Here the viewport turns between
// portrait and landscape every 150 frames, 6 times. Heavy frames, of 8 runs,
// and light ones, of 1 run, alternate every 60 frames. So the pages grow,
// shrink 120 frames after each turn, and shrink again after light frames
// only. The test reads back the frames around each shrink, and compares them
// with the same frame from a fresh renderer, whose pages never changed size.
// Reallocating pages back and forth used to garble frames, or hang the GPU
// on the Android emulator's Vulkan.
//
// On OpenGL ES, as on an Android emulator built with
// IMPELLER_BACKEND=opengles, the test runs once the GPU renderer's self-test
// passes. test/atlas_pages_test.dart checks the sizing itself.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu_example/goldens.dart';
import 'package:rasterizer_gpu_example/scenes.dart';

Future<void> main() async {
  // Fully live, so that frames are drawn: on OpenGL ES, initialize waits for
  // one, and the test steps frame by frame.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;
  runApp(const SizedBox());
  await RasterizerGpu.initialize();
  if (RasterizerGpu.support != RasterizerSupport.supported) {
    test(
      'no GPU renderer here',
      () {},
      skip:
          'support ${RasterizerGpu.support.name}: '
          '${RasterizerGpu.supportDetail}',
    );
    return;
  }

  const portrait = (720, 1600), landscape = (1600, 720);
  const phase = 150,
      alternate = 60,
      window = 120,
      heavyRuns = 8,
      perRun = 25,
      time = 7.3;
  final motion = AtlasMotion(entries: heavyRuns * perRun);
  late List<RasterizerScene> svgs;

  setUpAll(
    () => svgs = [
      for (final s in generatedSvgs(50))
        RasterizerScene.fromSvg(utf8.encode(s)),
    ],
  );
  tearDownAll(() {
    for (final s in svgs) {
      s.dispose();
    }
  });

  /// Renders a frame of [runs] runs of [perRun] entries each, for [viewport].
  ///
  /// With [place], each run is placed on the atlas as it ends, as games do.
  /// Otherwise, the frame packs them all as it renders. With [trim], a trim
  /// is asked for while the frame is built.
  RasterizerFrame frame(
    RasterizerRenderer renderer,
    (int, int) viewport,
    int runs, {
    required bool place,
    bool trim = false,
  }) {
    final (w, h) = viewport;
    final size = ui.Size(w.toDouble(), h.toDouble());
    final frame = renderer.beginFrame(w, h);
    for (var k = 0; k < runs; k++) {
      final run = frame.addRun();
      for (var i = k * perRun; i < (k + 1) * perRun; i++) {
        final (a, b, c, d, tx, ty) = motion.transform(i, time, size);
        run.add(svgs[motion.svg(i)], a, b, c, d, tx, ty);
      }
      if (place) {
        run.place();
      }
      // A trim asked for while the frame is being built waits for the frame.
      if (trim && k == 0) {
        renderer.trimAtlas();
      }
    }
    frame.render();
    return frame;
  }

  /// Reads back each run's parts: the rectangles of the atlas pages that they
  /// were rasterized into.
  Future<List<GoldenImage>> runImages(RasterizerFrame frame) async {
    // Request every page's readback before awaiting any.
    final images = {
      for (final run in frame.runs)
        for (final part in run.parts) part.page: part.image,
    };
    final reads = {
      for (final MapEntry(:key, :value) in images.entries) key: readRgba(value),
    };
    final pages = {
      for (final MapEntry(:key, :value) in reads.entries)
        key: Uint8List.sublistView((await value)!),
    };
    return [
      for (final run in frame.runs)
        for (final (k, part) in run.parts.indexed)
          () {
            final s = part.source,
                w = s.width.toInt(),
                h = s.height.toInt(),
                page = pages[part.page]!;
            final out = Uint8List(w * h * 4);
            for (var y = 0; y < h; y++) {
              final from =
                  (s.top.toInt() + y) * part.image.width + s.left.toInt();
              out.setRange(4 * y * w, 4 * (y + 1) * w, page, 4 * from);
            }
            return GoldenImage('run${run.index} part $k', w, h, out);
          }(),
    ];
  }

  /// Compares the frame that [subject] just rendered with the same frame from
  /// a fresh renderer, and returns the failures, if any.
  Future<List<String>> check(
    String at,
    RasterizerFrame subject,
    (int, int) viewport,
    int runs,
  ) async {
    final actual = await runImages(subject);
    List<ui.Rect> rectangles(RasterizerFrame frame) => [
      for (final run in frame.runs)
        for (final part in run.parts) part.destination,
    ];
    final subjectRectangles = rectangles(subject);
    final fresh = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.gpu,
    );
    try {
      final reference = frame(fresh, viewport, runs, place: false);
      final expected = await runImages(reference);
      final failures = <String>[], diffs = <String>[];
      var over8 = 0, area = 0;
      final referenceRectangles = rectangles(reference);
      if (subjectRectangles.length != referenceRectangles.length) {
        return [
          '$at: ${subjectRectangles.length} parts, not '
              '${referenceRectangles.length}',
        ];
      }
      for (var k = 0; k < referenceRectangles.length; k++) {
        final r = referenceRectangles[k];
        if (subjectRectangles[k] != r) {
          failures.add(
            '$at part $k: rectangle ${subjectRectangles[k]}, not $r',
          );
          continue;
        }
        // Pages of other sizes round the runs' transforms differently, so
        // antialiasing can differ slightly. As in the golden tests' atlas
        // check, the tolerance applies to all the frame's parts together, as
        // a part may be only a few pixels.
        final diff = GoldenDiff(expected[k], actual[k]);
        over8 += diff.over8;
        area += expected[k].width * expected[k].height;
        if (diff.over8 > 0) {
          diffs.add('$at part $k: $diff');
        }
      }
      if (over8 > area ~/ 10000) {
        failures.addAll(diffs);
      }
      return failures;
    } finally {
      fresh.dispose();
    }
  }

  Future<void> nextFrame() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  String mb(int bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

  // The frames checked in each phase: two heavy ones right after the turn,
  // the first light one, the window's last, the shrink's frames as each slot
  // reallocates, and the phase's last.
  const checked = {
    0,
    2,
    alternate,
    window - 1,
    window,
    window + 1,
    window + 3,
    phase - 1,
  };

  for (final place in [true, false]) {
    test('turns, with heavy and light frames, '
        '${place ? 'placed as they end' : 'packed at render'}', () async {
      final renderer = await RasterizerRenderer.create(
        backend: RasterizerBackend.gpu,
      );
      final failures = <String>[], bytes = <int>[];
      const phases = 7;
      try {
        for (var p = 0; p < phases; p++) {
          final viewport = p.isEven ? portrait : landscape;
          for (var f = 0; f < phase; f++) {
            final heavy = (f ~/ alternate).isEven, runs = heavy ? heavyRuns : 1;
            final subject = frame(renderer, viewport, runs, place: place);
            if (checked.contains(f)) {
              failures.addAll(
                await check('phase $p frame $f', subject, viewport, runs),
              );
            }
            if (f == phase - 1) {
              bytes.add(renderer.atlasBytes);
              // ignore: avoid_print
              print(
                '  phase $p, ${viewport.$1}x${viewport.$2}: pages '
                '${subject.pageSizes} (last frame), '
                '${mb(renderer.atlasBytes)}, '
                '${renderer.atlasResizes} resizes',
              );
            }
            await nextFrame();
          }
        }
        expect(failures, isEmpty);
        // After the first turns, each orientation's pages end as they did the
        // last time: shrunk back, not grown for good.
        expect(bytes[4], bytes[2]);
        expect(bytes[6], bytes[2]);
        expect(bytes[5], bytes[3]);
        expect(bytes[2], lessThanOrEqualTo(bytes[0]));

        // Then light frames only, in the last phase's viewport. They need less
        // than half of the page, so it shrinks once a window of them is done.
        // That can take up to two windows, as the last phase's heavy frames
        // end within the first.
        for (var f = 0; f <= 2 * window + 3; f++) {
          frame(renderer, portrait, 1, place: place);
          await nextFrame();
        }
        final light = renderer.atlasBytes;
        // ignore: avoid_print
        print('  light frames: ${mb(light)}');
        expect(light, lessThan(bytes[6]));
        // A trim shrinks the remaining page to what the light frame needs,
        // once each slot reallocates.
        renderer.trimAtlas();
        for (var f = 0; f < 4; f++) {
          final subject = frame(renderer, portrait, 1, place: place);
          failures.addAll(
            await check('after the trim, frame $f', subject, portrait, 1),
          );
          await nextFrame();
        }
        // ignore: avoid_print
        print('  trimmed: ${mb(renderer.atlasBytes)}');
        // Pages that the window found less than half used may have shrunk
        // already, so the trim may have nothing left to do.
        expect(renderer.atlasBytes, lessThanOrEqualTo(light));
        // A trim asked for while a heavy frame is built. The frame then grows
        // the pages again.
        final subject = frame(
          renderer,
          portrait,
          heavyRuns,
          place: place,
          trim: true,
        );
        failures.addAll(
          await check('trimmed while built', subject, portrait, heavyRuns),
        );
        final next = frame(renderer, portrait, heavyRuns, place: place);
        failures.addAll(await check('after that', next, portrait, heavyRuns));
        expect(failures, isEmpty);
      } finally {
        renderer.dispose();
      }
      // About 1200 frames, with checks, take 25 s on macOS and about a minute
      // on the Android emulator.
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
