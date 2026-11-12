import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'core.dart' as ra;

/// A mesh's GPU buffers, uploaded once: its vertices, its indices in paint
/// order, and its paints, as ra_mesh.glsl reads them.
///
/// The buffers are hostVisible, as Flutter GPU can't copy into devicePrivate
/// buffers. The scene keeps them for its lifetime.
class MeshBuffers._(
  final gpu.BufferView vertices,
  final gpu.BufferView indices,
  final gpu.IndexType indexType,
  final int indexCount,
  final gpu.Texture paints,

  /// As [ra.Mesh.isOpaque].
  final bool opaque,

  /// Whether any of the mesh's paths has a gradient.
  ///
  /// Only then do instances with a color transform need [MeshGpu.draw]'s
  /// `colorTransform`.
  final bool gradients,

  /// Whether the vertices hold stroke offsets ([ra.Mesh.vertexFloats]).
  final bool stroked,

  /// Whether the vertices also hold a glow ([ra.Mesh.vertexFloats]).
  final bool glow,

  /// As [ra.Mesh.stripIndices], with the same [indexType].
  final gpu.BufferView? stripIndices,

  /// The number of [stripIndices].
  final int stripIndexCount,
) {
  /// Uploads [mesh], or returns null if it has no triangles.
  static MeshBuffers? upload(ra.Mesh mesh) {
    if (mesh.indexCount == 0) {
      return null;
    }
    final context = gpu.gpuContext;
    gpu.BufferView view(TypedData data) {
      final buffer = context.createDeviceBufferWithCopy(
        ByteData.sublistView(data),
      );
      return gpu.BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: buffer.sizeInBytes,
      );
    }

    final indices = mesh.indices, strips = mesh.stripIndices;
    return MeshBuffers._(
      view(mesh.vertices),
      view(indices),
      indices is Uint16List ? gpu.IndexType.int16 : gpu.IndexType.int32,
      mesh.indexCount,
      _paints(mesh),
      mesh.isOpaque,
      mesh.stops.isNotEmpty,
      mesh.vertexFloats >= 5,
      mesh.vertexFloats == 6,
      strips == null ? null : view(strips),
      strips == null ? 0 : strips.lengthInBytes ~/ strips.elementSizeInBytes,
    );
  }

  /// The log2 of the paints texture's longest row, 1024 texels, as
  /// kPaintWidthLog2 in ra_mesh.glsl.
  static const paintWidthLog2 = 10;

  /// The paints texture: each path's 3 texels, then each stop's 2, as
  /// ra_mesh.glsl reads them.
  static gpu.Texture _paints(ra.Mesh mesh) {
    final paths = mesh.paths, stops = mesh.stops;
    final stopTexel = 3 * paths.length,
        texels = stopTexel + 2 * stops.length ~/ 5;
    const rowTexels = 1 << paintWidthLog2;
    final width = texels < rowTexels ? texels : rowTexels;
    final height = (texels + rowTexels - 1) >> paintWidthLog2;
    final data = Float32List(4 * width * height);
    for (final (i, p) in paths.indexed) {
      final o = 12 * i;
      if (p.paint == ra.MeshPaint.color) {
        data
          ..setAll(o, p.color)
          ..[o + 4] = p.halfWidth
          ..[o + 5] = p.isHalo ? 1 : 0;
        continue;
      }
      final g = p.gradient;
      data
        ..[o] = p.paint == ra.MeshPaint.radialGradient ? 1 : 0
        ..[o + 1] = p.halfWidth
        ..[o + 4] = g.a
        ..[o + 5] = g.b
        ..[o + 6] = g.c
        ..[o + 7] = g.d
        ..[o + 8] = g.tx
        ..[o + 9] = g.ty
        ..[o + 10] = (stopTexel + 2 * p.stopBegin).toDouble()
        ..[o + 11] = p.stopCount.toDouble();
    }
    for (var k = 0; 5 * k < stops.length; k++) {
      final o = 4 * (stopTexel + 2 * k);
      data
        ..[o] = stops[5 * k]
        ..setRange(o + 4, o + 8, stops, 5 * k + 1);
    }
    return gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r32g32b32a32Float,
      enableRenderTargetUsage: false,
    )..overwrite(ByteData.sublistView(data));
  }
}

/// A run's target in the pool of one frame in flight, and its image.
class MeshTarget() {
  gpu.Texture? texture;
  ui.Image? image;
}

/// The buffer for one frame in flight's instance records.
///
/// The buffer is hostVisible, and reused unless the GPU may still read it.
class MeshInstances() {
  gpu.DeviceBuffer? buffer;

  /// Whether the GPU may still read [buffer].
  bool _busy = false;
}

/// Draws meshes with Flutter GPU.
///
/// Each run is one render pass into its own target. The target is
/// multisampled with [samples] where offscreen MSAA is supported, as in
/// flame_3d, else aliased. Each draw is one mesh, instanced. It reads its
/// instances from a [gpu.VertexStepMode.instance] buffer. GPUs draw instances
/// in order, one after another, so paint order holds.
class MeshGpu(gpu.ShaderLibrary library, int samples) {
  /// Loads the mesh shaders from [library] and makes their pipelines, with
  /// [samples] per pixel where offscreen MSAA is supported.
  this
    : vertex = library['RaMeshVertex']!,
      strokedVertex = library['RaMeshStrokedVertex']!,
      glowVertex = library['RaMeshGlowVertex']!,
      fragment = library['RaMeshFragment']!,
      transformedFragment = library['RaMeshTransformedFragment']!,
      glowFragment = library['RaMeshGlowFragment']!,
      samples = gpu.gpuContext.doesSupportOffscreenMSAA ? samples : 1 {
    gpu.RenderPipeline create(gpu.Shader shader, {required bool stroked}) =>
        context.createRenderPipeline(
          stroked ? strokedVertex : vertex,
          shader,
          vertexLayout: _layout(stroked: stroked),
        );
    pipeline = create(fragment, stroked: false);
    transformedPipeline = create(transformedFragment, stroked: false);
    strokedPipeline = create(fragment, stroked: true);
    strokedTransformedPipeline = create(transformedFragment, stroked: true);
  }

  /// The floats in an instance record: the transform's 3 rows, a c tx, b d ty
  /// and g h i, each padded to 4, then the color transform's 4 rows, scaled by
  /// the opacity.
  static const instanceFloats = 28, instanceBytes = 4 * instanceFloats;

  /// The step that targets are sized in: the step of the mesh renderer's
  /// `AtlasPages`.
  ///
  /// So runs that change size a little, as moving entries make them, keep
  /// their targets.
  static const targetStep = 64;

  /// Targets' samples per pixel, 1 or 4, as Flutter GPU allows: 1 unless
  /// offscreen MSAA is supported.
  final int samples;

  final gpu.GpuContext context = gpu.gpuContext;
  late final gpu.HostBuffer hostBuffer = context.createHostBuffer();
  final gpu.Shader vertex,
      strokedVertex,
      glowVertex,
      fragment,
      transformedFragment,
      glowFragment;
  late final gpu.RenderPipeline pipeline,
      transformedPipeline,
      strokedPipeline,
      strokedTransformedPipeline;

  /// The pipeline for meshes with a glow, made at the first one's draw, so
  /// games without any don't pay for it.
  ///
  /// It has no variant for color transforms, as only gradients need one, and a
  /// glow's paths are all colors.
  late final gpu.RenderPipeline glowPipeline = context.createRenderPipeline(
    glowVertex,
    glowFragment,
    vertexLayout: _layout(stroked: true, glow: true),
  );

  /// The targets' format, as GpuRenderer.colorFormat: the context's default,
  /// or b8g8r8a8UNormInt where it reports unknown.
  final gpu.PixelFormat colorFormat =
      gpu.gpuContext.defaultColorFormat == gpu.PixelFormat.unknown
      ? gpu.PixelFormat.b8g8r8a8UNormInt
      : gpu.gpuContext.defaultColorFormat;

  /// Whether targets are multisampled.
  bool get multisampled => samples > 1;

  /// A stroke's least half width on screen, in pixels.
  ///
  /// 4x MSAA's samples lie in rows at most 0.56 of a pixel apart, at slopes of
  /// 1/2 and 2. A thinner line can miss all of a pixel's samples. Aliased, a
  /// line must be a pixel wide to reach the center of every pixel it crosses.
  double get leastHalfWidth => multisampled ? 0.28 : 0.5;

  /// How many times targets have been allocated.
  int resizes = 0;

  // The multisampled textures, by size. All targets of a size share one, as
  // each is used only within a render pass, and passes run in order.
  final Map<(int, int), gpu.Texture> _multisampledTextures = {};

  /// Makes [target]'s texture [width] x [height], the size of its run's page.
  ///
  /// It reallocates the texture if its size differs, larger or smaller.
  void fit(MeshTarget target, int width, int height) {
    final texture = target.texture;
    if (texture != null && texture.width == width && texture.height == height) {
      return;
    }
    target.texture = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: colorFormat,
    );
    // Write the texture once, which puts it in a defined layout before its
    // first render pass, as GpuRenderer does with its targets. The bytes come
    // from the texture's own size, as a format's pixels may not be 4 bytes.
    target.texture!.overwrite(
      ByteData(target.texture!.getBaseMipLevelSizeInBytes()),
    );
    // Replace the image, as the GPU renderer does for its pages.
    target.image?.dispose();
    target.image = target.texture!.asImage();
    resizes++;
  }

  /// Drops the multisampled textures whose size no target in [targets] has.
  void releaseMultisampled(Iterable<MeshTarget> targets) {
    final sizes = {
      for (final t in targets)
        if (t.texture case final texture?) (texture.width, texture.height),
    };
    _multisampledTextures.removeWhere((size, _) => !sizes.contains(size));
  }

  /// The bytes the multisampled textures hold, estimated from their format.
  int get multisampledBytes {
    var n = 0;
    for (final texture in _multisampledTextures.values) {
      n += texture.getBaseMipLevelSizeInBytes() * samples;
    }
    return n;
  }

  /// Begins a frame, whose uniforms share the host buffer, by resetting it.
  void beginFrame() => hostBuffer.reset();

  /// Uploads [count] instance records from [records] into [instances]'
  /// buffer, and returns the buffer.
  ///
  /// It makes a new buffer if the old one is too small, or if the GPU may
  /// still read it.
  gpu.DeviceBuffer upload(
    MeshInstances instances,
    Float32List records,
    int count,
  ) {
    final bytes = count * instanceBytes;
    var buffer = instances.buffer;
    if (buffer == null || buffer.sizeInBytes < bytes || instances._busy) {
      buffer = instances.buffer = context.createDeviceBuffer(
        gpu.StorageMode.hostVisible,
        bytes * 4 ~/ 3 + instanceBytes,
      );
      instances._busy = false;
    }
    if (!buffer.overwrite(
      ByteData.sublistView(records, 0, count * instanceFloats),
    )) {
      throw StateError('Failed to upload $count mesh instances');
    }
    return buffer;
  }

  // The pass being encoded, its command buffer, its FrameInfo uniform and its
  // instance records.
  gpu.CommandBuffer? _commandBuffer;
  late gpu.RenderPass _pass;
  late gpu.BufferView _info;
  late gpu.DeviceBuffer _instances;

  /// Begins [target]'s render pass, which clears it, with the instance records
  /// in [instances].
  void beginPass(MeshTarget target, gpu.DeviceBuffer instances) {
    final texture = target.texture!, w = texture.width, h = texture.height;
    final attachment = multisampled
        ? gpu.ColorAttachment(
            texture: _multisampledTextures[(w, h)] ??= context.createTexture(
              gpu.StorageMode.deviceTransient,
              w,
              h,
              format: colorFormat,
              sampleCount: samples,
              enableShaderReadUsage: false,
            ),
            resolveTexture: texture,
            storeAction: gpu.StoreAction.multisampleResolve,
          )
        : gpu.ColorAttachment(texture: texture);
    final commandBuffer = _commandBuffer = context.createCommandBuffer();
    _pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(attachment),
    );
    _info = hostBuffer.emplace(
      ByteData.sublistView(
        Float32List.fromList([w * 1.0, h * 1.0, leastHalfWidth, 0]),
      ),
    );
    _instances = instances;
  }

  /// Draws [mesh] once per instance, for [count] instances from [first].
  ///
  /// With [blend], it draws source over. Without, it replaces what's below,
  /// for opaque instances of an opaque mesh. Tile-based GPUs then shade only
  /// the fragments on top. [strips] draws [mesh]'s strip indices, for
  /// instances that keep its alpha.
  ///
  /// [colorTransform] holds the color transform rows that the instances share,
  /// scaled by their opacity. Their gradients' fragments read it as a uniform.
  /// Without it, they read only the instances' opacity.
  void draw(
    MeshBuffers mesh,
    int first,
    int count, {
    required bool blend,
    bool strips = false,
    Float32List? colorTransform,
  }) {
    final transformed = colorTransform != null;
    final shader = transformed ? transformedFragment : fragment;
    final vertexShader = mesh.glow
        ? glowVertex
        : (mesh.stroked ? strokedVertex : vertex);
    // A pass's bindings persist across draws, and binding a slot again doesn't
    // replace the earlier binding, so each draw clears them first.
    final pass = _pass
      ..clearBindings()
      ..bindPipeline(
        mesh.glow
            ? glowPipeline
            : mesh.stroked
            ? (transformed ? strokedTransformedPipeline : strokedPipeline)
            : (transformed ? transformedPipeline : pipeline),
      )
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setColorBlendEnable(blend);
    if (blend) {
      pass.setColorBlendEquation(_sourceOver);
    }
    pass
      ..bindVertexBuffer(mesh.vertices)
      ..bindVertexBuffer(
        gpu.BufferView(
          _instances,
          offsetInBytes: first * instanceBytes,
          lengthInBytes: count * instanceBytes,
        ),
        slot: 1,
      )
      ..bindIndexBuffer(
        strips ? mesh.stripIndices! : mesh.indices,
        mesh.indexType,
      )
      ..bindUniform(vertexShader.getUniformSlot('FrameInfo'), _info)
      ..bindTexture(vertexShader.getUniformSlot('paints'), mesh.paints);
    if (!mesh.glow) {
      pass.bindTexture(shader.getUniformSlot('paints'), mesh.paints);
    }
    if (colorTransform != null) {
      pass.bindUniform(
        shader.getUniformSlot('TransformInfo'),
        hostBuffer.emplace(ByteData.sublistView(colorTransform)),
      );
    }
    pass.drawIndexed(
      strips ? mesh.stripIndexCount : mesh.indexCount,
      instanceCount: count,
    );
  }

  /// Submits the pass.
  ///
  /// For a frame's [last] pass, it marks [instances]' buffer busy until the
  /// GPU has run the pass. Passes run in order, so the earlier ones have run
  /// too by then.
  void endPass(MeshInstances instances, {required bool last}) {
    final commandBuffer = _commandBuffer!;
    _commandBuffer = null;
    if (!last) {
      return commandBuffer.submit();
    }
    instances._busy = true;
    final buffer = instances.buffer;
    commandBuffer.submit(
      completionCallback: (_) {
        if (identical(instances.buffer, buffer)) {
          instances._busy = false;
        }
      },
    );
  }

  /// Source over, for premultiplied colors.
  static final _sourceOver = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );

  // A vertex is 12 bytes: x, y and its path. A mesh with strokes adds an
  // offset, for 20 bytes, and one with a glow then adds the glow, for 24.
  static gpu.VertexLayout _layout({required bool stroked, bool glow = false}) =>
      gpu.VertexLayout(
        buffers: [
          gpu.VertexBuffer(
            strideInBytes: glow ? 24 : (stroked ? 20 : 12),
            attributes: [
              const gpu.VertexAttribute(
                name: 'position',
                format: gpu.VertexFormat.float32x2,
              ),
              const gpu.VertexAttribute(
                name: 'path',
                format: gpu.VertexFormat.float32,
                offsetInBytes: 8,
              ),
              if (stroked)
                const gpu.VertexAttribute(
                  name: 'offset',
                  format: gpu.VertexFormat.float32x2,
                  offsetInBytes: 12,
                ),
              if (glow)
                const gpu.VertexAttribute(
                  name: 'glow',
                  format: gpu.VertexFormat.float32,
                  offsetInBytes: 20,
                ),
            ],
          ),
          const gpu.VertexBuffer(
            strideInBytes: instanceBytes,
            stepMode: gpu.VertexStepMode.instance,
            attributes: [
              gpu.VertexAttribute(
                name: 'r0',
                format: gpu.VertexFormat.float32x3,
              ),
              gpu.VertexAttribute(
                name: 'r1',
                format: gpu.VertexFormat.float32x3,
                offsetInBytes: 16,
              ),
              gpu.VertexAttribute(
                name: 'r2',
                format: gpu.VertexFormat.float32x3,
                offsetInBytes: 32,
              ),
              gpu.VertexAttribute(
                name: 'm0',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 48,
              ),
              gpu.VertexAttribute(
                name: 'm1',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 64,
              ),
              gpu.VertexAttribute(
                name: 'm2',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 80,
              ),
              gpu.VertexAttribute(
                name: 'm3',
                format: gpu.VertexFormat.float32x4,
                offsetInBytes: 96,
              ),
            ],
          ),
        ],
      );
}
