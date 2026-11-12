// Bindings for src/ra_capi.h, written by hand. The structs mirror the C ones.
// In C, static_asserts check those against the core's types.
// ignore_for_file: non_constant_identifier_names
// The Opaque and Struct subclasses mirror C types, and Dart never constructs
// them. So they keep their plain declarations.
// ignore_for_file: use_primary_constructors

import 'dart:ffi';

final class RaSceneHandle extends Opaque {}

final class RaListHandle extends Opaque {}

final class RaRendererHandle extends Opaque {}

final class RaFrameBufferHandle extends Opaque {}

final class RaMeshHandle extends Opaque {}

final class RaTransform extends Struct {
  @Float()
  external double a;
  @Float()
  external double b;
  @Float()
  external double c;
  @Float()
  external double d;
  @Float()
  external double tx;
  @Float()
  external double ty;
}

final class RaBounds extends Struct {
  @Float()
  external double lx;
  @Float()
  external double ly;
  @Float()
  external double ux;
  @Float()
  external double uy;
}

final class RaParams extends Struct {
  @Bool()
  external bool useClips;
  @Bool()
  external bool useCurves;
  @Bool()
  external bool showOpaques;
  @Bool()
  external bool showOutlines;
  @Uint8()
  external int clearB;
  @Uint8()
  external int clearG;
  @Uint8()
  external int clearR;
  @Uint8()
  external int clearA;
}

final class RaEntry extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int pad;
  @Uint64()
  external int begin;
  @Uint64()
  external int end;
}

final class RaFrame extends Struct {
  external Pointer<Uint8> base;
  @Uint64()
  external int size;
  external Pointer<RaEntry> entries;
  @Uint64()
  external int entryCount;
  @Uint64()
  external int colors;
  @Uint64()
  external int paths;
  @Uint64()
  external int texStrips;
  @Uint64()
  external int p16s;
  @Uint64()
  external int pathsCount;
  @Uint64()
  external int texCount;
  @Uint64()
  external int headerSize;
  external RaParams params;
}

final class RaLayout extends Struct {
  @Uint32()
  external int color;
  @Uint32()
  external int pathData;
  @Uint32()
  external int opaque;
  @Uint32()
  external int instance;
  @Uint32()
  external int edge;
  @Uint32()
  external int segment;
  @Uint32()
  external int point16;
  @Uint32()
  external int entry;
  @Uint32()
  external int colorTextureWidth;
  @Uint32()
  external int moleculesHeight;
  @Uint32()
  external int fastSegments;
  @Uint32()
  external int stripHeight;
}

@Native<RaLayout Function()>()
external RaLayout ra_layout();

@Native<Pointer<RaSceneHandle> Function(Pointer<Char>, Pointer<RaTransform>)>()
external Pointer<RaSceneHandle> ra_scene_from_svg(
  Pointer<Char> path,
  Pointer<RaTransform> ctm,
);

@Native<
  Pointer<RaSceneHandle> Function(Pointer<Char>, Uint64, Pointer<RaTransform>)
>()
external Pointer<RaSceneHandle> ra_scene_from_svg_data(
  Pointer<Char> data,
  int length,
  Pointer<RaTransform> ctm,
);

@Native<Void Function(Pointer<RaSceneHandle>)>()
external void ra_scene_release(Pointer<RaSceneHandle> scene);

@Native<Uint64 Function(Pointer<RaSceneHandle>)>(isLeaf: true)
external int ra_scene_count(Pointer<RaSceneHandle> scene);

@Native<RaBounds Function(Pointer<RaSceneHandle>)>()
external RaBounds ra_scene_bounds(Pointer<RaSceneHandle> scene);

@Native<RaBounds Function(Pointer<RaSceneHandle>)>()
external RaBounds ra_scene_svg_bounds(Pointer<RaSceneHandle> scene);

@Native<Pointer<RaListHandle> Function()>()
external Pointer<RaListHandle> ra_list_create();

@Native<Void Function(Pointer<RaListHandle>)>()
external void ra_list_release(Pointer<RaListHandle> list);

@Native<
  Void Function(Pointer<RaListHandle>, Pointer<RaSceneHandle>, RaTransform)
>()
external void ra_list_add_scene(
  Pointer<RaListHandle> list,
  Pointer<RaSceneHandle> scene,
  RaTransform ctm,
);

@Native<Void Function(Pointer<RaListHandle>, RaTransform)>(isLeaf: true)
external void ra_list_set_ctm(Pointer<RaListHandle> list, RaTransform ctm);

@Native<Void Function(Pointer<RaListHandle>, RaParams)>(isLeaf: true)
external void ra_list_set_params(Pointer<RaListHandle> list, RaParams params);

@Native<RaParams Function(Pointer<RaListHandle>)>(isLeaf: true)
external RaParams ra_list_params(Pointer<RaListHandle> list);

@Native<RaBounds Function(Pointer<RaListHandle>)>()
external RaBounds ra_list_bounds(Pointer<RaListHandle> list);

/// Sets the list's color matrices, which the next entries refer to.
///
/// [matrices] holds [count] 4 x 4 matrices, 16 floats each. An entry picks
/// one at [listEntryColorMatrix].
@Native<Void Function(Pointer<RaListHandle>, Pointer<Float>, Uint64)>(
  isLeaf: true,
)
external void ra_list_set_color_matrices(
  Pointer<RaListHandle> list,
  Pointer<Float> matrices,
  int count,
);

/// Replaces the list's scenes with [entries], in order.
///
/// [entries] holds [count] RaListEntry structs of [listEntrySize] bytes each.
/// Each one holds a scene pointer, a RaTransform and a RaBounds, the clip in
/// device pixels. Then come a float opacity and a uint32 color matrix: 0 for
/// none, or 1 + the matrix's index in the list's color matrices.
@Native<Void Function(Pointer<RaListHandle>, Pointer<Uint8>, Uint64)>(
  isLeaf: true,
)
external void ra_list_set_entries(
  Pointer<RaListHandle> list,
  Pointer<Uint8> entries,
  int count,
);

const listEntrySize = 56,
    listEntryCtm = 8,
    listEntryDeviceClip = 32,
    listEntryOpacity = 48,
    listEntryColorMatrix = 52;

@Native<Pointer<RaRendererHandle> Function()>()
external Pointer<RaRendererHandle> ra_renderer_create();

@Native<Void Function(Pointer<RaRendererHandle>)>()
external void ra_renderer_release(Pointer<RaRendererHandle> renderer);

@Native<Pointer<RaFrameBufferHandle> Function()>()
external Pointer<RaFrameBufferHandle> ra_frame_buffer_create();

@Native<Void Function(Pointer<RaFrameBufferHandle>)>()
external void ra_frame_buffer_release(Pointer<RaFrameBufferHandle> buffer);

@Native<
  RaFrame Function(
    Pointer<RaRendererHandle>,
    Pointer<RaListHandle>,
    Float,
    Float,
    Float,
    Pointer<RaFrameBufferHandle>,
  )
>()
external RaFrame ra_render(
  Pointer<RaRendererHandle> renderer,
  Pointer<RaListHandle> list,
  double w,
  double h,
  double scale,
  Pointer<RaFrameBufferHandle> buffer,
);

final class RaMeshPath extends Struct {
  @Uint32()
  external int type;
  @Uint32()
  external int indexBegin;
  @Uint32()
  external int indexCount;
  @Uint32()
  external int stopBegin;
  @Uint32()
  external int stopCount;
  @Float()
  external double r;
  @Float()
  external double g;
  @Float()
  external double b;
  @Float()
  external double a;
  external RaTransform gradient;
  @Float()
  external double halfWidth;
  @Uint32()
  external int halo;
}

final class RaMeshData extends Struct {
  external Pointer<Float> vertices;
  @Uint64()
  external int vertexCount;
  external Pointer<Void> indices;
  @Uint64()
  external int indexCount;
  @Uint32()
  external int indexSize;
  @Uint32()
  external int vertexFloats;
  external Pointer<Void> stripIndices;
  @Uint64()
  external int stripIndexCount;
  external Pointer<RaMeshPath> paths;
  @Uint64()
  external int pathCount;

  /// The gradients' RaMeshStop structs: 5 floats each, an offset, then r, g,
  /// b and a.
  external Pointer<Float> stops;
  @Uint64()
  external int stopCount;
  external RaBounds bounds;
  external RaBounds svgBounds;
}

@Native<Pointer<RaMeshHandle> Function(Pointer<Char>, Uint64, Float)>()
external Pointer<RaMeshHandle> ra_mesh_from_svg_data(
  Pointer<Char> data,
  int length,
  double maxSize,
);

@Native<RaMeshData Function(Pointer<RaMeshHandle>)>(isLeaf: true)
external RaMeshData ra_mesh_data(Pointer<RaMeshHandle> mesh);

@Native<Void Function(Pointer<RaMeshHandle>)>()
external void ra_mesh_release(Pointer<RaMeshHandle> mesh);

final class RaContours extends Struct {
  external Pointer<Float> points;
  external Pointer<Uint32> pointCounts;
  external Pointer<Uint8> closed;
  external Pointer<Uint32> contourCounts;
  @Uint64()
  external int pathCount;
}

final class RaPathDraw extends Struct {
  @Uint32()
  external int path;
  @Uint32()
  external int color;
  @Float()
  external double strokeWidth;
  @Float()
  external double miterLimit;
  @Uint8()
  external int cap;
  @Uint8()
  external int join;
  @Uint8()
  external int evenOdd;
  @Uint8()
  external int hairline;
}

@Native<
  Pointer<RaSceneHandle> Function(
    Pointer<RaContours>,
    Pointer<RaPathDraw>,
    Uint64,
    RaBounds,
  )
>()
external Pointer<RaSceneHandle> ra_scene_from_paths(
  Pointer<RaContours> contours,
  Pointer<RaPathDraw> draws,
  int drawCount,
  RaBounds viewBox,
);

final class RaGlow extends Struct {
  @Float()
  external double radius;
  @Float()
  external double strength;
  @Uint32()
  external int color;
  @Uint8()
  external int hasColor;
  @Uint8()
  external int inWidths;
}

@Native<
  Pointer<RaMeshHandle> Function(
    Pointer<RaContours>,
    Pointer<RaPathDraw>,
    Uint64,
    RaBounds,
    Float,
    Pointer<RaGlow>,
  )
>()
external Pointer<RaMeshHandle> ra_mesh_from_paths(
  Pointer<RaContours> contours,
  Pointer<RaPathDraw> draws,
  int drawCount,
  RaBounds viewBox,
  double tolerance,
  Pointer<RaGlow> glow,
);
