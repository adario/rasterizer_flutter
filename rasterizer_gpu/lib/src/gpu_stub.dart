import 'dart:typed_data';

import '../rasterizer_gpu.dart';
import 'paths/scene_paths.dart';

export 'self_test_cache.dart' show SelfTestAttempt, SelfTestCache;

// This file replaces atlas.dart where dart:ffi isn't available, as on web.
// There, only the canvas renderer works.

String? contextError;

RasterizerSupport checkSupport() => RasterizerSupport.unsupportedPlatform;

bool openGles = false;

int maxPageSize = RasterizerRenderer.maxAtlasSize;

Future<({bool passed, String detail, bool conclusive})> selfTest(
  RasterizerBackend backend,
  Set<String> fail, {
  bool apply = true,
}) async => (
  passed: false,
  detail: 'no GPU renderer without dart:ffi',
  conclusive: false,
);

void Function()? onGpuFrame, onMeshFrame;

RasterizerScene parseScene(Uint8List bytes) =>
    throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

Future<RasterizerRenderer> createRenderer(int slots) =>
    throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

RasterizerScene parseMeshScene(Uint8List bytes, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');

RasterizerScene importPathScene(ScenePaths paths, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no GPU renderer without dart:ffi');

RasterizerScene importPathMeshScene(ScenePaths paths, double maxSize) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');

Future<RasterizerRenderer> createMeshRenderer(int slots, int samples) =>
    throw UnsupportedError('rasterizer_gpu: no mesh renderer without dart:ffi');
