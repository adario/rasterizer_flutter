import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';
import 'package:rasterizer_gpu_example/goldens.dart';

import 'web_test.dart';

/// The tiger, which is separately licensed test data: see
/// assets/tiger/README.md.
const tigerAsset = 'assets/tiger/tiger.svg';

/// Defines the golden tests for each of [backends], and the GPU renderer's
/// checks of its atlas against itself.
///
/// [backends] defaults to the GPU and mesh renderers where they're supported,
/// and the canvas renderer. The canvas renderer's renders are checked against
/// the GPU renderer's goldens, with their own tolerance, and only for the
/// cases it draws the same ([GoldenCase.canvas]). The mesh renderer has its
/// own goldens ([GoldenCase.mesh]), prefixed with `mesh_`. Its renders are
/// also checked against the GPU renderer's goldens where there are some
/// ([GoldenCase.meshAsGpu]), with the canvas renderer's tolerance.
///
/// [golden] loads a golden's PNG, or returns null if there's none. [write]
/// saves an image. With [update], it saves each GPU or mesh render as its new
/// golden. Otherwise, it saves each failing render and its diff, prefixed
/// with `canvas_` or `mesh_` for those renderers. [recordDir], if set, is
/// where [GoldenRenders] records each frame. [log] prints each comparison's
/// line.
void defineGoldenTests({
  required Future<Uint8List?> Function(String name) golden,
  required void Function(GoldenImage image, {required bool asGolden}) write,
  required bool update,
  String? recordDir,
  List<RasterizerBackend>? backends,
  void Function(String line) log = _print,
}) {
  backends ??= [
    for (final gpu in [RasterizerBackend.gpu, RasterizerBackend.mesh])
      if (RasterizerGpu.of(gpu).support == RasterizerSupport.supported) gpu,
    RasterizerBackend.canvas,
  ];
  for (final backend in backends) {
    group(
      backend.name,
      () => _defineTests(
        backend,
        golden,
        write,
        update && backend != RasterizerBackend.canvas,
        recordDir,
        log,
      ),
    );
  }
}

/// Defines [backend]'s tests: see [defineGoldenTests].
void _defineTests(
  RasterizerBackend backend,
  Future<Uint8List?> Function(String name) golden,
  void Function(GoldenImage image, {required bool asGolden}) write,
  bool update,
  String? recordDir,
  void Function(String line) log,
) {
  final gpu = backend == RasterizerBackend.gpu,
      mesh = backend == RasterizerBackend.mesh,
      prefix = gpu ? '' : '${backend.name}_';
  late GoldenRenders renders;

  setUpAll(() async {
    if (backend != RasterizerBackend.canvas) {
      final state = RasterizerGpu.of(backend);
      expect(
        state.support,
        RasterizerSupport.supported,
        reason:
            'rasterizer_gpu\'s ${mesh ? 'mesh' : 'GPU'} renderer needs '
            'Impeller and Flutter GPU, and on OpenGL ES its self-test. '
            '${state.supportDetail ?? ''}',
      );
    }
    final tiger = await rootBundle.load(tigerAsset);
    renders = await GoldenRenders.load(
      Uint8List.sublistView(tiger),
      backend: backend,
      recordDir: recordDir,
    );
  });
  tearDownAll(() => renders.dispose());

  final cases = goldenCases.where(
    (c) => switch (backend) {
      RasterizerBackend.gpu => c.gpu,
      RasterizerBackend.canvas => c.canvas,
      RasterizerBackend.mesh => c.mesh,
    },
  );
  final kind = gpu ? 'golden' : backend.name;
  for (final c in cases) {
    webTest('$goldenSet $kind ${c.name}', () async {
      final failures = <String>[];
      // Compares [image] with [expected] as [name], within the canvas
      // renderer's tolerance if [loose]. If it fails, writes [image] and its
      // diff.
      void check(
        GoldenImage image,
        GoldenImage expected,
        String name, {
        required bool loose,
      }) {
        final diff = GoldenDiff(expected, image);
        final result = loose ? diff.toCanvasString() : '$diff';
        log('$name: $result');
        if (!(loose ? diff.passesCanvas : diff.passes)) {
          failures.add('$name: $result');
          write(image, asGolden: false);
          write(
            GoldenDiff.image(expected, image).renamed('${name}_diff'),
            asGolden: false,
          );
        }
      }

      for (final rendered in await c.render(renders)) {
        final image = rendered.renamed('$prefix${rendered.name}');
        // Also checks a mesh render against the GPU renderer's golden.
        final gpuPng = mesh && c.meshAsGpu ? await golden(rendered.name) : null;
        if (gpuPng != null) {
          check(
            image,
            GoldenImage.fromPng(rendered.name, gpuPng),
            '${image.name}_vs_gpu',
            loose: true,
          );
        }
        if (update) {
          write(image, asGolden: true);
          continue;
        }
        final png = await golden(mesh ? image.name : rendered.name);
        if (png == null) {
          failures.add('${image.name}: no golden for $goldenSet');
          write(image, asGolden: false);
          continue;
        }
        check(
          image,
          GoldenImage.fromPng(rendered.name, png),
          image.name,
          loose: !gpu && !mesh,
        );
      }
      expect(failures, isEmpty);
    });
  }

  if (!gpu) {
    return;
  }
  // Checks the GPU renderer against itself: each run in the atlas frame
  // against the same entries rendered as a frame of their own. The atlas
  // moves runs by whole pixels, but their transforms' floats round
  // differently, so antialiasing can differ slightly.
  test('atlas runs match each run rendered alone, and nothing is drawn outside '
      'them', () async {
    final all = await renders.atlas();
    log(
      'outside the runs: ${all.stray} pixels over 1/255, ${all.faint} at 1/255, largest ${all.strayLargest}/255',
    );
    expect(all.stray, 0, reason: 'pixels drawn outside the runs\' rectangles');
    for (var k = 0; k < all.runs.length; k++) {
      final alone = await renders.atlas(alone: k),
          diff = GoldenDiff(alone.runs.single, all.runs[k]);
      final r = all.rectangles[k];
      final area = r.fold(0, (a, p) => a + (p.width * p.height).toInt());
      final rects = [
        for (final p in r)
          '${p.width.toInt()}x${p.height.toInt()} at '
              '${p.left.toInt()},${p.top.toInt()}',
      ];
      log('run $k, ${rects.join(', ')}: $diff');
      expect(alone.rectangles.single, r);
      expect(alone.stray, 0);
      expect(
        diff.over8,
        lessThanOrEqualTo(area ~/ 10000),
        reason: 'run $k: $diff',
      );
    }
  });
}

// ignore: avoid_print
void _print(String line) => print('  $line');

/// The folder where a device run writes its images, for tool/pull_goldens.py
/// to copy.
///
/// It's a folder of the app's own, as on Linux the system's temporary folder
/// is shared. Each run deletes it first.
String deviceOutputDir() =>
    '${Directory.systemTemp.path}/goldens_rasterizer_gpu_example';
