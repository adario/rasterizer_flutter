// Checks that NanoSVG reads numbers the same whatever the C locale, from this
// package's folder:
//   flutter test test/svg_locale_test.dart
//
// A GTK app sets the C locale from the user's. NanoSVG read opacities,
// lengths and the viewBox with sscanf, which follows the locale's decimal
// point. So under a locale whose decimal point is a comma, such as en_DK or
// de_DE, 0.5 read as 0: translucent paths vanished, and the OpenGL ES
// self-tests failed on Linux. The test needs such a locale installed, and
// skips its checks under one where there's none.

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rasterizer_gpu/src/core.dart';
import 'package:test/test.dart';

final _setlocale = DynamicLibrary.process()
    .lookupFunction<
      Pointer<Utf8> Function(Int, Pointer<Utf8>),
      Pointer<Utf8> Function(int, Pointer<Utf8>)
    >('setlocale');

/// The C library's LC_NUMERIC: Apple's is 4, glibc's 1.
final _lcNumeric = Platform.isMacOS || Platform.isIOS ? 4 : 1;

/// Locales whose decimal point is a comma, under their names on macOS and on
/// Linux.
const _commaLocales = [
  'de_DE.UTF-8',
  'de_DE.utf8',
  'en_DK.UTF-8',
  'en_DK.utf8',
  'sv_SE.UTF-8',
  'sv_SE.utf8',
  'fr_FR.UTF-8',
  'fr_FR.utf8',
];

/// Sets LC_NUMERIC to [name], and returns whether it could.
bool _setNumeric(String name) => using(
  (arena) =>
      _setlocale(_lcNumeric, name.toNativeUtf8(allocator: arena)) != nullptr,
);

/// Returns the mesh of an SVG of [body], in a viewBox of [viewBox].
Mesh _mesh(String body, {String viewBox = '0 0 100 100'}) => Mesh.fromSvgBytes(
  Uint8List.fromList(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox">$body</svg>'
        .codeUnits,
  ),
  maxSize: 1000,
);

/// Checks that the SVGs' numbers read with their fractions.
void _checkNumbers() {
  // fill-opacity, and a length with a fraction.
  var m = _mesh(
    '<rect x="1" y="1" width="2.5" height="3" fill="#ff0000" '
    'fill-opacity="0.5"/>',
  );
  expect(m.paths.single.color[3], closeTo(0.5, 0.01));
  expect(m.bounds.ux, closeTo(3.5, 1e-4));
  // opacity after a space, and a length in ems, whose units follow the
  // number: 0.25em at a font size of 10 is 2.5.
  m = _mesh(
    '<rect x="1" y="1" font-size="10" width="0.25em" height="3" '
    'fill="#00ff00" opacity=" 0.75"/>',
  );
  expect(m.paths.single.color[3], closeTo(0.75, 0.01));
  expect(m.bounds.ux, closeTo(3.5, 1e-4));
  // A whole length in exes, which glibc's sscanf read as nothing, as it took
  // the e for an exponent's.
  m = _mesh(
    '<rect x="1" y="1" font-size="10" width="1ex" height="3" '
    'fill="#00ff00"/>',
  );
  expect(m.bounds.width, greaterThan(0));
  // A stroke's width.
  m = _mesh(
    '<path d="M10,10 L50,10" fill="none" stroke="#0000ff" '
    'stroke-width="1.5"/>',
  );
  expect(m.paths.single.halfWidth, closeTo(0.75, 1e-4));
  // The viewBox, its numbers separated by spaces and by commas.
  for (final viewBox in ['0.5 0 10.5 20.25', '0.5,0,10.5,20.25']) {
    final b = _mesh(
      '<rect width="1" height="1" fill="#000000"/>',
      viewBox: viewBox,
    ).svgBounds;
    expect([b.lx, b.ly, b.ux, b.uy], [0.5, 0, 11, 20.25], reason: viewBox);
  }
}

void main() {
  test('numbers read under the C locale', () {
    final saved = _setlocale(_lcNumeric, nullptr).toDartString();
    try {
      expect(_setNumeric('C'), isTrue);
      _checkNumbers();
    } finally {
      _setNumeric(saved);
    }
  });

  test('numbers read under a locale whose decimal point is a comma', () {
    final saved = _setlocale(_lcNumeric, nullptr).toDartString();
    try {
      final name = _commaLocales.where(_setNumeric).firstOrNull;
      if (name == null) {
        markTestSkipped('No locale with a decimal comma is installed');
        return;
      }
      _checkNumbers();
    } finally {
      _setNumeric(saved);
    }
  });
}
