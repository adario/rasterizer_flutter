// Checks the OpenGL ES self-test's scene, from this package's folder:
//   flutter test test/self_test_scene_test.dart
//
// The self-test doesn't parse selfTestSvg: src/ra_self_test.hpp builds its
// shapes, so that a parser's bug can't fail the GPU renderers. The scene
// must still be selfTestSvg's. So at each pixel that the self-test checks,
// the paths over it, composited as the GPU does, must give the colour that
// the check expects, both for the built mesh and for the parsed SVG's.

import 'dart:typed_data';

import 'package:rasterizer_gpu/src/core.dart';
import 'package:rasterizer_gpu/src/self_test.dart';
import 'package:test/test.dart';

/// Returns whether one of [m]'s path [path]'s triangles holds [x], [y].
bool _covers(Mesh m, int path, double x, double y) {
  final p = m.paths[path], v = m.vertices, i = m.indices as List<int>;
  final f = m.vertexFloats;
  for (var k = p.indexBegin; k < p.indexBegin + p.indexCount; k += 3) {
    final t = [
      for (var j = 0; j < 3; j++) ...[v[i[k + j] * f], v[i[k + j] * f + 1]],
    ];
    double side(int a, int b) =>
        (t[b] - t[a]) * (y - t[a + 1]) - (t[b + 1] - t[a + 1]) * (x - t[a]);
    final s0 = side(0, 2), s1 = side(2, 4), s2 = side(4, 0);
    if ((s0 >= 0 && s1 >= 0 && s2 >= 0) || (s0 <= 0 && s1 <= 0 && s2 <= 0)) {
      return true;
    }
  }
  return false;
}

/// Returns [m]'s pixels at the self-test's probes, premultiplied, its paths
/// composited source over, as the GPU renderers draw them. Other pixels are
/// transparent.
Uint8List _render(Mesh m) {
  final rgba = Uint8List(4 * selfTestSize * selfTestSize);
  for (final (:x, :y) in selfTestPixels) {
    final c = [0.0, 0.0, 0.0, 0.0];
    for (var path = 0; path < m.paths.length; path++) {
      if (_covers(m, path, x + 0.5, y + 0.5)) {
        final p = m.paths[path].color;
        for (var k = 0; k < 4; k++) {
          c[k] = p[k] + c[k] * (1 - p[3]);
        }
      }
    }
    final i = 4 * (y * selfTestSize + x);
    for (var k = 0; k < 4; k++) {
      rgba[i + k] = (c[k] * 255).round();
    }
  }
  return rgba;
}

String? _check(Mesh m) => checkSelfTest(_render(m), 4 * selfTestSize, 0, 0, (
  left: 0,
  top: 0,
  width: selfTestSize,
  height: selfTestSize,
));

void main() {
  final size = selfTestSize.toDouble();
  final parsedMesh = Mesh.fromSvgBytes(
    Uint8List.fromList(selfTestSvg.codeUnits),
    maxSize: size,
  );
  final builtMesh = Mesh.selfTest(maxSize: size);

  test("the parsed SVG's mesh passes the check", () {
    expect(_check(parsedMesh), isNull);
  });

  test('the built mesh passes the check', () {
    expect(_check(builtMesh), isNull);
  });

  test('the built mesh has the parsed paths and paints, in order', () {
    expect(builtMesh.paths.length, parsedMesh.paths.length);
    for (var i = 0; i < builtMesh.paths.length; i++) {
      final built = builtMesh.paths[i], parsed = parsedMesh.paths[i];
      expect(built.paint, parsed.paint, reason: 'path $i');
      expect(built.color, parsed.color, reason: 'path $i');
      expect(built.halfWidth, parsed.halfWidth, reason: 'path $i');
    }
    final b = builtMesh.svgBounds, p = parsedMesh.svgBounds;
    expect([b.lx, b.ly, b.ux, b.uy], [p.lx, p.ly, p.ux, p.uy]);
  });

  test("the built scene is the parsed SVG's", () {
    final built = Scene.selfTest(),
        parsed = Scene.fromSvgBytes(Uint8List.fromList(selfTestSvg.codeUnits));
    addTearDown(built.dispose);
    addTearDown(parsed.dispose);
    expect(built.count, parsed.count);
    final b = built.svgBounds, p = parsed.svgBounds;
    expect([b.lx, b.ly, b.ux, b.uy], [p.lx, p.ly, p.ux, p.uy]);
    final t = built.svgTransform, u = parsed.svgTransform;
    expect([t.a, t.b, t.c, t.d, t.tx, t.ty], [u.a, u.b, u.c, u.d, u.tx, u.ty]);
    final bb = built.bounds, pb = parsed.bounds;
    for (final (x, y) in [
      (bb.lx, pb.lx),
      (bb.ly, pb.ly),
      (bb.ux, pb.ux),
      (bb.uy, pb.uy),
    ]) {
      expect(x, closeTo(y, 0.01));
    }
  });

  test('Mesh.selfTest rejects a size that is not positive', () {
    expect(() => Mesh.selfTest(maxSize: 0), throwsArgumentError);
    expect(() => Mesh.selfTest(maxSize: double.nan), throwsArgumentError);
  });
}
