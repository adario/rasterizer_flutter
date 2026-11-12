// Checks scenes of plain paths, for each renderer, without a GPU. From this
// package's folder:
//   flutter test test/path_scene_test.dart
//
// It checks which paints the GPU renderers can draw, the scenes' bounds and
// counts, their glow, and the core's path scenes and meshes. A mesh's
// triangles must cover what its paths do. The scenes' pixels are checked by
// the `paths` golden, in example/lib/goldens.dart.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/src/core.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu/src/meshes.dart' show MeshScene;
import 'package:rasterizer_gpu/src/paths/scene_paths.dart';

/// The triangles of [m]'s path [path], as 6 coordinates each.
Iterable<List<double>> triangles(Mesh m, int path) sync* {
  final p = m.paths[path], v = m.vertices, i = m.indices as List<int>;
  final f = m.vertexFloats;
  for (var k = p.indexBegin; k < p.indexBegin + p.indexCount; k += 3) {
    yield [
      for (var j = 0; j < 3; j++) ...[v[i[k + j] * f], v[i[k + j] * f + 1]],
    ];
  }
}

/// The area of [m]'s path [path]'s triangles, summed.
double area(Mesh m, [int path = 0]) {
  var sum = 0.0;
  for (final t in triangles(m, path)) {
    sum += ((t[2] - t[0]) * (t[5] - t[1]) - (t[4] - t[0]) * (t[3] - t[1]))
        .abs();
  }
  return sum / 2;
}

/// A mesh of [draws] of [paths], flattened to [tolerance].
Mesh mesh(
  List<ui.Path> paths,
  List<PathDraw> draws, {
  double tolerance = 0.01,
}) => Mesh.fromPaths(
  [
    for (final path in paths) PathContours([path], tolerance: tolerance),
  ],
  draws,
  const Bounds(0, 0, 100, 100),
  tolerance: tolerance,
);

ui.Paint stroke(double width) => ui.Paint()
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = width;

/// [path] filled in blue, then stroked in red.
List<(ui.Path, ui.Paint)> paths2(ui.Path path) => [
  (path, ui.Paint()..color = const ui.Color(0xff0000ff)),
  (path, stroke(2)..color = const ui.Color(0xffff0000)),
];

void main() {
  final square = ui.Path()..addRect(const ui.Rect.fromLTWH(10, 10, 80, 80));
  final line = ui.Path()
    ..moveTo(0, 50)
    ..lineTo(100, 50);
  final hole = ui.Path()
    ..addPolygon(const [
      ui.Offset(30, 30),
      ui.Offset(30, 70),
      ui.Offset(70, 70),
      ui.Offset(70, 30),
    ], true);
  // The hole above runs the other way round from the square. This one runs
  // the same way.
  final sameHole = ui.Path()..addRect(const ui.Rect.fromLTWH(30, 30, 40, 40));

  group('canDraw', () {
    test('a color, filled or stroked with a width', () {
      expect(RasterizerScene.canDraw(ui.Paint()), isTrue);
      for (final cap in ui.StrokeCap.values) {
        for (final join in ui.StrokeJoin.values) {
          final paint = stroke(2)
            ..strokeCap = cap
            ..strokeJoin = join;
          expect(RasterizerScene.canDraw(paint), isTrue);
        }
      }
    });

    test('not what can\'t be read back, a hairline, nor other modes', () {
      for (final paint in [
        stroke(0),
        stroke(double.infinity),
        ui.Paint()
          ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(1, 1), [
            const ui.Color(0xff000000),
            const ui.Color(0xffffffff),
          ]),
        ui.Paint()
          ..colorFilter = const ui.ColorFilter.mode(
            ui.Color(0xffff0000),
            ui.BlendMode.srcATop,
          ),
        ui.Paint()
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2),
        ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        ui.Paint()..blendMode = ui.BlendMode.multiply,
        ui.Paint()..invertColors = true,
        ui.Paint()..isAntiAlias = false,
        ui.Paint()
          ..color = const ui.Color.from(
            alpha: 1,
            red: 1,
            green: 0,
            blue: 0,
            colorSpace: ui.ColorSpace.displayP3,
          ),
      ]) {
        expect(RasterizerScene.canDraw(paint), isFalse, reason: '$paint');
      }
    });
  });

  group('fromPaths', () {
    final paths = [
      (square, ui.Paint()..color = const ui.Color(0xff3060c0)),
      (square, stroke(4)..color = const ui.Color(0xff80a0e0)),
      (line, stroke(10)),
    ];

    test('throws for a maxSize that is not positive', () {
      for (final maxSize in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => RasterizerScene.fromPaths(
            paths,
            backend: RasterizerBackend.canvas,
            maxSize: maxSize,
          ),
          throwsArgumentError,
        );
      }
    });

    test('throws for a paint the GPU renderers can\'t draw, on every '
        'backend', () {
      for (final backend in RasterizerBackend.values) {
        expect(
          () => RasterizerScene.fromPaths(
            [(square, stroke(0))],
            backend: backend,
            maxSize: 512,
          ),
          throwsArgumentError,
          reason: backend.name,
        );
      }
    });

    test('has the paths\' bounds, with half their strokes, on every '
        'backend', () {
      for (final backend in RasterizerBackend.values) {
        final scene = RasterizerScene.fromPaths(
          paths,
          backend: backend,
          maxSize: 512,
        );
        expect(scene.backend, backend);
        expect(
          scene.viewBox,
          const ui.Rect.fromLTRB(0, 10, 100, 90),
          reason: backend.name,
        );
        // The square's stroke reaches 2 out. The core and the canvas renderer
        // grow the line's bounds by 5 on each side, as for SVGs. The mesh
        // renderer's bounds are its triangles', which end at the butt ends.
        final out = backend == RasterizerBackend.mesh ? 0 : 5;
        final bounds = scene.bounds;
        expect(bounds.left, closeTo(-out, 1e-4), reason: backend.name);
        expect(bounds.top, closeTo(8, 1e-4), reason: backend.name);
        expect(bounds.right, closeTo(100 + out, 1e-4), reason: backend.name);
        expect(bounds.bottom, closeTo(92, 1e-4), reason: backend.name);
        expect(scene.pathCount, 3, reason: backend.name);
        scene.dispose();
      }
    });

    test('of no paths is empty', () {
      for (final backend in RasterizerBackend.values) {
        final scene = RasterizerScene.fromPaths(
          const [],
          backend: backend,
          maxSize: 512,
        );
        expect(scene.viewBox, ui.Rect.zero, reason: backend.name);
        expect(scene.bounds, ui.Rect.zero, reason: backend.name);
        expect(scene.pathCount, 0, reason: backend.name);
      }
    });

    test('copies the paints', () async {
      final paint = ui.Paint()..color = const ui.Color(0xff00ff00);
      final scene = RasterizerScene.fromPaths(
        [(square, paint)],
        backend: RasterizerBackend.canvas,
        maxSize: 512,
      );
      paint.color = const ui.Color(0xffff0000);
      final recorder = ui.PictureRecorder();
      scene.drawPaths(ui.Canvas(recorder));
      final image = await recorder.endRecording().toImage(100, 100);
      final pixel = (await image.toByteData())!.buffer.asUint8List(
        4 * (50 * 100 + 50),
        4,
      );
      image.dispose();
      expect(pixel, [0, 0xff, 0, 0xff]);
    });

    test('flattens a path once for a tolerance, for each scene of it', () {
      final first = ScenePaths(paths), second = ScenePaths(paths);
      expect(first.paths, [square, line]);
      expect(first.pathIndices, [0, 0, 1]);
      final contours = first.contours(512);
      expect(second.contours(512), [for (final c in contours) same(c)]);
      expect(identical(second.contours(1024).first, contours.first), isFalse);
    });

    test('flattens to 1/4 of a device pixel at maxSize for the viewBox', () {
      // The viewBox's longer side is 100, wider than the widest stroke, 10.
      expect(ScenePaths(paths).tolerance(512), 0.25 * 100 / 512);
    });

    test('flattens a path for its stroke, if it\'s wider', () {
      // The zigzag is about 0.1 wide, far less than its stroke. Flattened for
      // its own size, its round joins and caps took thousands of triangles,
      // which took libtess seconds to tessellate.
      final zigzag = ui.Path()
        ..addPolygon([
          for (var i = 0; i < 8; i++) ui.Offset(i / 80, i.isEven ? 0 : 0.03),
        ], false);
      final round = stroke(2)
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      expect(ScenePaths([(zigzag, round)]).tolerance(1600), 0.25 * 2 / 1600);
      RasterizerScene.fromPaths(
        [(zigzag, round)],
        backend: RasterizerBackend.mesh,
        maxSize: 1600,
      ).dispose();
    });

    test('flattens a tiny line far from the origin into its ends', () {
      // The line is 0.006 long. Flattened to 1/4 of a device pixel at that
      // size, it was sampled finer than float precision, into 2234 points,
      // and libtess never finished tessellating them.
      final spike = ui.Path()
        ..moveTo(16.624696, 40.135567)
        ..lineTo(16.626923, 40.140943);
      final scenePaths = ScenePaths([(spike, stroke(0.001))]);
      expect(
        scenePaths.tolerance(1600),
        greaterThanOrEqualTo(16 * 40.14 / (1 << 23)),
      );
      final [contours] = scenePaths.contours(1600);
      expect(contours.points, hasLength(4));
      RasterizerScene.fromPaths(
        [(spike, stroke(0.001))],
        backend: RasterizerBackend.mesh,
        maxSize: 1600,
      ).dispose();
    });
  });

  group('glow', () {
    final stroked = [(line, stroke(4))];

    RasterizerScene scene(
      List<(ui.Path, ui.Paint)> paths,
      RasterizerGlow? glow, {
      RasterizerBackend backend = RasterizerBackend.mesh,
    }) => RasterizerScene.fromPaths(
      paths,
      backend: backend,
      maxSize: 512,
      glow: glow,
    );

    test('is equal to one of the same values, and only to it', () {
      const teal = ui.Color(0xff008080);
      RasterizerGlow glow({
        double radius = 3,
        double strength = 0.5,
        ui.Color? color = teal,
      }) => RasterizerGlow(radius, strength: strength, color: color);
      expect(identical(glow(), glow()), isFalse);
      expect(glow(), glow());
      expect(glow().hashCode, glow().hashCode);
      expect(glow(), isNot(glow(radius: 4)));
      expect(glow(), isNot(glow(strength: 1)));
      expect(glow(), isNot(glow(color: null)));
      expect(
        glow(),
        isNot(const RasterizerGlow.widths(3, strength: 0.5, color: teal)),
      );
    });

    test('asserts a finite radius of at least 0, a strength from 0 to 1', () {
      for (final radius in [-1.0, double.infinity, double.nan]) {
        expect(() => RasterizerGlow(radius), throwsAssertionError);
        expect(() => RasterizerGlow.widths(radius), throwsAssertionError);
      }
      for (final strength in [-0.1, 1.1, double.nan]) {
        expect(
          () => RasterizerGlow(1, strength: strength),
          throwsAssertionError,
        );
      }
      expect(RasterizerGlow(0, strength: 0).radius, 0);
    });

    test('the mesh renderer draws a ribbon of each path, within its '
        'bounds', () {
      final around = scene(stroked, const RasterizerGlow(12));
      expect(around.pathCount, 3, reason: 'its halo, its stroke and its core');
      // The halo reaches 12 from the line's centre, past its butt ends too.
      expect(
        around.bounds,
        rectMoreOrLessEquals(
          const ui.Rect.fromLTRB(-12, 38, 112, 62),
          epsilon: 1e-3,
        ),
      );
      final outward = scene([(square, ui.Paint())], const RasterizerGlow(5));
      expect(outward.pathCount, 2);
      expect(
        outward.bounds,
        rectMoreOrLessEquals(
          const ui.Rect.fromLTRB(5, 5, 95, 95),
          epsilon: 1e-3,
        ),
      );
      // A path drawn twice gets one halo. With its fill, its stroke and the
      // stroke's core, that makes 4.
      expect(scene(paths2(square), const RasterizerGlow(5)).pathCount, 4);
    });

    test('a radius in line widths is that many times a stroke\'s width', () {
      expect(
        scene(stroked, const RasterizerGlow.widths(3)).bounds,
        scene(stroked, const RasterizerGlow(12)).bounds,
      );
    });

    test('has its color and strength, or the last draw\'s at full', () {
      List<double> ribbon(RasterizerGlow glow) => (scene(
        paths2(square),
        glow,
      ) as MeshScene).debugMesh!.paths.first.color;
      expect(ribbon(const RasterizerGlow(5)), [1, 0, 0, 1]);
      expect(
        ribbon(
          const RasterizerGlow(5, strength: 0.5, color: ui.Color(0xff00ff00)),
        ),
        [0, closeTo(0.5, 1e-6), 0, closeTo(0.5, 1e-6)],
      );
      // A color in another color space is converted to sRGB.
      const p3 = ui.Color.from(
        alpha: 1,
        red: 0.4,
        green: 0.6,
        blue: 0.2,
        colorSpace: ui.ColorSpace.displayP3,
      );
      expect(
        ribbon(const RasterizerGlow(5, color: p3)),
        ribbon(
          RasterizerGlow(
            5,
            color: p3.withValues(colorSpace: ui.ColorSpace.sRGB),
          ),
        ),
      );
    });

    test('of no radius is none', () {
      expect(scene(stroked, const RasterizerGlow(0)).pathCount, 1);
    });

    test('the GPU and canvas renderers draw the paths without it', () async {
      for (final backend in [RasterizerBackend.gpu, RasterizerBackend.canvas]) {
        final plain = scene(stroked, null, backend: backend);
        final glowing = scene(
          stroked,
          const RasterizerGlow(12),
          backend: backend,
        );
        expect(glowing.pathCount, plain.pathCount, reason: backend.name);
        expect(glowing.bounds, plain.bounds, reason: backend.name);
        plain.dispose();
        if (backend == RasterizerBackend.canvas) {
          final recorder = ui.PictureRecorder();
          glowing.drawPaths(ui.Canvas(recorder));
          final image = await recorder.endRecording().toImage(100, 100);
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          image.dispose();
          // Opaque on the line, and clear within the glow's reach.
          expect(pixels[4 * (50 * 100 + 50) + 3], 0xff);
          expect(pixels[4 * (44 * 100 + 50) + 3], 0);
        }
        glowing.dispose();
      }
    });
  });

  group('hairlines', () {
    test('a mesh holds the polyline, with its offsets, and no area', () {
      final m = mesh(
        [line],
        const [PathDraw(path: 0, color: 0xff000000, hairline: true)],
      );
      expect(m.vertexFloats, 5);
      expect(m.paths.single.halfWidth, 0);
      expect(m.stripIndices, isNull);
      expect(area(m), 0);
      expect(m.indexCount ~/ 3, 2);
      expect(
        [m.bounds.lx, m.bounds.ly, m.bounds.ux, m.bounds.uy],
        [0, 50, 100, 50],
      );
      for (var k = 0; k < m.vertexCount; k++) {
        final v = m.vertices;
        expect(v[k * 5 + 1], 50);
        expect(v[k * 5] == 0 || v[k * 5] == 100, isTrue);
        expect([v[k * 5 + 3], v[k * 5 + 4].abs()], [0, 1]);
      }
    });

    test('a turn keeps its corners, whatever the segments\' lengths', () {
      final turn = ui.Path()
        ..moveTo(0, 0)
        ..lineTo(0.5, 0)
        ..lineTo(0.5, 0.5);
      final m = mesh(
        [turn],
        const [PathDraw(path: 0, color: 0xff000000, hairline: true)],
      );
      for (var k = 0; k < m.vertexCount; k++) {
        final v = m.vertices;
        final length = math.sqrt(
          v[k * 5 + 3] * v[k * 5 + 3] + v[k * 5 + 4] * v[k * 5 + 4],
        );
        expect(
          length,
          anyOf(closeTo(0, 1e-5), closeTo(1, 1e-5), closeTo(math.sqrt2, 1e-5)),
        );
      }
      expect(m.indexCount ~/ 3, greaterThanOrEqualTo(4));
    });

    test('a scene skips them', () {
      final scene = Scene.fromPaths(
        [
          PathContours([line], tolerance: 0.01),
        ],
        const [PathDraw(path: 0, color: 0xff000000, hairline: true)],
        const Bounds(0, 0, 100, 100),
      );
      expect(scene.count, 0);
      scene.dispose();
    });
  });

  group('core', () {
    test('a scene has its draws, and its viewBox', () {
      final contours = [
        PathContours([square, line], tolerance: 0.01),
      ];
      final scene = Scene.fromPaths(contours, const [
        PathDraw(path: 0, color: 0xff000000),
        PathDraw(path: 1, color: 0xff000000, strokeWidth: 10),
      ], const Bounds(0, 10, 100, 90));
      expect(scene.count, 2);
      expect(scene.svgBounds.toString(), 'Bounds(0.0, 10.0, 100.0, 90.0)');
      final b = scene.bounds;
      // The line's stroke grows the bounds by 5 on each side, as for SVGs.
      expect([b.lx, b.ly, b.ux, b.uy], [-5, 10, 105, 90]);
      expect(
        () => Scene.fromPaths(contours, const [
          PathDraw(path: 2, color: 0xff000000),
        ], const Bounds(0, 0, 1, 1)),
        throwsArgumentError,
      );
      scene.dispose();
    });

    test('a mesh fills with each rule, its open contours closed', () {
      final square = ui.Path()
        ..addRect(const ui.Rect.fromLTWH(10, 10, 80, 80))
        ..addPath(sameHole, ui.Offset.zero);
      expect(
        area(mesh([square], const [PathDraw(path: 0, color: 0xff000000)])),
        closeTo(6400, 1e-2),
      );
      expect(
        area(
          mesh(
            [square],
            const [PathDraw(path: 0, color: 0xff000000, evenOdd: true)],
          ),
        ),
        closeTo(4800, 1e-2),
      );
      final ring = ui.Path()
        ..addRect(const ui.Rect.fromLTWH(10, 10, 80, 80))
        ..addPath(hole, ui.Offset.zero);
      expect(
        area(mesh([ring], const [PathDraw(path: 0, color: 0xff000000)])),
        closeTo(4800, 1e-2),
      );
      final open = ui.Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0)
        ..lineTo(0, 100);
      expect(
        area(mesh([open], const [PathDraw(path: 0, color: 0xff000000)])),
        closeTo(5000, 1e-2),
      );
      final circle = ui.Path()
        ..addOval(
          ui.Rect.fromCircle(center: const ui.Offset(50, 50), radius: 40),
        );
      expect(
        area(mesh([circle], const [PathDraw(path: 0, color: 0xff000000)])),
        closeTo(math.pi * 1600, 2 * math.pi * 40 * 0.01),
      );
    });

    test('a mesh strokes with each cap, its closed contours closed', () {
      double stroked(ui.Path path, ui.StrokeCap cap) => area(
        mesh(
          [path],
          [PathDraw(path: 0, color: 0xff000000, strokeWidth: 10, cap: cap)],
        ),
      );
      expect(stroked(line, ui.StrokeCap.butt), closeTo(1000, 1e-2));
      expect(stroked(line, ui.StrokeCap.square), closeTo(1100, 1e-2));
      expect(
        stroked(line, ui.StrokeCap.round),
        closeTo(1000 + math.pi * 25, 0.5),
      );
      // With miter joins, it covers the outer square less the inner one.
      expect(
        stroked(square, ui.StrokeCap.butt),
        closeTo(90 * 90 - 70 * 70, 1e-2),
      );
    });

    test('a mesh has a path for each draw, with its color premultiplied', () {
      final m = mesh(
        [square],
        const [
          PathDraw(path: 0, color: 0x80ff4000),
          PathDraw(path: 0, color: 0xff0000ff, strokeWidth: 2),
        ],
      );
      expect(m.paths, hasLength(2));
      final a = 0x80 / 255;
      expect(m.paths[0].color, [
        closeTo(a, 1e-6),
        closeTo(a * 0x40 / 255, 1e-6),
        0,
        closeTo(a, 1e-6),
      ]);
      expect(m.paths[1].color, [0, 0, 1, 1]);
      expect(m.svgBounds.toString(), 'Bounds(0.0, 0.0, 100.0, 100.0)');
    });

    test('a mesh needs a positive tolerance', () {
      expect(
        () => Mesh.fromPaths(
          [
            PathContours([square], tolerance: 1),
          ],
          const [PathDraw(path: 0, color: 0xff000000)],
          const Bounds(0, 0, 1, 1),
          tolerance: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
