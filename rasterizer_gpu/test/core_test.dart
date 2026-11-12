// ignore_for_file: avoid_print
// Checks Rasterizer's core through FFI, from this package's folder:
//   flutter test test/core_test.dart --reporter expanded
//
// It prints the frames that the GPU renderer would draw for generated
// scenes: their sections and their entries.

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:rasterizer_gpu/src/core.dart';
import 'package:test/test.dart';

const viewWidth = 1024.0, viewHeight = 768.0, viewScale = 2.0;

/// A random SVG of [paths] paths, from [seed], drawn like a city map.
///
/// Its viewBox is 4000 by 3000. A gradient band comes first. Then come
/// stroked roads of lines and curves, curved parks, square blocks with a hole,
/// filled even-odd, and buildings, some translucent. A group around them all
/// flips them upside down.
Uint8List mapSvg(int paths, {int seed = 1}) {
  final r = math.Random(seed), out = StringBuffer();
  String n(double v) => v.toStringAsFixed(1);
  String color() =>
      '#${(r.nextInt(0xFFFFFF) | 0x101010).toRadixString(16).padLeft(6, '0')}';
  out.write(
    '<svg xmlns="http://www.w3.org/2000/svg" width="4000" height="3000" viewBox="0 0 4000 3000">'
    '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2060c0"/>'
    '<stop offset="1" stop-color="#80e0ff"/></linearGradient></defs>'
    '<g transform="translate(0,3000) scale(1,-1)">'
    '<path fill="url(#g)" d="M0,0 L4000,0 L4000,600 C3000,900 1000,300 0,700 Z"/>',
  );
  for (var i = 1; i < paths; i++) {
    final x = r.nextDouble() * 4000,
        y = r.nextDouble() * 3000,
        s = 4 + r.nextDouble() * 40;
    switch (r.nextInt(10)) {
      case 0 || 1:
        // A road: a stroked polyline or curve.
        final dx = (r.nextDouble() - 0.5) * 300,
            dy = (r.nextDouble() - 0.5) * 300;
        final d = r.nextBool()
            ? 'M${n(x)},${n(y)} L${n(x + dx)},${n(y + dy)} '
                  'L${n(x + 2 * dx)},${n(y + dy * 0.5)}'
            : 'M${n(x)},${n(y)} Q${n(x + dx)},${n(y - dy)} '
                  '${n(x + 2 * dx)},${n(y + dy)}';
        out.write(
          '<path fill="none" stroke="${color()}" '
          'stroke-width="${n(1 + r.nextDouble() * 6)}" '
          'stroke-linecap="${r.nextBool() ? 'round' : 'butt'}" stroke-linejoin="${r.nextBool() ? 'round' : 'miter'}" d="$d"/>',
        );
      case 2:
        // A park: a curved closed shape.
        out.write(
          '<path fill="${color()}" d="M${n(x - s)},${n(y)} '
          'C${n(x - s)},${n(y + s)} ${n(x + s)},${n(y + s)} '
          '${n(x + s)},${n(y)} '
          'S${n(x - s)},${n(y - 2 * s)} ${n(x - s)},${n(y)} Z"/>',
        );
      case 3:
        // A courtyard block: a square with a hole.
        out.write(
          '<path fill-rule="evenodd" fill="${color()}" d="M${n(x)},${n(y)} '
          'h${n(2 * s)} v${n(2 * s)} h${n(-2 * s)} Z '
          'M${n(x + s / 2)},${n(y + s / 2)} h${n(s)} v${n(s)} h${n(-s)} Z"/>',
        );
      default:
        // A building: a rotated quadrilateral, some translucent.
        final a = r.nextDouble() * math.pi,
            c = math.cos(a) * s,
            sn = math.sin(a) * s,
            w = 0.4 + r.nextDouble();
        out.write(
          '<polygon '
          'fill="${color()}"${r.nextInt(5) == 0 ? ' fill-opacity="0.7"' : ''} '
          'points="${n(x)},${n(y)} ${n(x + c)},${n(y + sn)} ${n(x + c - sn * w)},${n(y + sn + c * w)} ${n(x - sn * w)},${n(y + c * w)}"/>',
        );
    }
  }
  out.write('</g></svg>');
  return Uint8List.fromList(out.toString().codeUnits);
}

/// A scene of [mapSvg] with 300 paths, about as many as the tiger has.
Scene smallScene() => Scene.fromSvgBytes(mapSvg(300));

/// A scene list of [scene] alone, fitted into the view.
SceneList fittedList(Scene scene) {
  final list = SceneList()..addScene(scene, scene.svgTransform);
  list.ctm = const Bounds(0, 0, viewWidth, viewHeight).fit(list.bounds);
  return list;
}

/// The size of [frame], its sections, and its entries counted by type.
String summary(Frame frame) {
  final out = StringBuffer()
    ..writeln(
      '  frame ${frame.size} bytes, header ${frame.headerSize}, '
      '${frame.pathsCount} paths, ${frame.texCount} gradient strips',
    )
    ..writeln(
      '  sections: colors ${frame.colors}, paths ${frame.paths}, texStrips '
      '${frame.texStrips}, p16s ${frame.p16s}',
    )
    ..writeln('  ${frame.entries.length} entries:');
  for (final type in EntryType.values) {
    final entries = frame.entries.where((e) => e.type == type).toList();
    if (entries.isEmpty) {
      continue;
    }
    final counts = type.itemSize == 0
        ? ''
        : ', ${entries.fold(0, (n, e) => n + e.count)} items of '
              '${type.itemSize} bytes';
    out.writeln(
      '    ${type.name.padRight(15)} ${entries.length} entries$counts',
    );
  }
  return out.toString();
}

/// Checks the layout of [frame], rendered from [scene].
///
/// It checks the sections' order and sizes, the entries' ranges and types,
/// and the clear color.
void checkFrame(Frame frame, Scene scene) {
  expect(frame.pathsCount, scene.count);
  expect(frame.colors, 0);
  expect(frame.paths, greaterThan(frame.colors));
  expect(frame.headerSize, greaterThan(frame.paths));
  expect(frame.texStrips, greaterThanOrEqualTo(frame.headerSize));
  expect(
    frame.p16s - frame.texStrips,
    frame.texCount * layout.colorTextureWidth * layout.color,
  );
  for (final entry in frame.entries.where((e) => e.isRange)) {
    expect(
      entry.begin,
      greaterThanOrEqualTo(frame.headerSize),
      reason: '$entry',
    );
    expect(entry.end, lessThanOrEqualTo(frame.size), reason: '$entry');
    expect(
      (entry.end - entry.begin) % entry.type.itemSize,
      0,
      reason: '$entry',
    );
  }
  // Each pass's edges use at most as many rows of the accumulation texture
  // as the view has device pixels.
  for (final entry in frame.entries.where(
    (e) => e.type == EntryType.instancesBase,
  )) {
    expect(
      entry.end,
      inInclusiveRange(1, (viewHeight * viewScale).ceil()),
      reason: '$entry',
    );
  }
  // The core's SVG import makes no clip paths or blend modes, so the GPU
  // renderer needs none of their pipelines.
  final unsupported = {
    EntryType.clipMask,
    EntryType.enableClip,
    EntryType.blendInstances,
  };
  expect(frame.entries.where((e) => unsupported.contains(e.type)), isEmpty);
  expect(
    frame.entries.where((e) => e.type == EntryType.instances && e.count > 0),
    isNotEmpty,
  );
  // The clear color, BGRA, comes right after the paths' colors.
  final clear = ByteData.sublistView(
    frame.bytes,
    frame.colors + frame.pathsCount * layout.color,
    frame.colors + (frame.pathsCount + 1) * layout.color,
  );
  final argb =
      clear.getUint8(3) << 24 |
      clear.getUint8(2) << 16 |
      clear.getUint8(1) << 8 |
      clear.getUint8(0);
  expect(argb, frame.params.clearColor);
}

void main() {
  test('layout', () {
    print(
      '  color ${layout.color}, pathData ${layout.pathData}, opaque '
      '${layout.opaque}, instance ${layout.instance}, '
      'edge ${layout.edge}, segment ${layout.segment}, point16 '
      '${layout.point16}, entry ${layout.entry}',
    );
    print(
      '  colorTextureWidth ${layout.colorTextureWidth}, moleculesHeight '
      '${layout.moleculesHeight}, '
      'fastSegments ${layout.fastSegments}, stripHeight ${layout.stripHeight}',
    );
    expect(layout.color, 4);
    expect(layout.entry, 24);
    expect(layout.edge, 8);
    expect(layout.segment, 16);
    expect(layout.point16, 4);
    expect(layout.instance % 4, 0);
    expect(layout.opaque % 4, 0);
  });

  test('an unparseable file throws', () {
    expect(
      () => Scene.fromSvg(
        '${Directory.systemTemp.path}/rasterizer_gpu_missing.svg',
      ),
      throwsArgumentError,
    );
  });

  test('parsing bytes is parsing the file', () {
    final dir = Directory.systemTemp.createTempSync('rasterizer_gpu_test'),
        path = '${dir.path}/map.svg';
    File(path).writeAsBytesSync(mapSvg(300));
    final fromFile = Scene.fromSvg(path),
        fromBytes = Scene.fromSvgBytes(File(path).readAsBytesSync());
    dir.deleteSync(recursive: true);
    expect(fromBytes.count, fromFile.count);
    expect(fromBytes.svgTransform.toString(), fromFile.svgTransform.toString());
    final a = Renderer().render(
      fittedList(fromFile),
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );
    final b = Renderer().render(
      fittedList(fromBytes),
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );
    expect(b.entries.join(), a.entries.join());
  });

  test("an SVG's own bounds are its viewBox, or else its width and height", () {
    Uint8List svg(String attributes) => Uint8List.fromList(
      '<svg xmlns="http://www.w3.org/2000/svg" $attributes><rect x="10" y="10" width="200" height="5"/></svg>'
          .codeUnits,
    );
    List<double> svgBounds(String attributes) {
      final scene = Scene.fromSvgBytes(svg(attributes)), b = scene.svgBounds;
      expect(
        scene.bounds.ux,
        210,
        reason:
            "paths can draw outside it, and aren't scaled to the width and "
            "height",
      );
      scene.dispose();
      return [b.lx, b.ly, b.ux, b.uy];
    }

    expect(svgBounds('width="64" height="48"'), [0, 0, 64, 48]);
    expect(svgBounds('viewBox="0 0 32 24"'), [0, 0, 32, 24]);
    expect(svgBounds('width="64" height="48" viewBox="-4 2 32 24"'), [
      -4,
      2,
      28,
      26,
    ]);
  });

  test("an SVG's transform flips it onto its own bounds", () {
    double flip(String attributes) {
      final scene = Scene.fromSvgBytes(
        Uint8List.fromList(
          '<svg xmlns="http://www.w3.org/2000/svg" $attributes><rect x="1" y="1" width="2" height="2"/></svg>'
              .codeUnits,
        ),
      );
      final t = scene.svgTransform;
      scene.dispose();
      expect([t.a, t.b, t.c, t.d, t.tx], [1, 0, 0, -1, 0]);
      return t.ty;
    }

    expect(flip('width="64" height="48"'), 48);
    expect(flip('width="48" height="48" viewBox="0 0 24 24"'), 24);
    expect(flip('width="64" height="48" viewBox="-4 2 32 24"'), 28);
  });

  test('a generated scene, with curves', () {
    final scene = smallScene();
    final list = fittedList(scene);
    final renderer = Renderer();
    final buffer = FrameBuffer();
    print(
      '  map: ${scene.count} draws, bounds ${scene.bounds}, svg transform '
      '${scene.svgTransform}',
    );
    print(
      '  list ctm ${list.ctm}, view ${viewWidth}x$viewHeight @${viewScale}x',
    );
    expect(scene.count, greaterThan(0));

    final frame = renderer.render(
      list,
      viewWidth,
      viewHeight,
      viewScale,
      buffer,
    );
    print(summary(frame));
    for (final entry in frame.entries) {
      print('    $entry');
    }
    checkFrame(frame, scene);
    expect(frame.params.useCurves, isTrue);
    final quad = frame.entries.where(
      (e) => e.type == EntryType.quadEdges || e.type == EntryType.quadMolecules,
    );
    expect(quad.fold(0, (n, e) => n + e.count), greaterThan(0));
    list.dispose();
    scene.dispose();
    renderer.dispose();
    buffer.dispose();
  });

  test('a generated scene, without curves', () {
    final scene = smallScene();
    final list = fittedList(scene)..params = const Params(useCurves: false);
    final frame = Renderer().render(
      list,
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );
    print(summary(frame));
    checkFrame(frame, scene);
    expect(frame.params.useCurves, isFalse);
    // Without curves, every edge is fast. So the scene needs only the
    // opaques, instances, fast edges and fast molecules pipelines.
    final quad = frame.entries.where(
      (e) => e.type == EntryType.quadEdges || e.type == EntryType.quadMolecules,
    );
    expect(quad.fold(0, (n, e) => n + e.count), 0);
  });

  test('frames in flight, and a frame invalidated by the next render into its '
      'buffer', () {
    final scene = smallScene();
    final list = fittedList(scene);
    final renderer = Renderer();
    final buffers = [FrameBuffer(), FrameBuffer()];
    final frames = <Frame>[];
    for (var i = 0; i < 4; i++) {
      // Pans the view, as an app would each frame.
      list.ctm = list.ctm.concat(Transform.translation(i * 10.0, 0));
      frames.add(
        renderer.render(list, viewWidth, viewHeight, viewScale, buffers[i % 2]),
      );
      checkFrame(frames.last, scene);
    }
    expect(() => frames[1].bytes, throwsStateError);
    expect(frames[3].bytes.length, frames[3].size);
    // Once disposed of, as its finalizer would also do, the scene throws on
    // use. The frames' own values stay readable.
    scene.dispose();
    expect(() => scene.count, throwsStateError);
    expect(frames.last.pathsCount, greaterThan(0));
  });

  test("a scene's entries share its P16s, written once (geometry cache)", () {
    final scene = smallScene();
    // Three small copies side by side, so most fills are molecules: small
    // fills drawn from the scene's cached 16-bit points, its P16s.
    Transform at(double x) => scene.svgTransform
        .concat(const Transform.scale(256 / 4000))
        .concat(Transform.translation(x, 100));
    SceneList listOf(int copies) {
      final list = SceneList();
      for (var i = 0; i < copies; i++) {
        list.addScene(scene, at(i * 300.0));
      }
      return list;
    }

    // The base of each molecule's P16s, by entry and by path in the scene.
    const molecule = 1 << 25, outlines = 1 << 29, pathIndexMask = 0xFFFFF;
    Map<(int, int), int> bases(Frame frame) {
      final data = ByteData.sublistView(frame.bytes), out = <(int, int), int>{};
      for (final e in frame.entries.where(
        (e) => e.type == EntryType.instances,
      )) {
        for (var at = e.begin; at < e.end; at += layout.instance) {
          final iz = data.getUint32(at, Endian.little);
          if (iz & (molecule | outlines) != molecule) {
            continue;
          }
          final path = iz & pathIndexMask;
          out[(path ~/ scene.count, path % scene.count)] = data.getInt32(
            at + 20,
            Endian.little,
          );
        }
      }
      return out;
    }

    final renderer = Renderer();
    final one = renderer.render(
      listOf(1),
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );
    final oneBases = bases(one);
    final three = renderer.render(
      listOf(3),
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );
    final threeBases = bases(three);
    print('  ${oneBases.length} molecules, frames ${one.size} & ${three.size}');
    expect(oneBases.length, greaterThan(100));
    for (final MapEntry(key: (entry, path), :value) in threeBases.entries) {
      expect(value, oneBases[(0, path)], reason: 'entry $entry, path $path');
    }
    expect({for (final (entry, _) in threeBases.keys) entry}, {0, 1, 2});
  });

  test('strokes within a power of 2 scale share cached outlines (geometry '
      'cache)', () {
    // An open cubic and a closed path of cubics. The Outliner splits their
    // strokes into pieces, whose count depends on the scale.
    final scene = Scene.fromSvgBytes(
      Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">'
                '<path fill="none" stroke="#000" stroke-width="8" '
                'd="M100,100 C900,100 100,900 900,900"/>'
                '<path fill="none" stroke="#c00" stroke-width="12" '
                'd="M500,200 C700,200 800,300 800,500 C800,700 700,800 500,800 '
                'C300,800 200,700 200,500 C200,300 300,200 500,200 Z"/>'
                '</svg>'
            .codeUnits,
      ),
    );
    // Device scales 1 and 0.8, so both use the cache's outlines at 2^0.
    // Then a skewed entry, and one at scale 1 half outside the view: the
    // Outliner draws both without the cache.
    final ctms = [
      const Transform(0.5, 0, 0, 0.5, 50, 50),
      const Transform(0.4, 0, 0, 0.4, 600, 50),
      const Transform(0.5, 0, 0.25, 0.5, 50, 400),
      const Transform(0.5, 0, 0, 0.5, -250, 400),
    ];
    final list = SceneList();
    for (final ctm in ctms) {
      list.addScene(scene, ctm);
    }
    final frame = Renderer().render(
      list,
      viewWidth,
      viewHeight,
      viewScale,
      FrameBuffer(),
    );

    // Where each outline piece is in the frame, by entry and by path in the
    // scene. A piece holds iz, x0, y0, x2 and y2, then its neighbors' offsets.
    const outlines = 1 << 29, pathIndexMask = 0xFFFFF;
    final data = ByteData.sublistView(frame.bytes);
    final pieces = <(int, int), List<int>>{};
    for (final e in frame.entries.where((e) => e.type == EntryType.instances)) {
      for (var at = e.begin; at < e.end; at += layout.instance) {
        final iz = data.getUint32(at, Endian.little);
        if (iz & outlines == 0) {
          continue;
        }
        final path = iz & pathIndexMask;
        (pieces[(path ~/ scene.count, path % scene.count)] ??= []).add(at);
      }
    }
    double f(int at, int i) => data.getFloat32(at + 4 + 4 * i, Endian.little);
    int short(int at, int i) => data.getInt16(at + 28 + 2 * i, Endian.little);

    for (var path = 0; path < scene.count; path++) {
      final one = pieces[(0, path)]!, small = pieces[(1, path)]!;
      final clipped = pieces[(3, path)]!;
      print(
        '  path $path: ${one.length} pieces, '
        'skewed ${pieces[(2, path)]!.length}, clipped ${clipped.length}',
      );
      // The 0.8 entry's pieces are the scale 1 entry's, scaled. In device
      // pixels, x is p + 100 and 0.8p + 1200, and y is p + 100 and
      // 0.8p + 100.
      expect(small.length, one.length, reason: 'path $path');
      for (var j = 0; j < one.length; j++) {
        for (final i in [0, 4]) {
          expect(
            f(small[j], i),
            closeTo(0.8 * (f(one[j], i) - 100) + 1200, 1e-2),
          );
          expect(
            f(small[j], i + 1),
            closeTo(0.8 * (f(one[j], i + 1) - 100) + 100, 1e-2),
          );
        }
      }
      // The clip leaves some pieces out. Every piece's neighbors belong to
      // its own path.
      expect(clipped.length, inExclusiveRange(0, one.length));
      for (var entry = 0; entry < ctms.length; entry++) {
        final at = pieces[(entry, path)]!;
        for (var j = 0; j < at.length; j++) {
          for (final n in [short(at[j], 0), short(at[j], 1)]) {
            expect(j + n, inInclusiveRange(0, at.length - 1));
          }
        }
      }
    }
    // Unclipped, the closed path's first and last pieces are neighbors.
    final closed = pieces[(0, 1)]!;
    expect(short(closed.first, 0), closed.length - 1);
    expect(short(closed.last, 1), 1 - closed.length);
  });

  // Times a generated scene of 30,000 paths: its import, its first frame and
  // the frames after it.
  test('a 30k path scene, timed', () {
    final svg = mapSvg(30000);
    final watch = Stopwatch()..start();
    final scene = Scene.fromSvgBytes(svg);
    final parse = watch.elapsedMicroseconds;
    final list = fittedList(scene);
    final renderer = Renderer();
    final buffers = [FrameBuffer(), FrameBuffer()];
    watch.reset();
    var frame = renderer.render(
      list,
      viewWidth,
      viewHeight,
      viewScale,
      buffers[0],
    );
    final first = watch.elapsedMicroseconds;
    checkFrame(frame, scene);
    const runs = 20;
    final times = <int>[];
    for (var i = 0; i < runs; i++) {
      watch.reset();
      frame = renderer.render(
        list,
        viewWidth,
        viewHeight,
        viewScale,
        buffers[i % 2],
      );
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    print(
      '  map of 30k paths, ${svg.length} bytes: ${scene.count} draws, parse '
      '${(parse / 1000).toStringAsFixed(1)} ms, '
      'first frame ${(first / 1000).toStringAsFixed(2)} ms (includes prepare), '
      'then median ${(times[runs ~/ 2] / 1000).toStringAsFixed(2)} ms, min '
      '${(times.first / 1000).toStringAsFixed(2)} ms',
    );
    print(summary(frame));
  });

  test("an entry's opacity scales its colors, and only opaque entries have "
      'opaques', () {
    // A red rectangle, big enough to cover whole opaque cells, and a
    // gradient one.
    final scene = Scene.fromSvgBytes(
      Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
                '<defs><linearGradient id="g"><stop offset="0" '
                'stop-color="#2060c0"/><stop offset="1" stop-color="#80e0ff"/>'
                '</linearGradient></defs>'
                '<rect x="10" y="10" width="80" height="40" fill="red"/>'
                '<rect x="10" y="60" width="80" height="30" fill="url(#g)"/>'
                '</svg>'
            .codeUnits,
      ),
    );
    final entry = calloc<Uint8>(SceneList.entrySize);
    final list = SceneList(), renderer = Renderer();
    // The SVG at twice its size, y up.
    const m = Transform(2, 0, 0, -2, 0, 200);

    // Draws the scene at [opacity] into a 200 by 200 view. Returns the
    // rectangles' colors, BGRA, the gradient's strip and the entries' types.
    (List<int>, List<int>, Set<EntryType>) render(double opacity) {
      final bytes = entry.asTypedList(SceneList.entrySize).buffer.asByteData();
      bytes.setInt64(0, scene.address, Endian.host);
      for (final (i, v) in [m.a, m.b, m.c, m.d, m.tx, m.ty].indexed) {
        bytes.setFloat32(SceneList.entryCtm + 4 * i, v, Endian.host);
      }
      for (final (i, v) in [0.0, 0.0, 200.0, 200.0].indexed) {
        bytes.setFloat32(SceneList.entryDeviceClip + 4 * i, v, Endian.host);
      }
      bytes.setFloat32(SceneList.entryOpacity, opacity, Endian.host);
      list.setEntries(entry, 1);
      final frame = renderer.render(list, 200, 200, 1, FrameBuffer());
      final b = frame.bytes;
      return (
        b.sublist(frame.colors, frame.colors + 8),
        frame.texCount == 0
            ? <int>[]
            : b.sublist(
                frame.texStrips,
                frame.texStrips + 4 * layout.colorTextureWidth,
              ),
        {for (final e in frame.entries) e.type},
      );
    }

    final (opaqueColors, opaqueStrip, opaqueTypes) = render(1);
    final (fadedColors, fadedStrip, fadedTypes) = render(0.5);
    final (_, _, hiddenTypes) = render(0);
    print('  opaque $opaqueColors, $opaqueTypes');
    print('  faded $fadedColors, $fadedTypes');
    print('  hidden $hiddenTypes');

    expect(opaqueColors.sublist(0, 4), [0, 0, 255, 255]);
    expect(opaqueTypes, contains(EntryType.opaques));
    // Red at an alpha of 128, premultiplied.
    for (final (i, v) in [0, 0, 128, 128].indexed) {
      expect(fadedColors[i], closeTo(v, 1));
    }
    expect(
      fadedTypes,
      isNot(contains(EntryType.opaques)),
      reason: 'opaques are drawn before what is beneath them',
    );
    expect(opaqueStrip, hasLength(4 * layout.colorTextureWidth));
    expect(fadedStrip, [for (final v in opaqueStrip) (v * 0.5 + 0.5).floor()]);
    expect(
      hiddenTypes.intersection({
        EntryType.opaques,
        EntryType.instances,
        EntryType.blendInstances,
      }),
      isEmpty,
    );

    calloc.free(entry);
    list.dispose();
    scene.dispose();
  });

  test("an entry's color matrix transforms its premultiplied colors and "
      'gradient strips, clamped, and only alpha-keeping ones have opaques', () {
    // The opacity test's red and gradient rectangles.
    final scene = Scene.fromSvgBytes(
      Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
                '<defs><linearGradient id="g"><stop offset="0" '
                'stop-color="#2060c0"/><stop offset="1" stop-color="#80e0ff"/>'
                '</linearGradient></defs>'
                '<rect x="10" y="10" width="80" height="40" fill="red"/>'
                '<rect x="10" y="60" width="80" height="30" fill="url(#g)"/>'
                '</svg>'
            .codeUnits,
      ),
    );
    final entry = calloc<Uint8>(SceneList.entrySize);
    final matrices = calloc<Float>(16);
    final list = SceneList(), renderer = Renderer();
    const m = Transform(2, 0, 0, -2, 0, 200);

    // Draws the scene with [matrix], or with none if null. Its rows map r,
    // g, b and a. Returns the red rectangle's color, BGRA, the gradient's
    // strip and the entries' types.
    (List<int>, List<int>, Set<EntryType>) render(List<double>? matrix) {
      final bytes = entry.asTypedList(SceneList.entrySize).buffer.asByteData();
      bytes.setInt64(0, scene.address, Endian.host);
      for (final (i, v) in [m.a, m.b, m.c, m.d, m.tx, m.ty].indexed) {
        bytes.setFloat32(SceneList.entryCtm + 4 * i, v, Endian.host);
      }
      for (final (i, v) in [0.0, 0.0, 200.0, 200.0].indexed) {
        bytes.setFloat32(SceneList.entryDeviceClip + 4 * i, v, Endian.host);
      }
      bytes
        ..setFloat32(SceneList.entryOpacity, 1, Endian.host)
        ..setUint32(
          SceneList.entryColorMatrix,
          matrix == null ? 0 : 1,
          Endian.host,
        );
      if (matrix != null) {
        matrices.asTypedList(16).setAll(0, matrix);
      }
      list
        ..setColorMatrices(matrices, matrix == null ? 0 : 1)
        ..setEntries(entry, 1);
      final frame = renderer.render(list, 200, 200, 1, FrameBuffer());
      final b = frame.bytes;
      return (
        b.sublist(frame.colors, frame.colors + 4),
        frame.texCount == 0
            ? <int>[]
            : b.sublist(
                frame.texStrips,
                frame.texStrips + 4 * layout.colorTextureWidth,
              ),
        {for (final e in frame.entries) e.type},
      );
    }

    // The matrices: Flame's tint, srcATop with green at an alpha of 0.8.
    // Modulate with white at an alpha of 0.5. Greyscale. And one whose
    // results fall out of range.
    const t = 0.8, s = 1 - t;
    const tint = [
      s, 0.0, 0.0, 0.0, 0.0, s, 0.0, t, 0.0, 0.0, s, 0.0, 0.0, //
      0.0, 0.0, 1.0,
    ];
    const modulate = [
      0.5, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.5, //
      0.0, 0.0, 0.0, 0.0, 0.5,
    ];
    const grey = [
      0.2126, 0.7152, 0.0722, 0.0, 0.2126, 0.7152, 0.0722, 0.0, //
      0.2126, 0.7152, 0.0722, 0.0, 0.0, 0.0, 0.0, 1.0,
    ];
    const bright = [
      2.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -0.5, 0.0, 0.0, 1.0, //
      0.0, 0.0, 0.0, 0.0, 1.0,
    ];
    const identity = [
      1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, //
      0.0, 0.0, 0.0, 0.0, 1.0,
    ];

    // [bgra] transformed by [matrix], clamped and rounded as the core does.
    List<int> transform(List<double> matrix, List<int> bgra) {
      final rgba = [bgra[2], bgra[1], bgra[0], bgra[3]];
      double row(int r) =>
          [for (var c = 0; c < 4; c++) matrix[4 * r + c] * rgba[c]]
              .reduce((a, b) => a + b);
      final a = row(3).clamp(0, 255).toDouble();
      final c = [for (var r = 0; r < 3; r++) row(r).clamp(0, a)];
      return [
        for (final v in [c[2], c[1], c[0], a]) (v + 0.5).floor(),
      ];
    }

    void expectClose(List<int> actual, List<int> expected, String reason) {
      expect(actual, hasLength(expected.length), reason: reason);
      for (var i = 0; i < actual.length; i++) {
        expect(actual[i], closeTo(expected[i], 1), reason: '$reason [$i]');
      }
    }

    final (plain, plainStrip, plainTypes) = render(null);
    expect(plain, [0, 0, 255, 255]);
    expect(plainTypes, contains(EntryType.opaques));
    final (same, sameStrip, sameTypes) = render(identity);
    expect(same, plain);
    expect(sameStrip, plainStrip);
    expect(sameTypes, plainTypes);

    for (final (name, matrix, opaque) in [
      ('tint', tint, true),
      ('modulate', modulate, false),
      ('grey', grey, true),
      ('out of range', bright, true),
    ]) {
      final (color, strip, types) = render(matrix);
      print('  $name $color, $types');
      expectClose(color, transform(matrix, plain), name);
      expectClose(strip, [
        for (var k = 0; k < plainStrip.length; k += 4)
          ...transform(matrix, plainStrip.sublist(k, k + 4)),
      ], '$name strip');
      expect(
        types.contains(EntryType.opaques),
        opaque,
        reason: '$name: only alpha-keeping matrices have opaques',
      );
    }
    // Red tinted green at 0.8: 0.2 red, 0.8 green, opaque.
    expectClose(render(tint).$1, [0, 204, 51, 255], 'tint');
    // Clamped: red doubled to 255, green offset below 0.
    expectClose(render(bright).$1, [0, 0, 255, 255], 'clamped');

    final (_, _, clearTypes) = render(List.filled(16, 0));
    expect(
      clearTypes.intersection({
        EntryType.opaques,
        EntryType.instances,
        EntryType.blendInstances,
      }),
      isEmpty,
      reason: 'a matrix that clears alpha skips the entry',
    );

    calloc
      ..free(entry)
      ..free(matrices);
    list.dispose();
    scene.dispose();
  });
}
