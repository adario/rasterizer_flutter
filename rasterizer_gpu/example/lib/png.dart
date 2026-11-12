import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder, ZLibEncoder;

/// Encodes raw 8-bit RGBA pixels as a PNG, byte for byte, so that they decode
/// back exactly.
///
/// Flutter's own PNG encoding unpremultiplies a readback's pixels, which
/// loses the low bits of translucent pixels. So the goldens use this instead.
/// Their PNGs hold the readback's premultiplied bytes, which image viewers
/// show slightly darker where pixels are translucent.
///
/// The zlib compression is package:archive's. It uses dart:io's where there's
/// dart:io, and its own, in Dart, on the web.
Uint8List encodePng(int width, int height, Uint8List rgba) {
  final stride = width * 4, rows = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    // Filter each row with PNG's Sub filter, the difference from the pixel to
    // its left, which compresses flat areas well.
    final o = y * (stride + 1), i = y * stride;
    rows[o] = 1;
    for (var x = 0; x < stride; x++) {
      rows[o + 1 + x] = rgba[i + x] - (x < 4 ? 0 : rgba[i + x - 4]);
    }
  }
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = Uint8List.fromList([...type.codeUnits, ...data]);
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc(body)));
  }

  chunk('IHDR', [..._u32(width), ..._u32(height), 8, 6, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder().encodeBytes(rows, level: 6));
  chunk('IEND', const []);
  return out.takeBytes();
}

/// Decodes an 8-bit RGBA, non-interlaced PNG, as [encodePng] writes. Returns
/// its width, its height and its raw bytes.
(int, int, Uint8List) decodePng(Uint8List png) {
  final data = ByteData.sublistView(png);
  var offset = 8, width = 0, height = 0;
  final idat = BytesBuilder(copy: false);
  while (offset + 8 <= png.length) {
    final length = data.getUint32(offset),
        type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = Uint8List.sublistView(png, offset + 8, offset + 8 + length);
    if (type == 'IHDR') {
      width = data.getUint32(offset + 8);
      height = data.getUint32(offset + 12);
      if (body[8] != 8 || body[9] != 6 || body[12] != 0) {
        throw const FormatException('Not an 8-bit RGBA, non-interlaced PNG');
      }
    } else if (type == 'IDAT') {
      idat.add(body);
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  final rows = ZLibDecoder().decodeBytes(idat.takeBytes()),
      stride = width * 4,
      rgba = Uint8List(height * stride);
  for (var y = 0; y < height; y++) {
    final o = y * (stride + 1), i = y * stride, filter = rows[o];
    for (var x = 0; x < stride; x++) {
      final a = x < 4 ? 0 : rgba[i + x - 4],
          b = y == 0 ? 0 : rgba[i + x - stride],
          c = x < 4 || y == 0 ? 0 : rgba[i + x - stride - 4];
      final v = rows[o + 1 + x];
      rgba[i + x] = switch (filter) {
        0 => v,
        1 => v + a,
        2 => v + b,
        3 => v + (a + b) ~/ 2,
        4 => v + _paeth(a, b, c),
        _ => throw FormatException('Unknown PNG filter $filter'),
      };
    }
  }
  return (width, height, rgba);
}

/// PNG's Paeth predictor: of the pixels to the left ([a]), above ([b]) and
/// above left ([c]), the one closest to a + b - c.
int _paeth(int a, int b, int c) {
  final p = a + b - c,
      pa = (p - a).abs(),
      pb = (p - b).abs(),
      pc = (p - c).abs();
  return pa <= pb && pa <= pc
      ? a
      : pb <= pc
      ? b
      : c;
}

/// [v]'s 4 bytes, big-endian, as PNG stores integers.
List<int> _u32(int v) => [
  v >> 24 & 0xFF,
  v >> 16 & 0xFF,
  v >> 8 & 0xFF,
  v & 0xFF,
];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// The CRC-32 of [bytes], which ends each PNG chunk.
int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
