import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

// The core's FFI API is internal, but the example checks frames with it.
// ignore: implementation_imports
import 'package:rasterizer_gpu/src/core.dart' as ra;
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'goldens.dart';

/// Renders [frame], if it's the GPU renderer's, and reads back its runs for
/// the golden tests. Returns null for the other renderers' frames.
///
/// It copies each run's parts out of the atlas pages into an image of the
/// golden viewport's size. It also counts the pixels that the pages have
/// outside all the parts. With [recordDir], it writes the frame's atlas
/// pages, core frames and lists there too: see [GoldenRenders].
Future<FrameRenders>? renderAtlasFrame(
  String name,
  RasterizerFrame frame,
  RasterizerRenderer renderer,
  bool curves,
  String Function(int entry) svgOf,
  String? recordDir,
) {
  if (frame is! ra.AtlasFrame) {
    return null;
  }
  return _render(
    name,
    frame,
    renderer as ra.AtlasRenderer,
    curves,
    svgOf,
    recordDir,
  );
}

/// Does the work of [renderAtlasFrame], with [record] as its `recordDir`.
Future<FrameRenders> _render(
  String name,
  ra.AtlasFrame frame,
  ra.AtlasRenderer renderer,
  bool curves,
  String Function(int entry) svgOf,
  String? record,
) async {
  if (record != null) {
    renderer.debugFrameWritten = (page, f) {
      File('$record/golden_${name}_p${page}_frame.bin')
          .writeAsBytesSync(f.bytes);
      File('$record/golden_${name}_p${page}_frame.txt').writeAsStringSync(
        [
          'colors ${f.colors} paths ${f.paths} texStrips ${f.texStrips} p16s '
              '${f.p16s} pathsCount ${f.pathsCount} '
              'texCount ${f.texCount} headerSize ${f.headerSize} size '
              '${f.size}',
          ...f.entries,
        ].join('\n'),
      );
    };
  }
  frame.render();
  renderer.debugFrameWritten = null;
  // Request every page's readback before awaiting any, as the next frames
  // render into these textures again.
  final images = {
    for (final run in frame.runs)
      for (final part in run.parts) part.page: part.image,
  };
  final reads = {
    for (final MapEntry(:key, :value) in images.entries) key: readRgba(value),
  };
  final pages = {
    for (final MapEntry(:key, :value) in reads.entries)
      key: Uint8List.sublistView((await value)!),
  };
  final covered = {
    for (final MapEntry(:key, :value) in images.entries)
      key: Uint8List(value.width * value.height),
  };

  final runs = <GoldenImage>[], rectangles = <List<ui.Rect>>[];
  final many = frame.runs.length > 1;
  for (final run in frame.runs) {
    final out = Uint8List(goldenWidth * goldenHeight * 4);
    for (final part in run.parts) {
      final page = pages[part.page]!,
          cover = covered[part.page]!,
          pw = part.image.width;
      final s = part.source,
          d = part.destination,
          w = s.width.toInt(),
          h = s.height.toInt();
      // Parts' rectangles can overlap, each transparent where the other's
      // entries are. So composite them as they're drawn: premultiplied, the
      // later over the earlier.
      for (var y = 0; y < h; y++) {
        final from = ((s.top.toInt() + y) * pw + s.left.toInt()),
            to = (d.top.toInt() + y) * goldenWidth + d.left.toInt();
        for (var x = 0; x < w; x++) {
          final i = 4 * (from + x), o = 4 * (to + x), a = page[i + 3];
          for (var c = 0; c < 4; c++) {
            out[o + c] = page[i + c] + (out[o + c] * (255 - a) + 127) ~/ 255;
          }
        }
        cover.fillRange(from, from + w, 1);
      }
    }
    runs.add(
      GoldenImage(
        many ? '${name}_run${run.index}' : name,
        goldenWidth,
        goldenHeight,
        out,
      ),
    );
    rectangles.add([for (final part in run.parts) part.destination]);
  }
  // Count the pixels that the pages have outside all the parts: see
  // FrameRenders.
  var stray = 0, faint = 0, strayLargest = 0;
  for (final MapEntry(:key, :value) in pages.entries) {
    final cover = covered[key]!;
    for (var k = 0; k < cover.length; k++) {
      if (cover[k] != 0) {
        continue;
      }
      final alpha = value[4 * k + 3];
      if (alpha > 1) {
        stray++;
      }
      if (alpha == 1) {
        faint++;
      }
      if (alpha > strayLargest) {
        strayLargest = alpha;
      }
    }
  }

  // Write each page's pixels, and a list of the entries drawn into it, each
  // with its SVG's name.
  if (record != null) {
    for (final MapEntry(:key, :value) in pages.entries) {
      final (pw, ph) = frame.pageSizes[key];
      final entries = StringBuffer(
        'entries ${svgOf(0)} $pw $ph ${curves ? 1 : 0}\n',
      );
      for (var i = 0; i < frame.entryCount; i++) {
        final core = frame.coreEntry(i);
        if (core != null && frame.entryRun(i).$2 == key) {
          entries.writeln([...core.$1, ...core.$2, svgOf(i)].join(' '));
        }
      }
      File('$record/golden_${name}_p$key.rgba').writeAsBytesSync(value);
      File('$record/golden_${name}_p$key.entries')
          .writeAsStringSync(entries.toString());
    }
  }
  return FrameRenders(runs, stray, faint, strayLargest, rectangles);
}
