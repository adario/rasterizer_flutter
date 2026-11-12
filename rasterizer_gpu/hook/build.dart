// ignore_for_file: avoid_print

import 'package:code_assets/code_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the GPU renderers' shader bundle and the package's native library.
///
/// The library holds the Rasterizer core, NanoSVG, libtess2 and the C API, for
/// macOS, iOS, 64-bit Android and Linux. The core's sources are in src/core,
/// and libtess2's in src/libtess2: see each one's README.md.
///
/// flutter_gpu_shaders always writes the bundle into this package's
/// build/shaderbundles/, and pubspec.yaml lists it as an asset. When the
/// package is hosted, that's its folder in the pub cache. flutter_gpu_shaders
/// allows for that: its engine stamp reruns the hook when another project's
/// SDK rewrote the bundle. Dart data assets would avoid writing there, but
/// stable Flutter doesn't have them yet. A prebuilt bundle wouldn't work
/// either, as bundles are tied to the engine's impellerc.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'rasterizer.shaderbundle.json',
      includeDirectories: [input.packageRoot.resolve('shaders/')],
      // Bundles always include an OpenGL ES variant. The default, GLSL ES
      // 1.00, can't express texelFetch, integers or gl_VertexIndex, so
      // impellerc aborts in SPIRV-Cross. 3.00 is the minimum the renderers
      // need.
      glesLanguageVersion: 300,
    );

    if (!input.config.buildCodeAssets) {
      return;
    }
    final code = input.config.code;
    final os = code.targetOS;
    // Elsewhere, only the canvas renderer draws, which needs no native code.
    if (os != OS.macOS && os != OS.iOS && os != OS.android && os != OS.linux) {
      print(
        'rasterizer_gpu: no GPU renderer for $os, so its native code isn\'t '
        'built: the canvas renderer draws instead',
      );
      return;
    }
    // Nor on 32-bit Android. `flutter build apk` builds it by default, and
    // checkSupport reports it as unsupported.
    if (os == OS.android &&
        code.targetArchitecture != Architecture.arm64 &&
        code.targetArchitecture != Architecture.x64) {
      print(
        'rasterizer_gpu: no GPU renderer for ${code.targetArchitecture} '
        'Android, so its native code isn\'t built: the canvas renderer draws '
        'instead',
      );
      return;
    }
    const core = 'src/core', tess = 'src/libtess2';
    final cbuilder = CBuilder.library(
      name: input.packageName,
      // The asset that lib/src/bindings.dart's @Native functions resolve to.
      assetName: 'src/bindings.dart',
      // Every source compiles as C++. xxhash.c supports that, and libtess2
      // does with a patch.
      sources: [
        'src/ra_capi.cpp',
        '$core/nanosvg.cc',
        '$core/xxhash.c',
        for (final name in _tessSources) '$tess/Source/$name.c',
      ],
      includes: ['src', core, '$tess/Include'],
      language: Language.cpp,
      std: 'c++17',
      // Android's default, c++_shared, isn't packaged into the app, and this
      // is the package's only C++ library.
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
      // Bionic's libm isn't linked by default, unlike Apple's libSystem.
      libraries: [if (os == OS.android) 'm'],
      // Export only the C API, RA_EXPORT: not NanoSVG's, libtess2's or
      // xxHash's symbols, which another library loaded alongside may have too.
      flags: ['-fvisibility=hidden', '-fvisibility-inlines-hidden'],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.WARNING
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}

const _tessSources = [
  'bucketalloc',
  'dict',
  'geom',
  'mesh',
  'priorityq',
  'sweep',
  'tess',
];
