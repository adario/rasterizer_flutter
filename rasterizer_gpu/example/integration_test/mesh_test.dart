// Tests the mesh renderer in the app:
//   flutter test integration_test/mesh_test.dart -d <device>
//
// Each test imports SVG scenes into meshes, renders them through the
// renderer's API, and reads the result back through a canvas. The tests check
// colors and paint order, instances with their opacities and color
// transforms, unblended opaque draws, gradients with and without color
// transforms, fill rules, strokes, 32-bit indices, multisampled and aliased
// edges, runs' targets, and frames in flight. On OpenGL ES, they run once the
// mesh renderer's self-test has passed. projective_test.dart checks
// perspective.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The mesh importer and renderer are internal. The tests use them to make
// hairline meshes and to read whether edges are multisampled.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/meshes.dart' show MeshRenderer, MeshScene;

/// The viewport's width and height, in pixels.
const size = 64;

/// An SVG document of [body], with a square viewBox [side] wide.
String svg(String body, {int side = size}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $side $side">'
    '$body</svg>';

/// A mesh scene of [svg], disposed after the test.
RasterizerScene scene(String svg) {
  final scene = RasterizerScene.fromSvg(
    utf8.encode(svg),
    backend: RasterizerBackend.mesh,
    maxSize: size.toDouble(),
  );
  addTearDown(scene.dispose);
  return scene;
}

/// What [draw] draws, read back as premultiplied RGBA.
Future<Pixels> readBack(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording(),
      image = await picture.toImage(size, size);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return Pixels(Uint8List.sublistView(data!));
}

/// The pixels of a [size] by [size] image, as premultiplied RGBA bytes.
class Pixels(final Uint8List bytes) {
  /// The RGBA of the pixel at [x], [y].
  List<int> at(int x, int y) {
    final i = 4 * (y * size + x);
    return bytes.sublist(i, i + 4);
  }

  /// Fails with [what] unless each channel of the pixel at [x], [y] is
  /// within [within] of [rgba].
  void expectAt(int x, int y, List<int> rgba, String what, {int within = 2}) {
    final p = at(x, y);
    for (var i = 0; i < 4; i++) {
      if ((p[i] - rgba[i]).abs() > within) {
        fail('$what: pixel ($x, $y) is $p, not $rgba');
      }
    }
  }
}

/// A scene drawn at [x], [y], with its opacity and color transform.
typedef Entry = ({
  RasterizerScene scene,
  double x,
  double y,
  double opacity,
  RasterizerColorTransform? color,
});

/// An [Entry] of [scene], by default at the origin, opaque and with no color
/// transform.
Entry entry(
  RasterizerScene scene, {
  double x = 0,
  double y = 0,
  double opacity = 1,
  RasterizerColorTransform? color,
}) => (scene: scene, x: x, y: y, opacity: opacity, color: color);

const red = [255, 0, 0, 255], green = [0, 255, 0, 255], clear = [0, 0, 0, 0];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // On OpenGL ES, the mesh renderer is supported once its self-test has
  // passed.
  final mesh = RasterizerGpu.of(RasterizerBackend.mesh);
  var supported = false;
  late final MeshRenderer renderer;

  /// Renders [entries] as one run, in a frame of their own, and reads it back.
  ///
  /// It renders with [by], or else with [renderer].
  Future<Pixels> render(List<Entry> entries, {MeshRenderer? by}) async {
    final frame = (by ?? renderer).beginFrame(size, size);
    final run = frame.addRun();
    for (final (:scene, :x, :y, :opacity, :color) in entries) {
      run.add(scene, 1, 0, 0, 1, x, y, opacity: opacity, colorTransform: color);
    }
    frame.render();
    return readBack(run.draw);
  }

  setUpAll(() async {
    runApp(const SizedBox());
    await binding.waitUntilFirstFrameRasterized;
    RasterizerGpu.allowOpenGles = true;
    await mesh.initialize();
    supported = mesh.support == RasterizerSupport.supported;
    if (!supported) {
      return;
    }
    renderer = await RasterizerRenderer.create(
      backend: RasterizerBackend.mesh,
    ) as MeshRenderer;
    // ignore: avoid_print
    print(
      'mesh renderer: ${mesh.support.name}, '
      '${renderer.multisampled ? '4×' : 'not'} multisampled',
    );
  });

  tearDownAll(() {
    if (supported) {
      renderer.dispose();
    }
  });

  /// A [test] that's skipped where the mesh renderer isn't supported.
  void meshTest(String description, Future<void> Function() body) =>
      test(description, () async {
        if (!supported) {
          markTestSkipped('support ${mesh.support.name}');
          return;
        }
        await body();
      });

  meshTest('a mesh scene needs a maximum size', () async {
    expect(
      () => RasterizerScene.fromSvg(
        utf8.encode(svg('')),
        backend: RasterizerBackend.mesh,
      ),
      throwsArgumentError,
    );
  });

  meshTest('paths paint in order, the right way up', () async {
    final squares = scene(
      svg(
        '<rect x="8" y="8" width="32" height="32" fill="red"/>'
        '<rect x="24" y="24" width="32" height="32" fill="#0000ff" '
        'fill-opacity="0.5"/>'
        '<rect x="48" y="2" width="14" height="8" fill="#00ff00"/>',
      ),
    );
    expect(squares.backend, RasterizerBackend.mesh);
    expect(squares.pathCount, 3);
    expect(squares.viewBox, const ui.Rect.fromLTWH(0, 0, 64, 64));
    final pixels = await render([entry(squares)]);
    pixels
      ..expectAt(4, 4, clear, 'outside')
      ..expectAt(16, 16, red, 'red')
      ..expectAt(32, 32, [128, 0, 128, 255], 'blue over red')
      ..expectAt(48, 48, [0, 0, 128, 128], 'blue')
      ..expectAt(55, 6, green, 'top right')
      ..expectAt(6, 55, clear, 'bottom left');
  });

  meshTest('instances paint in order, each with its paint', () async {
    final square = scene(
      svg('<rect width="24" height="24" fill="red"/>', side: 24),
    );
    final blue = RasterizerColorTransform.mode(
      const ui.Color(0xFF0000FF),
      ui.BlendMode.srcATop,
    );
    final greenTint = RasterizerColorTransform.mode(
      const ui.Color(0xFF00FF00),
      ui.BlendMode.srcATop,
    );
    final pixels = await render([
      entry(square, x: 8, y: 8),
      entry(square, x: 20, y: 20, opacity: 0.5, color: blue),
      entry(square, x: 32, y: 32, color: greenTint),
    ]);
    pixels
      ..expectAt(12, 12, red, 'instance 0')
      ..expectAt(26, 26, [128, 0, 128, 255], '1 over 0')
      ..expectAt(38, 38, green, '2 over 1')
      ..expectAt(50, 50, green, 'instance 2')
      ..expectAt(4, 4, clear, 'outside');
  });

  meshTest('opacities and color matrices', () async {
    final square = scene(svg('<rect width="64" height="64" fill="red"/>'));
    (await render([entry(square, opacity: 0.5)]))
        .expectAt(32, 32, [128, 0, 0, 128], 'faded');
    final swap = RasterizerColorTransform.matrix([
      0, 1, 0, 0, 0, //
      1, 0, 0, 0, 0, //
      0, 0, 1, 0, 255, //
      0, 0, 0, 1, 0, //
    ]);
    (await render([entry(square, color: swap)]))
        .expectAt(32, 32, [0, 255, 255, 255], 'red & green swapped, blue on');
    (await render([entry(square, opacity: 0.5, color: swap)]))
        .expectAt(32, 32, [0, 128, 128, 128], 'faded, then swapped');
  });

  meshTest("opaque meshes' opaque instances cover what's below, unblended, "
      'and the others blend', () async {
    String square(String paint) => svg(
      '<defs><linearGradient id="g"><stop offset="0" stop-color="#00ff00"/>'
      '<stop offset="1" stop-color="#00ff00"/></linearGradient></defs>'
      '<rect width="24" height="24" $paint/>',
      side: 24,
    );
    final redSquare = scene(square('fill="red"')),
        halfBlue = scene(square('fill="#0000ff" fill-opacity="0.5"')),
        greenGradient = scene(square('fill="url(#g)"'));
    final erase = RasterizerColorTransform.mode(
      const ui.Color(0xFF000000),
      ui.BlendMode.clear,
    );
    // The red square's first 4 entries make 3 draws: an unblended one, a
    // blended one for the entry that erases it, then an unblended one again.
    final pixels = await render([
      entry(redSquare, x: 4, y: 4),
      entry(redSquare, x: 4, y: 4, color: erase),
      entry(redSquare, x: 36, y: 4),
      entry(redSquare, x: 4, y: 36),
      entry(halfBlue, x: 36, y: 4),
      entry(greenGradient, x: 4, y: 36),
      entry(redSquare, x: 16, y: 48, opacity: 0.5),
    ]);
    pixels
      ..expectAt(16, 16, red, 'erased, so unchanged')
      ..expectAt(48, 16, [128, 0, 128, 255], 'translucent mesh over red')
      ..expectAt(8, 40, green, 'opaque gradient over red')
      ..expectAt(24, 56, [128, 128, 0, 255], 'faded over the gradient')
      ..expectAt(36, 56, [128, 0, 0, 128], 'faded over nothing')
      ..expectAt(2, 2, clear, 'outside');
  });

  meshTest('linear and radial gradients', () async {
    final gradients = scene(
      svg(
        '<defs>'
        '<linearGradient id="l"><stop offset="0" stop-color="#000"/>'
        '<stop offset="1" stop-color="#fff"/></linearGradient>'
        '<radialGradient id="r"><stop offset="0" stop-color="#fff"/>'
        '<stop offset="1" stop-color="#000"/></radialGradient>'
        '</defs>'
        '<rect width="64" height="32" fill="url(#l)"/>'
        '<rect y="32" width="64" height="32" fill="url(#r)"/>',
      ),
    );
    final pixels = await render([entry(gradients)]);
    // At pixel centers, where the linear gradient's t is (x + 0.5) / 64.
    for (final x in [0, 16, 40, 63]) {
      final v = ((x + 0.5) / 64 * 255).round();
      pixels.expectAt(x, 8, [v, v, v, 255], 'linear', within: 3);
    }
    // The radial gradient is an ellipse from the box's center, 32 by 16
    // pixels, padded with its last color beyond.
    for (final (x, y) in [(32, 48), (48, 48), (32, 56), (40, 52), (1, 33)]) {
      final dx = (x + 0.5 - 32) / 32, dy = (y + 0.5 - 48) / 16;
      final t = math.min(1, math.sqrt(dx * dx + dy * dy));
      final v = ((1 - t) * 255).round();
      pixels.expectAt(x, y, [v, v, v, 255], 'radial', within: 3);
    }
  });

  meshTest('gradients interpolate unpremultiplied, then premultiply', () async {
    final fade = scene(
      svg(
        '<defs><linearGradient id="g">'
        '<stop offset="0" stop-color="red"/>'
        '<stop offset="1" stop-color="#0000ff" stop-opacity="0"/>'
        '</linearGradient></defs>'
        '<rect width="64" height="64" fill="url(#g)"/>',
      ),
    );
    // Halfway, the color is (0.5, 0, 0.5) at alpha 0.5. Interpolating the
    // premultiplied stops would give red at alpha 0.5 instead.
    final pixels = await render([entry(fade)]);
    for (final x in [8, 32, 56]) {
      final t = (x + 0.5) / 64, a = 1 - t;
      pixels.expectAt(
        x,
        32,
        [
          ((1 - t) * a * 255).round(),
          0,
          (t * a * 255).round(),
          (a * 255).round(),
        ],
        'faded',
        within: 3,
      );
    }
  });

  meshTest("gradients' instances with and without color transforms, in one "
      'run', () async {
    // Instances with a color transform draw with the ra_mesh_transformed.frag
    // shader, one draw for each transform scaled by its opacity. The others
    // draw with ra_mesh.frag.
    final ramp = scene(
      svg(
        '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/>'
        '<stop offset="1" stop-color="#00ff00"/></linearGradient></defs>'
        '<rect width="24" height="24" fill="url(#g)"/>',
        side: 24,
      ),
    );
    final swap = RasterizerColorTransform.matrix([
      0, 1, 0, 0, 0, //
      1, 0, 0, 0, 0, //
      0, 0, 1, 0, 255, //
      0, 0, 0, 1, 0, //
    ]);
    final pixels = await render([
      entry(ramp, x: 4, y: 4),
      entry(ramp, x: 16, y: 4, color: swap),
      entry(ramp, x: 40, y: 4, opacity: 0.5, color: swap),
      entry(ramp, x: 4, y: 36, opacity: 0.5),
      entry(ramp, x: 36, y: 36),
    ]);
    // The ramp's color x pixels into it, from red to green, faded by
    // opacity, or with red and green swapped and blue on.
    List<int> color(int x, {double opacity = 1, bool swapped = false}) {
      final t = (x + 0.5) / 24;
      final (r, g) = swapped ? (t, 1 - t) : (1 - t, t);
      return [
        for (final v in [r, g, swapped ? 1.0 : 0.0, 1.0])
          (v * opacity * 255).round(),
      ];
    }

    pixels
      ..expectAt(10, 16, color(6), 'without')
      ..expectAt(20, 16, color(4, swapped: true), 'swapped, over it')
      ..expectAt(28, 16, color(12, swapped: true), 'swapped')
      ..expectAt(
        52,
        16,
        color(12, opacity: 0.5, swapped: true),
        'swapped and faded, next to it',
      )
      ..expectAt(16, 48, color(12, opacity: 0.5), 'faded')
      ..expectAt(48, 48, color(12), 'without again')
      ..expectAt(2, 2, clear, 'outside');
  });

  meshTest('fill rules, holes and strokes', () async {
    const outer = 'M8 8h48v48h-48z', inner = 'M24 24h16v16h-16z';
    final evenOdd = scene(
      svg('<path d="$outer $inner" fill-rule="evenodd" fill="red"/>'),
    );
    final nonZero = scene(svg('<path d="$outer $inner" fill="red"/>'));
    final reversed = scene(
      svg('<path d="$outer M24 24v16h16v-16z" fill="red"/>'),
    );
    final stroke = scene(
      svg('<path d="M8 32H56" stroke="#00ff00" stroke-width="8"/>'),
    );
    (await render([entry(evenOdd)]))
      ..expectAt(12, 12, red, 'even-odd, outside the hole')
      ..expectAt(32, 32, clear, 'even-odd, the hole');
    (await render([entry(nonZero)]))
        .expectAt(32, 32, red, 'nonzero, wound twice');
    (await render([entry(reversed)]))
        .expectAt(32, 32, clear, 'nonzero, wound back');
    (await render([entry(stroke)]))
      ..expectAt(32, 30, green, 'stroke')
      ..expectAt(32, 33, green, 'stroke')
      ..expectAt(32, 40, clear, 'beyond the stroke')
      ..expectAt(4, 32, clear, 'beyond its butt cap');
  });

  meshTest('32 bit indices reach past 65535', () async {
    // 17,000 squares off the viewBox, of 4 vertices each, then a green one.
    // Indices cut to 16 bits would pick other squares' vertices for it.
    final body = StringBuffer();
    for (var i = 0; i < 17000; i++) {
      body.write('<rect x="-90" y="-90" width="1" height="1" fill="red"/>');
    }
    body.write('<rect x="16" y="16" width="32" height="32" fill="#00ff00"/>');
    final many = scene(svg('$body'));
    (await render([entry(many)])).expectAt(32, 32, green, 'the last square');
  });

  meshTest('edges are multisampled where offscreen MSAA is, unless 1 sample '
      'is asked for', () async {
    // Tilted, so its edges cross pixels at every offset.
    final triangle = scene(svg('<path d="M4 4L60 9L7 60z" fill="#00ff00"/>'));
    final aliased = await RasterizerRenderer.create(
      backend: RasterizerBackend.mesh,
      meshSamples: 1,
    ) as MeshRenderer;
    addTearDown(aliased.dispose);
    expect(aliased.samples, 1);
    expect(aliased.multisampled, isFalse);
    for (final by in [renderer, aliased]) {
      final pixels = await render([entry(triangle)], by: by);
      pixels
        ..expectAt(10, 10, green, 'inside')
        ..expectAt(50, 50, clear, 'outside');
      var partial = 0;
      for (var i = 1; i < pixels.bytes.length; i += 4) {
        final g = pixels.bytes[i];
        if (g > 8 && g < 247) {
          partial++;
        }
      }
      // ignore: avoid_print
      print(
        'mesh renderer, ${by.samples} samples: $partial partial edge '
        'pixels',
      );
      if (by.multisampled) {
        expect(partial, greaterThan(40), reason: 'multisampled edges');
      } else {
        expect(partial, 0, reason: 'aliased edges');
      }
    }
  });

  meshTest("a run's target is its entries' bounds, clipped", () async {
    final square = scene(
      svg('<rect width="24" height="24" fill="red"/>', side: 24),
    );
    final empty = scene(svg(''));
    final frame = renderer.beginFrame(size, size);
    final inside = frame.addRun()..add(square, 1, 0, 0, 1, 10.3, 20.7);
    final clipped = frame.addRun()..add(square, 1, 0, 0, 1, 50, -10);
    final outside = frame.addRun()..add(square, 1, 0, 0, 1, 70, 0);
    final none = frame.addRun()..add(empty, 1, 0, 0, 1, 0, 0);
    inside.place();
    // The bounds grow by a margin of 1 pixel, then round out to whole pixels.
    expect(inside.parts, hasLength(1));
    expect(
      inside.parts.single.destination,
      const ui.Rect.fromLTRB(9, 19, 36, 46),
    );
    expect(inside.parts.single.source, const ui.Rect.fromLTWH(0, 0, 27, 27));
    frame.render();
    expect(
      clipped.parts.single.destination,
      const ui.Rect.fromLTRB(49, 0, 64, 15),
    );
    expect(outside.isEmpty, isTrue);
    expect(none.isEmpty, isTrue);
    expect(
      inside.parts.single.image,
      isNot(same(clipped.parts.single.image)),
      reason: 'a target each',
    );
    expect(frame.pageSizes, hasLength(2));
    final pixels = await readBack((canvas) {
      inside.draw(canvas);
      clipped.draw(canvas);
    });
    pixels
      ..expectAt(11, 21, red, 'inside')
      ..expectAt(33, 43, red, 'inside')
      ..expectAt(9, 19, clear, 'its margin')
      ..expectAt(55, 5, red, 'clipped')
      ..expectAt(55, 20, clear, 'below the clipped one');
  });

  meshTest('targets are kept as entries move, and frames stay', () async {
    final square = scene(
      svg('<rect width="24" height="24" fill="red"/>', side: 24),
    );
    RasterizerRun frameAt(double x) {
      final frame = renderer.beginFrame(size, size);
      final run = frame.addRun()..add(square, 1, 0, 0, 1, x, 4);
      frame.render();
      return run;
    }

    for (var i = 0; i < renderer.slots; i++) {
      frameAt(i.toDouble());
    }
    final resizes = renderer.atlasResizes;
    for (var i = 0; i < 20; i++) {
      frameAt(i * 0.5);
    }
    expect(renderer.atlasResizes, resizes, reason: 'no target reallocated');

    // A frame's images stay valid until `slots` frames later.
    final first = frameAt(2), part = first.parts.single;
    for (var i = 1; i < renderer.slots; i++) {
      frameAt(30);
    }
    (await readBack(
        (canvas) => canvas.drawImageRect(
          part.image,
          part.source,
          part.destination,
          ui.Paint(),
        ),
      ))
      ..expectAt(4, 10, red, 'the first frame')
      ..expectAt(28, 10, clear, 'not a later one');

    expect(renderer.atlasBytes, greaterThan(0));
    renderer.trimAtlas();
    expect(renderer.atlasBytes, 0, reason: 'targets released');
    final run = frameAt(8);
    (await readBack(run.draw)).expectAt(16, 16, red, 'after the trim');
  });

  /// Renders what [add] adds to a run, in a frame of its own, and reads it
  /// back.
  Future<Pixels> renderBy(
    void Function(RasterizerRun run) add, {
    MeshRenderer? by,
  }) async {
    final frame = (by ?? renderer).beginFrame(size, size), run = frame.addRun();
    add(run);
    frame.render();
    return readBack(run.draw);
  }

  /// The coverage of column [x], in pixels: the sum of its alphas, over 255.
  double column(Pixels p, int x) {
    var sum = 0;
    for (var y = 0; y < size; y++) {
      sum += p.at(x, y)[3];
    }
    return sum / 255;
  }

  /// Expects each column from [from] to [to] to hold [least] to [most] pixels
  /// of coverage, so that no part of the line is missing or too wide.
  void expectWhole(
    Pixels p,
    int from,
    int to, {
    required double least,
    required double most,
  }) {
    for (var x = from; x <= to; x++) {
      expect(column(p, x), inInclusiveRange(least, most), reason: 'column $x');
    }
  }

  /// A mesh scene that draws [path] as a red hairline, a stroke one device
  /// pixel wide at any scale, disposed after the test.
  RasterizerScene hairline(ui.Path path) {
    final scene = MeshScene(
      ra.Mesh.fromPaths(
        [
          ra.PathContours([path], tolerance: 0.25),
        ],
        const [ra.PathDraw(path: 0, color: 0xffff0000, hairline: true)],
        const ra.Bounds(0, 0, 64, 64),
        tolerance: 0.25,
      ),
    );
    addTearDown(scene.dispose);
    return scene;
  }

  // The least width that the renderer draws a stroke at, in pixels. Thinner
  // strokes widen to it.
  double leastWidth() => renderer.multisampled ? 0.56 : 1.0;

  // A line 0.2 pixels wide on screen, at slope 1/2, so 0.22 pixels tall per
  // column. Widened to the least width, it's 1.12 times that width per
  // column.
  final thinLine = svg(
    '<path d="M20 100 L620 400" stroke="#ff0000" stroke-width="2" '
    'fill="none"/>',
    side: 640,
  );

  meshTest('a stroke thinned by its transform stays whole', () async {
    final line = scene(thinLine);
    expectWhole(
      await renderBy((run) => run.add(line, 0.1, 0, 0, 0.1, 0, 0)),
      4,
      60,
      least: 0.4 * leastWidth(),
      most: 2.2 * leastWidth(),
    );
  });

  meshTest('a stroke at the least width is whole at any offset', () async {
    // At slope 1/2, the rows of 4x MSAA's samples are farthest apart.
    final line = scene(thinLine);
    for (var k = 0; k < 16; k++) {
      expectWhole(
        await renderBy((run) => run.add(line, 0.1, 0, 0, 0.1, 0, k / 16)),
        4,
        60,
        least: 0.4 * leastWidth(),
        most: 2.2 * leastWidth(),
      );
    }
  });

  meshTest('aliased, its least width is a pixel', () async {
    final aliased = await RasterizerRenderer.create(
      backend: RasterizerBackend.mesh,
      meshSamples: 1,
    ) as MeshRenderer;
    addTearDown(aliased.dispose);
    final line = scene(thinLine);
    expectWhole(
      await renderBy((run) => run.add(line, 0.1, 0, 0, 0.1, 0, 0), by: aliased),
      4,
      60,
      least: 1,
      most: 2,
    );
  });

  meshTest('so does one under a perspective', () async {
    final line = scene(thinLine);
    expectWhole(
      await renderBy(
        (run) => run.addProjective(line, 0.1, 0, 0, 0.1, 0, 0, 0.002, 0, 1),
      ),
      4,
      25,
      least: 0.4 * leastWidth(),
      most: 2.2 * leastWidth(),
    );
  });

  meshTest(
    'a thin opaque stroke over itself: strips whole, a fade its union',
    () async {
      // Each diagonal is 0.2 pixels wide on screen, at slope 1, so 0.28 pixels
      // tall per column. Widened to the least width, it's 1.41 times that
      // width per column.
      final cross = scene(
        svg(
          '<path d="M20 20 L620 620 M620 20 L20 620" stroke="#ff0000" '
          'stroke-width="2" fill="none"/>',
          side: 640,
        ),
      );
      expectWhole(
        await renderBy((run) => run.add(cross, 0.1, 0, 0, 0.1, 0, 0)),
        4,
        60,
        least: 0.4 * leastWidth(),
        most: 4 * leastWidth(),
      );
      expectWhole(
        await renderBy(
          (run) => run.add(cross, 0.1, 0, 0, 0.1, 0, 0, opacity: 0.5),
        ),
        4,
        60,
        least: 0,
        most: 1.24 * leastWidth(),
      );
    },
  );

  meshTest('a fading stroke that overlaps itself blends once', () async {
    final cross = scene(
      svg(
        '<path d="M8 8 L56 56 M56 8 L8 56" stroke="#ff0000" stroke-width="8" '
        'fill="none"/>',
      ),
    );
    (await renderBy((run) => run.add(cross, 1, 0, 0, 1, 0, 0)))
        .expectAt(32, 32, red, 'opaque');
    (await renderBy((run) => run.add(cross, 1, 0, 0, 1, 0, 0, opacity: 0.5)))
        .expectAt(32, 32, [128, 0, 0, 128], 'faded');
  });

  meshTest('strokes wider than the least width keep their width', () async {
    const line = '<path d="M0 32 L64 32" stroke-width="8" fill="none" stroke=';
    for (final stroke in [
      scene(svg('$line"#ff0000"/>')),
      scene(
        svg(
          '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" '
          'y1="0" x2="64" y2="0"><stop offset="0" stop-color="#ff0000"/>'
          '<stop offset="1" stop-color="#ff0000"/></linearGradient></defs>'
          '$line"url(#g)"/>',
        ),
      ),
    ]) {
      (await renderBy((run) => run.add(stroke, 1, 0, 0, 1, 0, 0)))
        ..expectAt(32, 27, clear, 'above')
        ..expectAt(32, 28, red, 'its top')
        ..expectAt(32, 35, red, 'its bottom')
        ..expectAt(32, 36, clear, 'below');
    }
  });

  meshTest('hairlines are a device pixel wide at any scale', () async {
    // A straight line, whose bounds are empty.
    final straight = hairline(
      ui.Path()
        ..moveTo(4, 20)
        ..lineTo(60, 20),
    );
    for (final s in [1.0, 0.5]) {
      expectWhole(
        await renderBy((run) => run.add(straight, s, 0, 0, s, 0, 0)),
        (4 * s).ceil() + 1,
        (60 * s).floor() - 1,
        least: 0.88 * leastWidth(),
        most: 1.12 * leastWidth(),
      );
    }

    // A line with a corner on its way.
    final bent = hairline(
      ui.Path()
        ..moveTo(4, 8)
        ..lineTo(32, 22)
        ..lineTo(60, 8),
    );
    expectWhole(
      await renderBy((run) => run.add(bent, 1, 0, 0, 1, 0, 0)),
      6,
      58,
      least: 0.4 * leastWidth(),
      most: 2.6 * leastWidth(),
    );
  });
}
