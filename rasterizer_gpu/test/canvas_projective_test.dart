// Checks the canvas renderer's projective entries, added with
// RasterizerRun.addProjective, without a GPU. From this package's folder:
//   flutter test test/canvas_projective_test.dart
//
// An entry must draw as the scene's paths do under a canvas transform with
// the same perspective. That holds in a painted run's layer too.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

const _size = 64;

final _bytes = Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
    '<rect x="4" y="4" width="40" height="40" fill="red"/>'
    '<circle cx="40" cy="40" r="16" fill="#0000ff" fill-opacity="0.5"/>'
    '</svg>',
  ),
);

/// What [draw] draws into a picture, as RGBA.
Future<Uint8List> _pixels(void Function(ui.Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(_size, _size);
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  final scene = RasterizerScene.fromSvg(
    _bytes,
    backend: RasterizerBackend.canvas,
  );
  late final RasterizerRenderer renderer;
  setUpAll(
    () async => renderer = await RasterizerRenderer.create(
      slots: 1,
      backend: RasterizerBackend.canvas,
    ),
  );

  /// Draws a new frame's run, of the entries that [add] adds, with [paint].
  /// Returns its pixels.
  Future<Uint8List> run(
    void Function(RasterizerRun run) add, {
    ui.Paint? paint,
  }) {
    final frame = renderer.beginFrame(_size, _size);
    final run = frame.addRun();
    add(run);
    frame.render();
    return _pixels((canvas) => run.draw(canvas, paint: paint));
  }

  /// A move by [tx] along x, with a perspective: w = [g] x + [h] y + [i].
  Matrix4 projective(double g, double h, double i, [double tx = 0]) =>
      Matrix4.identity()
        ..setEntry(0, 3, tx)
        ..setEntry(3, 0, g)
        ..setEntry(3, 1, h)
        ..setEntry(3, 3, i);

  /// The pixels of [scene]'s paths drawn straight into a canvas under [m], in
  /// a layer with [paint] if there is one.
  Future<Uint8List> reference(Matrix4 m, {ui.Paint? paint}) =>
      _pixels((canvas) {
        if (paint != null) {
          canvas.saveLayer(null, paint);
        }
        canvas.transform(m.storage);
        scene.drawPaths(canvas);
        if (paint != null) {
          canvas.restore();
        }
      });

  test('a projective entry draws as the canvas transform with its '
      'perspective', () async {
    final m = projective(0.01, 0.005, 1);
    final expected = await reference(m);
    expect(expected.any((v) => v != 0), isTrue);
    expect(
      await run(
        (run) => run.addProjective(scene, 1, 0, 0, 1, 0, 0, .01, .005, 1),
      ),
      expected,
    );
    expect(await run((run) => run.addMatrix(scene, m)), expected);
  });

  test('a constant w divides the affine part', () async {
    expect(
      await run((run) => run.addProjective(scene, 2, 0, 0, 2, 8, 0, 0, 0, 2)),
      await run((run) => run.add(scene, 1, 0, 0, 1, 4, 0)),
    );
  });

  test("with a paint, its layer holds the projected entry, and the viewport "
      "where a corner is behind the eye", () async {
    final paint = ui.Paint()..color = const ui.Color(0x80000000);
    for (final m in [
      projective(0.01, 0.005, 1, 10),
      // w is 0 at x = 50, so the scene's right side is behind the eye.
      projective(-0.02, 0, 1),
    ]) {
      final expected = await reference(m, paint: paint);
      expect(expected.any((v) => v != 0), isTrue);
      expect(
        await run((run) => run.addMatrix(scene, m), paint: paint),
        expected,
      );
    }
  });
}
