import 'dart:typed_data';

import '../rasterizer_gpu.dart';
import 'paths/scene_paths.dart';

// This file replaces atlas.dart where dart:ffi isn't available, as on web.
// There, only the canvas renderer works.

String? contextError;

RasterizerSupport checkSupport(int textureWidth) =>
    RasterizerSupport.unsupportedPlatform;

bool openGles = false;

int maxPageSize = RasterizerRenderer.maxAtlasSize;

Future<String?>? formatProbe;

String get formatDetail => 'no GPU renderer without dart:ffi';

String get meshDetail => formatDetail;

void resetFormatProbe() {}

Future<String?> debugProbeFormat(Set<String> fail) async =>
    'no GPU renderer without dart:ffi';

RasterizerScene parseScene(Uint8List bytes) =>
    throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

Future<RasterizerRenderer> createRenderer(
  int slots,
  Set<String> fail,
  Duration timeout,
) => throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

RasterizerScene parseMeshScene(Uint8List bytes, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');

RasterizerScene importPathScene(ScenePaths paths, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

RasterizerScene importPathMeshScene(ScenePaths paths, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');

Future<RasterizerRenderer> createMeshRenderer(
  int slots,
  int samples,
  Duration timeout,
) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');
