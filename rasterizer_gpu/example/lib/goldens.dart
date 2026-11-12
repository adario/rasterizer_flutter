import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'affine.dart';
import 'golden_atlas.dart';
import 'png.dart';
import 'scenes.dart';

/// The size of a golden image, in pixels.
///
/// Golden images are reference renders of rasterizer_gpu's renderers, one
/// set per platform, in `goldens/<set>/<name>.png`, where [goldenSet] picks
/// the set. Each image is one run, a group of entries that a renderer draws
/// on its own (see [RasterizerRun]), as drawn into a viewport of this size.
/// So it doesn't depend on where the run's parts lie in the atlas. Its
/// pixels are the raw, premultiplied RGBA read back from the GPU, over
/// transparent.
///
/// The GPU renderer's goldens were checked against the original Metal
/// renderer before it was dropped, and the ios set against the macos set
/// once it was gone. So a render that matches its golden still matches the
/// original. Gradients are the exception: since the core's gradient patches,
/// the goldens of the atlas frame and the gradient cases stand for Chrome's
/// renders instead. The core is Rasterizer's C++ library, which the GPU
/// renderer draws with.
///
/// The canvas renderer is checked against the same goldens, with the looser
/// tolerance of [GoldenDiff.passesCanvas], as it antialiases differently.
/// The mesh renderer, whose edges are multisampled, has its own goldens,
/// `mesh_<name>.png` in the same folders. Its renders are also checked
/// against the GPU renderer's goldens with the canvas renderer's tolerance,
/// so that a golden it records can't hide a wrong shape or colour. Strokes
/// thinner than a pixel are the exception: see [GoldenCase.meshAsGpu].
const goldenWidth = 1024, goldenHeight = 768;

/// The folder of this platform's golden set.
///
/// - macos: the Mac, and the iOS Simulator, which renders with the Mac's GPU
///   and matches it.
/// - ios: iOS devices, whose GPUs round differently from the Mac's, by 1/255
///   on a few pixels.
/// - android_emulator: the Android emulator, whose Vulkan runs on the host's
///   GPU. android_emulator_gles: the emulator with Impeller's OpenGL ES
///   backend, which runs on the CPU (SwiftShader, through ANGLE).
/// - android: Android devices. It has no goldens yet, so a first run records
///   them.
/// - linux_llvmpipe: Linux, whose Impeller renders with OpenGL ES, on Mesa's
///   CPU renderer, which tool/linux's image picks with GALLIUM_DRIVER.
///   linux: Linux on a GPU, which has no goldens yet either.
/// - macos on the web too: only the canvas renderer draws there, and it
///   never writes goldens, so its renders are checked against the macos set.
String get goldenSet => kIsWeb
    ? 'macos'
    : Platform.isAndroid
    ? _isAndroidEmulator()
          ? RasterizerGpu.openGles
                ? 'android_emulator_gles'
                : 'android_emulator'
          : 'android'
    : Platform.isLinux
    ? Platform.environment['GALLIUM_DRIVER'] == 'llvmpipe'
          ? 'linux_llvmpipe'
          : 'linux'
    // A Simulator app's bundle is in the Mac's CoreSimulator/Devices folder.
    : Platform.isIOS &&
          !Platform.resolvedExecutable.contains('/CoreSimulator/Devices/')
    ? 'ios'
    : 'macos';

/// Whether this Android device is an emulator, from its system properties.
///
/// On the emulator's images, `ro.boot.qemu` is 1, and `ro.hardware` is
/// ranchu or goldfish.
bool _isAndroidEmulator() {
  String prop(String name) {
    try {
      return (Process.runSync('getprop', [name]).stdout as String).trim();
    } on ProcessException {
      return '';
    }
  }

  return prop('ro.boot.qemu') == '1' ||
      const {'ranchu', 'goldfish'}.contains(prop('ro.hardware'));
}

/// Reads [image]'s raw RGBA through a canvas.
///
/// It draws [image] into a picture of its size, with [ui.BlendMode.src], and
/// reads back that picture's image. On Impeller's OpenGL ES backend, reading
/// the image of a Flutter GPU texture directly gives zeros or an earlier
/// frame's pixels. On Metal and Vulkan, both ways read the same.
Future<ByteData?> readRgba(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawImage(image, ui.Offset.zero, ui.Paint()..blendMode = ui.BlendMode.src);
  final picture = recorder.endRecording();
  final copy = await picture.toImage(image.width, image.height);
  picture.dispose();
  try {
    return await copy.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    copy.dispose();
  }
}

/// An image to compare with a golden, or a golden itself: [rgba] holds its
/// raw, premultiplied pixels.
class GoldenImage(
  final String name,
  final int width,
  final int height,
  final Uint8List rgba,
) {
  /// Encodes it as a PNG file.
  Uint8List toPng() => encodePng(width, height, rgba);

  /// Returns the same image under another [name].
  GoldenImage renamed(String name) => GoldenImage(name, width, height, rgba);

  /// Decodes a [png] file, as written by [toPng].
  static GoldenImage fromPng(String name, Uint8List png) {
    final (w, h, rgba) = decodePng(png);
    return GoldenImage(name, w, h, rgba);
  }
}

/// How two images of the same size differ.
///
/// A pixel's difference is the largest difference among its channels, out of
/// 255. It counts the pixels whose difference is over 0, over 2, over 8 and
/// over 64, and keeps the largest difference and the mean of all pixels'.
class GoldenDiff(GoldenImage a, GoldenImage b) {
  this : _a = a, _b = b, pixels = a.width * a.height {
    if (a.width != b.width || a.height != b.height) {
      throw ArgumentError(
        '${a.name}: ${a.width}x${a.height} against ${b.width}x${b.height}',
      );
    }
    final x = a.rgba, y = b.rgba;
    for (var i = 0; i < x.length; i += 4) {
      var d = 0;
      for (var k = 0; k < 4; k++) {
        final v = (x[i + k] - y[i + k]).abs();
        if (v > d) {
          d = v;
        }
      }
      if (d == 0) {
        continue;
      }
      differing++;
      if (d > 2) {
        over2++;
      }
      if (d > 8) {
        over8++;
      }
      if (d > 64) {
        over64++;
      }
      if (d > largest) {
        largest = d;
      }
      total += d;
    }
  }

  final GoldenImage _a, _b;
  final int pixels;
  int differing = 0, over2 = 0, over8 = 0, over64 = 0, largest = 0, total = 0;

  double get mean => total / pixels;

  /// Whether the images match within the tolerance.
  ///
  /// At most 1 pixel in 10,000 may differ by over 2/255, at most 1% by any,
  /// and none by over 16/255. The core can write a frame's edges in another
  /// order from one render to the next, so it sums their coverage in another
  /// order too. In the tiger's sweep, that changed a few pixels by up to
  /// 6/255. On the emulator, one frame varied by 1/255 on 361 pixels.
  bool get passes =>
      over2 <= pixels ~/ 10000 && differing <= pixels ~/ 100 && largest <= 16;

  /// Whether the images match within the canvas renderer's tolerance against
  /// the GPU goldens.
  ///
  /// vector_graphics_compiler parses the canvas renderer's SVGs, rather than
  /// NanoSVG, and Impeller antialiases its paths, rather than the core's
  /// exact coverage. On macOS, Impeller's 4x MSAA covers an edge pixel by a
  /// quarter, a half or three quarters, so edges differ by up to 100/255 or
  /// so. Shapes and colours mustn't differ, so this compares 4 x 4 pixel
  /// blocks, which average edges out. In its first tests, antialiasing alone
  /// made blocks differ by at most 53/255, and at most 0.2% by over 32/255.
  /// Drawing curves as line segments made them differ by up to 155/255, and
  /// 1.9% by over 32/255.
  bool get passesCanvas =>
      blocksOver32 <= blockCount ~/ 200 && blocksOver64 <= blockCount ~/ 2000;

  /// The side of the blocks that [passesCanvas] compares, in pixels.
  ///
  /// A block's difference is the largest among its channels' mean
  /// differences. [blockLargest] is the largest of them, and [blocksOver32]
  /// and [blocksOver64] count the blocks that differ by over 32/255 and over
  /// 64/255.
  static const blockSize = 4;
  late final int blockCount =
      (_a.width ~/ blockSize) * (_a.height ~/ blockSize);
  late final (int, int, int) _blocks = () {
    const n = blockSize;
    final x = _a.rgba, y = _b.rgba, w = _a.width;
    var largest = 0, over32 = 0, over64 = 0;
    for (var by = 0; by + n <= _a.height; by += n) {
      for (var bx = 0; bx + n <= w; bx += n) {
        var d = 0;
        for (var k = 0; k < 4; k++) {
          var sum = 0;
          for (var row = by; row < by + n; row++) {
            for (
              var i = 4 * (row * w + bx) + k, end = i + 4 * n;
              i < end;
              i += 4
            ) {
              sum += x[i] - y[i];
            }
          }
          final v = sum.abs() ~/ (n * n);
          if (v > d) {
            d = v;
          }
        }
        if (d > largest) {
          largest = d;
        }
        if (d > 32) {
          over32++;
        }
        if (d > 64) {
          over64++;
        }
      }
    }
    return (largest, over32, over64);
  }();
  int get blockLargest => _blocks.$1;
  int get blocksOver32 => _blocks.$2;
  int get blocksOver64 => _blocks.$3;

  @override
  String toString() =>
      '$differing of $pixels pixels differ, $over2 by over 2/255, $over8 by over 8/255, $over64 by over '
      '64/255, largest $largest/255, mean ${mean.toStringAsFixed(3)}/255';

  /// As [toString], with the blocks' differences too.
  String toCanvasString() =>
      '$this; blocks: largest $blockLargest/255, $blocksOver32 of $blockCount over 32/255, $blocksOver64 over 64/255';

  /// Creates an image of where [actual] differs from [golden]: [actual]
  /// dimmed to grey, with the differing pixels in red, brighter for bigger
  /// differences.
  static GoldenImage image(GoldenImage golden, GoldenImage actual) {
    final out = Uint8List(actual.rgba.length), a = actual.rgba, g = golden.rgba;
    for (var i = 0; i < out.length; i += 4) {
      var d = 0;
      for (var k = 0; k < 4; k++) {
        final v = (a[i + k] - g[i + k]).abs();
        if (v > d) {
          d = v;
        }
      }
      final grey = (a[i] * 30 + a[i + 1] * 59 + a[i + 2] * 11) ~/ 300 + 160;
      out
        ..[i] = d == 0 ? grey : 255
        ..[i + 1] = d == 0 ? grey : (160 - d * 4).clamp(0, 255)
        ..[i + 2] = d == 0 ? grey : (160 - d * 4).clamp(0, 255)
        ..[i + 3] = 255;
    }
    return GoldenImage('${actual.name}_diff', actual.width, actual.height, out);
  }
}

/// A golden test case: a frame that [render] draws, and the images it
/// compares with the goldens, one for each run.
class const GoldenCase(
  final String name,
  final Future<List<GoldenImage>> Function(GoldenRenders renders) render, {

  /// Whether the GPU renderer has a golden of it.
  final bool gpu = true,

  /// Whether the canvas renderer is checked against it too.
  ///
  /// It isn't where the canvas renderer can't draw the same: with curves
  /// drawn as line segments, which it never does, and with the gradients
  /// that vector_graphics_compiler doesn't draw as SVG says.
  final bool canvas = true,

  /// Whether the mesh renderer has a golden of it. It doesn't for curves
  /// drawn as line segments, as it draws those frames the same either way.
  final bool mesh = true,

  /// Whether the mesh renderer's render is also checked against the GPU
  /// renderer's golden.
  ///
  /// It isn't where strokes thinner than a pixel make the two differ by more
  /// than the canvas renderer's tolerance. The mesh renderer widens those
  /// strokes to its least width, so that 4x MSAA doesn't break them into
  /// dots, while the GPU renderer draws them as faint lines.
  final bool meshAsGpu = true,
});

/// The golden cases.
///
/// They are the tiger's first frame and its sweep's checkpoints, with and
/// without curves, the sweep of a 4 x 4 grid of tigers, the atlas frame of
/// generated SVGs in 4 runs, the gradients and the plain paths. For the mesh
/// renderer only, they also include the strokes, strokes thinner than a
/// pixel on screen, and glows.
final goldenCases = [
  for (final curves in [false, true])
    GoldenCase(
      'tiger_${curves ? 'curves' : 'fast'}',
      (r) => r.tiger(curves: curves),
      canvas: curves,
      mesh: curves,
      // As the sweep's frames below.
      meshAsGpu: false,
    ),
  for (final curves in [false, true])
    for (final i in sweepCheckpoints)
      GoldenCase(
        'tiger_${curves ? 'curves' : 'fast'}_sweep${'$i'.padLeft(3, '0')}',
        (r) => r.tiger(curves: curves, sweep: i),
        canvas: curves,
        mesh: curves,
        // The tiger's outlines are about 0.14 of a pixel wide at its fit, and
        // 1/4 at 1.5 times. Frames 90 and 150 show enough of them, widened to
        // the least width, to differ by more than the tolerance.
        meshAsGpu: i != 90 && i != 150,
      ),
  for (final i in sweepCheckpoints)
    GoldenCase(
      'tiger4x4_curves_sweep${'$i'.padLeft(3, '0')}',
      (r) => r.tiger(curves: true, grid: 4, sweep: i),
      // As above, and the grid draws the outlines 4 times thinner.
      meshAsGpu: i == 59,
    ),
  GoldenCase('atlas', (r) async => (await r.atlas()).runs),
  GoldenCase('gradients', (r) => r.gradients(skewed: false)),
  GoldenCase(
    'gradients_skewed',
    (r) => r.gradients(skewed: true),
    canvas: false,
  ),
  GoldenCase('strokes', (r) => r.strokes(), gpu: false, canvas: false),
  GoldenCase('thin_strokes', (r) => r.thinStrokes(), gpu: false, canvas: false),
  GoldenCase('glow', (r) => r.glow(), gpu: false, canvas: false),
  GoldenCase('paths', (r) => r.paths()),
];

/// A frame's runs, each as drawn into the viewport, and the pixels that its
/// atlas pages have outside the runs' rectangles.
///
/// The core clips each run to its rectangles in the atlas, so those pixels
/// must stay empty.
class FrameRenders(
  final List<GoldenImage> runs,

  /// The pixels outside the runs' rectangles whose alpha is over 1/255.
  final int stray,

  /// The pixels outside the runs' rectangles whose alpha is 1/255.
  ///
  /// The core's clip to a rectangle is also a soft clip of its paths: a ramp
  /// 1 pixel wide, centred on the rectangle's edge. So a pixel just outside
  /// gets a coverage of about 0, which float rounding can make 1/255. The
  /// original renderer draws the same from the same frame.
  final int faint,

  /// The largest alpha outside the runs' rectangles.
  final int strayLargest,

  /// The rectangles of each run's parts in the viewport.
  final List<List<ui.Rect>> rectangles,
);

/// Renders the frames of the golden cases with one renderer, loading their
/// scenes once.
///
/// For the mesh renderer, it flattens each SVG's curves for the largest size
/// that a case draws it at. With a `recordDir`, the GPU renderer also writes
/// there each frame's atlas pages, the core's frames and the lists they were
/// rendered from: the `.rgba`, `_frame.bin`, `_frame.txt` and `.entries`
/// files, the last naming the SVGs written there too. The last comparison
/// with the original renderer read those files.
class GoldenRenders._(
  final RasterizerRenderer renderer,
  final RasterizerScene tigerScene,

  /// The bounds that fit the tiger to the viewport: its scene's, or for the
  /// mesh renderer, its GPU renderer scene's.
  final ui.Rect tigerBounds,
  final List<RasterizerScene> svgs,
  final RasterizerScene gradientsScene,
  final RasterizerScene gradientsSkewedScene,
  final RasterizerScene strokesScene,
  final RasterizerScene thinStrokesScene,

  /// The scenes of [_glowScenes] for the mesh renderer, or none for the
  /// others.
  final List<RasterizerScene> glowScenes,

  /// The scenes of [goldenPaths] and [goldenSmallPaths].
  final RasterizerScene pathsScene,
  final RasterizerScene smallPathsScene,
  final String? recordDir,
) {
  /// Loads the scenes for [backend]'s renderer, the tiger from [tigerSvg].
  ///
  /// It ignores [recordDir] for other renderers than the GPU renderer.
  static Future<GoldenRenders> load(
    Uint8List tigerSvg, {
    RasterizerBackend backend = RasterizerBackend.gpu,
    String? recordDir,
  }) async {
    if (backend != RasterizerBackend.gpu) {
      recordDir = null;
    }
    final svgs = generatedSvgs(50);
    if (recordDir != null) {
      Directory(recordDir).createSync(recursive: true);
      File('$recordDir/tiger.svg').writeAsBytesSync(tigerSvg);
      for (var i = 0; i < svgs.length; i++) {
        File('$recordDir/svg_$i.svg').writeAsStringSync(svgs[i]);
      }
      File('$recordDir/gradients.svg').writeAsStringSync(gradientsSvg);
      File('$recordDir/gradients_skewed.svg')
          .writeAsStringSync(gradientsSkewedSvg);
    }
    RasterizerScene scene(Uint8List svg, double maxSize) =>
        RasterizerScene.fromSvg(svg, backend: backend, maxSize: maxSize);
    // Fit the mesh renderer's tiger by its GPU renderer scene's bounds, the
    // core's, so that both renderers draw the same frames. Those bounds are
    // looser than the mesh's triangles'. The sweep then zooms in up to 20
    // times. The atlas frame draws the generated SVGs' view boxes at up to
    // 1.6 / 12 of the viewport's height.
    final gpuTiger = backend == RasterizerBackend.mesh
        ? RasterizerScene.fromSvg(tigerSvg, backend: RasterizerBackend.gpu)
        : null;
    final tigerBounds = gpuTiger?.bounds, tigerViewBox = gpuTiger?.viewBox;
    gpuTiger?.dispose();
    final tigerSize = tigerBounds == null || tigerViewBox == null
        ? 0.0
        : 20 *
              math.min(
                goldenWidth / tigerBounds.width,
                goldenHeight / tigerBounds.height,
              ) *
              tigerViewBox.longestSide;
    const svgSize = 1.6 * goldenHeight / 12, ownSize = goldenWidth + 0.0;
    final tigerScene = scene(tigerSvg, tigerSize);
    return GoldenRenders._(
      await RasterizerRenderer.create(backend: backend),
      tigerScene,
      tigerBounds ?? tigerScene.bounds,
      [for (final s in svgs) scene(utf8.encode(s), svgSize)],
      scene(utf8.encode(gradientsSvg), ownSize),
      scene(utf8.encode(gradientsSkewedSvg), ownSize),
      scene(utf8.encode(strokesSvg), ownSize),
      scene(utf8.encode(thinStrokesSvg), ownSize),
      backend == RasterizerBackend.mesh ? _glowScenes() : const [],
      RasterizerScene.fromPaths(
        goldenPaths(),
        backend: backend,
        maxSize: ownSize,
      ),
      RasterizerScene.fromPaths(
        goldenSmallPaths(),
        backend: backend,
        maxSize: 3 * smallPathsScale,
      ),
      recordDir,
    );
  }

  /// The pixels a unit that [paths] draws [goldenSmallPaths] at.
  static const smallPathsScale = 40.0;

  /// The pixels a unit that [glow] draws the ship and the zapper at.
  static const _glowUnit = 85.0;

  /// Creates the scenes of the mesh renderer's glow golden, shapes from the
  /// Tube Shooter example.
  ///
  /// The ship is a closed stroke, and the zapper an open one. Both are a unit
  /// wide, with a stroke of 4 pixels and a glow of 12 at [_glowUnit] pixels a
  /// unit. The tube has 12 lanes, drawn as filled quads 3 pixels wide, with a
  /// glow of 12 pixels.
  static List<RasterizerScene> _glowScenes() {
    const unit = _glowUnit;
    RasterizerScene shape(
      List<ui.Offset> points,
      int color, {
      required bool closed,
    }) => RasterizerScene.fromPaths(
      [
        (
          ui.Path()..addPolygon(points, closed),
          ui.Paint()
            ..color = ui.Color(color)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 4 / unit,
        ),
      ],
      backend: RasterizerBackend.mesh,
      // Flattens curves to within 0.003 of their unit.
      maxSize: 0.25 / 0.003,
      glow: const RasterizerGlow(12 / unit),
    );

    const lanes = 12, halfWidth = 1.5;
    const centre = ui.Offset(512, 590);
    ui.Offset at(int lane, double radius) =>
        centre + ui.Offset.fromDirection(2 * math.pi * lane / lanes, radius);
    final tube = ui.Path();
    void line(ui.Offset a, ui.Offset b) {
      final d = (b - a) / (b - a).distance;
      final o = ui.Offset(-d.dy, d.dx) * halfWidth;
      tube.addPolygon([a + o, b + o, b - o, a - o], false);
    }

    for (var i = 0; i < lanes; i++) {
      line(at(i, 160), at(i, 60));
      line(at(i, 160), at(i + 1, 160));
      line(at(i, 60), at(i + 1, 60));
    }
    return [
      shape(
        const [
          ui.Offset(-0.5, 0),
          ui.Offset(-0.22, -0.2),
          ui.Offset(0, -0.06),
          ui.Offset(0.22, -0.2),
          ui.Offset(0.5, 0),
          ui.Offset(0, 0.28),
        ],
        0xFF38BDF8,
        closed: true,
      ),
      shape(
        const [
          ui.Offset(-0.5, 0),
          ui.Offset(-0.3, -0.16),
          ui.Offset(-0.1, 0.16),
          ui.Offset(0.1, -0.16),
          ui.Offset(0.3, 0.16),
          ui.Offset(0.5, 0),
        ],
        0xFF34D399,
        closed: false,
      ),
      RasterizerScene.fromPaths(
        [(tube, ui.Paint()..color = const ui.Color(0xFFA78BFA))],
        backend: RasterizerBackend.mesh,
        maxSize: tube.getBounds().longestSide,
        glow: const RasterizerGlow.widths(2),
      ),
    ];
  }

  /// The motion of the atlas frame's entries.
  final AtlasMotion motion = AtlasMotion(entries: 200);

  static const _size = ui.Size(goldenWidth + 0.0, goldenHeight + 0.0);

  /// Renders the tiger [grid] x [grid] times, fitted to the viewport, as one
  /// run, at the sweep's frame [sweep] if given.
  Future<List<GoldenImage>> tiger({
    required bool curves,
    int grid = 1,
    int? sweep,
  }) async {
    final view = sweep == null
        ? const Affine.identity()
        : sweepView(sweep, _size);
    final frame = renderer.beginFrame(
      goldenWidth,
      goldenHeight,
      curves: curves,
    );
    final run = frame.addRun();
    for (final m in gridTransforms(tigerBounds, grid, _size, view, 1)) {
      run.add(tigerScene, m.a, m.b, m.c, m.d, m.tx, m.ty);
    }
    final name =
        'tiger${grid > 1 ? '${grid}x$grid' : ''}_${curves ? 'curves' : 'fast'}'
        '${sweep == null ? '' : '_sweep${'$sweep'.padLeft(3, '0')}'}';
    return (await _render(name, frame, curves, (_) => 'tiger.svg')).runs;
  }

  /// Renders the atlas frame: 200 entries of the generated SVGs at time 7.3,
  /// in 4 runs.
  ///
  /// Each run covers much of the viewport, and many entries cross its edges.
  /// With [alone], it renders only that run's entries, as a frame of one run.
  Future<FrameRenders> atlas({int? alone}) async {
    const runs = 4, t = 7.3;
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    final added = [
      for (var k = 0; k < (alone == null ? runs : 1); k++) frame.addRun(),
    ];
    final entries = <int>[];
    for (var i = 0; i < motion.entries; i++) {
      final k = i * runs ~/ motion.entries;
      if (alone != null && k != alone) {
        continue;
      }
      final (a, b, c, d, tx, ty) = motion.transform(i, t, _size);
      added[alone == null ? k : 0].add(svgs[motion.svg(i)], a, b, c, d, tx, ty);
      entries.add(i);
    }
    return _render(
      alone == null ? 'atlas' : 'atlas_alone$alone',
      frame,
      true,
      (e) => 'svg_${motion.svg(entries[e])}.svg',
    );
  }

  /// Renders [gradientsSvg], or [gradientsSkewedSvg] if [skewed], at its own
  /// size, as one run.
  Future<List<GoldenImage>> gradients({required bool skewed}) async {
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    frame.addRun().add(
      skewed ? gradientsSkewedScene : gradientsScene,
      1,
      0,
      0,
      1,
      0,
      0,
    );
    final name = skewed ? 'gradients_skewed' : 'gradients';
    return (await _render(name, frame, true, (_) => '$name.svg')).runs;
  }

  /// Renders [strokesSvg] at its own size, as one run.
  Future<List<GoldenImage>> strokes() async {
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    frame.addRun().add(strokesScene, 1, 0, 0, 1, 0, 0);
    return (await _render('strokes', frame, true, (_) => 'strokes.svg')).runs;
  }

  /// Renders [thinStrokesSvg] four times, as one run: at half its size, where
  /// its strokes are 0.6 pixels wide, at a quarter, turned and shrunk, and
  /// under a perspective.
  ///
  /// The strokes must stay whole, widened to the least width where they'd be
  /// thinner, never broken into dots.
  Future<List<GoldenImage>> thinStrokes() async {
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    frame.addRun()
      ..add(thinStrokesScene, 0.5, 0, 0, 0.5, 0, 0)
      ..add(thinStrokesScene, 0.25, 0, 0, 0.25, 700, 10)
      ..add(thinStrokesScene, 0.3, 0.12, -0.12, 0.3, 640, 240)
      ..addProjective(thinStrokesScene, 0.5, 0, 0, 0.7, 10, 410, 0, 0.001, 1);
    return (await _render('thin_strokes', frame, true, (_) => 'thin.svg')).runs;
  }

  /// Renders [goldenPaths] at their own size, and [goldenSmallPaths] at
  /// [smallPathsScale] pixels a unit, as one run.
  Future<List<GoldenImage>> paths() async {
    const k = smallPathsScale;
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    frame.addRun()
      ..add(pathsScene, 1, 0, 0, 1, 0, 0)
      ..add(smallPathsScene, k, 0, 0, k, 790, 580);
    return (await _render('paths', frame, true, (_) => 'paths')).runs;
  }

  /// Renders [_glowScenes] as one run, over the tube's lines.
  ///
  /// It draws the ship and the zapper at 4 times their size, where a glow's
  /// arcs show, then at their size, upright and turned.
  Future<List<GoldenImage>> glow() async {
    const unit = _glowUnit, large = 4 * unit;
    final [ship, zapper, tube] = glowScenes;
    final cos = unit * math.cos(math.pi / 6),
        sin = unit * math.sin(math.pi / 6);
    final frame = renderer.beginFrame(goldenWidth, goldenHeight);
    frame.addRun()
      ..add(tube, 1, 0, 0, 1, 0, 0)
      ..add(ship, large, 0, 0, large, 256, 140)
      ..add(zapper, large, 0, 0, large, 768, 140)
      ..add(ship, unit, 0, 0, unit, 90, 330)
      ..add(ship, cos, sin, -sin, cos, 270, 330)
      ..add(zapper, unit, 0, 0, unit, 750, 330)
      ..add(zapper, cos, sin, -sin, cos, 930, 330);
    return (await _render('glow', frame, true, (_) => 'glow')).runs;
  }

  /// Renders [frame] and reads back its runs, with [svgOf] naming each
  /// entry's SVG for the recorded lists.
  Future<FrameRenders> _render(
    String name,
    RasterizerFrame frame,
    bool curves,
    String Function(int entry) svgOf,
  ) =>
      renderAtlasFrame(name, frame, renderer, curves, svgOf, recordDir) ??
      _renderCanvas(name, frame);

  /// Renders a canvas renderer's frame, drawing each run on its own into a
  /// picture of the viewport's size, and reads the pictures back.
  Future<FrameRenders> _renderCanvas(String name, RasterizerFrame frame) async {
    frame.render();
    final runs = <GoldenImage>[];
    final many = frame.runs.length > 1;
    for (final run in frame.runs) {
      final recorder = ui.PictureRecorder();
      run.draw(ui.Canvas(recorder));
      final picture = recorder.endRecording(),
          image = await picture.toImage(goldenWidth, goldenHeight);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      picture.dispose();
      image.dispose();
      runs.add(
        GoldenImage(
          many ? '${name}_run${run.index}' : name,
          goldenWidth,
          goldenHeight,
          Uint8List.sublistView(data),
        ),
      );
    }
    return FrameRenders(runs, 0, 0, 0, [
      for (final run in frame.runs)
        [for (final part in run.parts) part.destination],
    ]);
  }

  void dispose() {
    renderer.dispose();
    tigerScene.dispose();
    gradientsScene.dispose();
    gradientsSkewedScene.dispose();
    strokesScene.dispose();
    thinStrokesScene.dispose();
    for (final s in glowScenes) {
      s.dispose();
    }
    pathsScene.dispose();
    smallPathsScene.dispose();
    for (final s in svgs) {
      s.dispose();
    }
  }
}
