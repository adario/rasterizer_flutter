import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'core.dart' as ra;

import 'package:vector_math/vector_math.dart' as vm;

/// Draws the core's frames with Flutter GPU.
///
/// It does what the draw loop of the original Rasterizer's RasterizerLayer
/// does with Metal (https://github.com/mindbrix/Rasterizer), and its shaders
/// port that project's Shaders.metal. It draws opaques, instances, and fast
/// and quad edges and molecules, so frames written with useCurves true or
/// false. Frames with clip masks or blend instances throw, as SVGs have none.
///
/// Its callers own the textures. Each frame in flight needs its own
/// [RenderTargets], as a frame's image shows while later frames render, and
/// the GPU may still read its textures. The [SharedTargets], depth and
/// accumulation, are only used within a frame's command buffers, so frames in
/// flight can share them.
///
/// Edges' coverage accumulates in [accumulationFormat]: r32Float, or
/// r16g16b16a16Float where the OpenGL ES self-test found that r32Float can't
/// be blended into (RasterizerGpu.initialize).
class GpuRenderer(
  gpu.ShaderLibrary library, {
  final gpu.PixelFormat accumulationFormat = gpu.PixelFormat.r32Float,
}) {
  this
    : opaquesVertex = library['RaOpaquesVertex']!,
      opaquesFragment = library['RaOpaquesFragment']!,
      edgesVertex = library['RaEdgesVertex']!,
      fastEdgesFragment = library['RaFastEdgesFragment']!,
      fastMoleculesVertex = library['RaFastMoleculesVertex']!,
      fastMoleculesFragment = library['RaFastMoleculesFragment']!,
      quadEdgesFragment = library['RaQuadEdgesFragment']!,
      quadMoleculesVertex = library['RaQuadMoleculesVertex']!,
      quadMoleculesFragment = library['RaQuadMoleculesFragment']!,
      instancesVertex = library['RaInstancesVertex']!,
      instancesFragment = library['RaInstancesFragment']!,
      clearVertex = library['RaClearVertex']!,
      clearFragment = library['RaClearFragment']! {
    opaquesPipeline = context.createRenderPipeline(
      opaquesVertex,
      opaquesFragment,
    );
    fastEdgesPipeline = context.createRenderPipeline(
      edgesVertex,
      fastEdgesFragment,
    );
    fastMoleculesPipeline = context.createRenderPipeline(
      fastMoleculesVertex,
      fastMoleculesFragment,
    );
    quadEdgesPipeline = context.createRenderPipeline(
      edgesVertex,
      quadEdgesFragment,
    );
    quadMoleculesPipeline = context.createRenderPipeline(
      quadMoleculesVertex,
      quadMoleculesFragment,
    );
    instancesPipeline = context.createRenderPipeline(
      instancesVertex,
      instancesFragment,
    );
    clearPipeline = context.createRenderPipeline(clearVertex, clearFragment);
  }

  /// The base-2 log of the data texture's width in texels, as kDataWidthLog2
  /// in ra_defs.glsl.
  static const dataWidthLog2 = 12;

  /// The bytes in a row of the data texture, 16 per texel.
  static const dataRowBytes = 16 << dataWidthLog2;

  final gpu.GpuContext context = gpu.gpuContext;
  late final gpu.HostBuffer hostBuffer = context.createHostBuffer();

  /// The targets' format: the context's default, read as the renderer is
  /// made.
  ///
  /// A context that reports PixelFormat.unknown, which texture creation
  /// rejects, gets b8g8r8a8UNormInt instead, Metal's default.
  final gpu.PixelFormat colorFormat =
      gpu.gpuContext.defaultColorFormat == gpu.PixelFormat.unknown
      ? gpu.PixelFormat.b8g8r8a8UNormInt
      : gpu.gpuContext.defaultColorFormat;

  /// The depth attachment's format: the context's default, read as
  /// [colorFormat] is.
  ///
  /// That's d32FloatS8UInt on Metal, and d24UnormS8Uint on OpenGL ES, whose
  /// backend doesn't map d32FloatS8UInt. A context that reports
  /// PixelFormat.unknown gets d32FloatS8UInt. Depths are
  /// 0.1 * (path index + 1) / path count, so 24 bits tell over a million paths
  /// apart.
  final gpu.PixelFormat depthFormat =
      gpu.gpuContext.defaultDepthStencilFormat == gpu.PixelFormat.unknown
      ? gpu.PixelFormat.d32FloatS8UInt
      : gpu.gpuContext.defaultDepthStencilFormat;

  final gpu.Shader opaquesVertex,
      opaquesFragment,
      edgesVertex,
      fastEdgesFragment;
  final gpu.Shader fastMoleculesVertex,
      fastMoleculesFragment,
      quadEdgesFragment,
      quadMoleculesVertex,
      quadMoleculesFragment;
  final gpu.Shader instancesVertex, instancesFragment;
  // A solid quad that covers the target, to clear it.
  final gpu.Shader clearVertex, clearFragment;
  late final gpu.RenderPipeline opaquesPipeline,
      fastEdgesPipeline,
      fastMoleculesPipeline,
      quadEdgesPipeline;
  late final gpu.RenderPipeline quadMoleculesPipeline,
      instancesPipeline,
      clearPipeline;

  // Every draw reads its quad's unit corners from this 4-vertex triangle
  // strip. Vertex shaders need an input: a shader bundle with a vertex shader
  // that has none crashes Flutter GPU.
  late final gpu.BufferView corners = () {
    final buffer = context.createDeviceBufferWithCopy(
      ByteData.sublistView(Float32List.fromList([0, 0, 1, 0, 0, 1, 1, 1])),
    );
    return gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
  }();

  /// The last [render]'s upload and encode times, in microseconds.
  int uploadMicros = 0, encodeMicros = 0;

  /// Begins a frame of one or more [render]s.
  ///
  /// Their uniforms share the host buffer, which this resets.
  void beginFrame() => hostBuffer.reset();

  /// Draws [frame] into [slot]'s target, and returns the target.
  ///
  /// The core wrote [frame] for a [width] x [height] view in device pixels,
  /// and the target has that size. [shared] holds the depth and accumulation
  /// textures. The target's texture is reused when [slot] is rendered into
  /// again.
  gpu.Texture render(
    ra.Frame frame,
    RenderTargets slot,
    SharedTargets shared,
    int width,
    int height,
  ) {
    final watch = Stopwatch()..start();
    _ensureTargets(slot, shared, width, height);
    final (data, colors) = _upload(slot, frame);
    uploadMicros = watch.elapsedMicroseconds;
    watch.reset();

    final target = slot.target!,
        depth = shared.depth!,
        accumulation = shared.accumulation!;
    final params = frame.params;
    final flags =
        (params.useCurves ? 1 : 0) |
        (params.showOpaques ? 2 : 0) |
        // Clips are always on: see ra.Params.
        4;
    final pathsWord = frame.paths ~/ 4, p16sWord = frame.p16s ~/ 4;
    final clear = params.clearColor;
    final clearColor = [
      (clear >> 16 & 0xFF) / 255,
      (clear >> 8 & 0xFF) / 255,
      (clear & 0xFF) / 255,
      (clear >> 24 & 0xFF) / 255,
    ];

    // A new render pass begins when the kind of pass changes, and for a new
    // group's edges. RenderPass has no end(), so a pass's encoder stays open
    // until its command buffer is submitted. So each pass has its own command
    // buffer, submitted in order.
    //
    // Impeller's Vulkan backend reuses a texture's first render pass, with its
    // load actions, for all its later ones. It also begins every depth
    // attachment in an undefined layout. So drawable passes always load the
    // target, and the first one draws the clear color over it. Only opaques
    // write depth, so each drawable pass clears the depth, then redraws the
    // opaques so far into it, depth only.
    gpu.CommandBuffer? commandBuffer;
    late gpu.RenderPass pass;
    _PassKind? passKind;
    var cleared = false;
    var edgesRead = true;
    final opaques = <(ra.Entry, int, int)>[];

    // Draws [entry]'s instances with [pipeline]. [fragmentBindings] binds the
    // fragment shader's textures, after the pipeline. A pass's bindings
    // persist across draws, and binding a slot again doesn't replace the
    // earlier binding, so each draw clears them first.
    void draw(
      gpu.RenderPipeline pipeline,
      gpu.Shader vertex,
      ra.Entry entry,
      int segmentsWord,
      int instancesWord, [
      void Function()? fragmentBindings,
    ]) {
      pass.clearBindings();
      pass.bindPipeline(pipeline);
      pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
      pass.bindVertexBuffer(corners);
      pass.bindTexture(vertex.getUniformSlot('data'), data);
      fragmentBindings?.call();
      final info = ByteData(64)
        ..setUint32(0, entry.begin ~/ 4, Endian.little)
        ..setUint32(4, segmentsWord, Endian.little)
        ..setUint32(8, instancesWord, Endian.little)
        ..setUint32(12, pathsWord, Endian.little)
        ..setUint32(16, p16sWord, Endian.little)
        ..setUint32(20, frame.pathsCount, Endian.little)
        ..setUint32(24, frame.texCount, Endian.little)
        ..setUint32(28, entry.count, Endian.little)
        ..setUint32(32, flags, Endian.little)
        ..setFloat32(48, width.toDouble(), Endian.little)
        ..setFloat32(52, height.toDouble(), Endian.little);
      pass.bindUniform(
        vertex.getUniformSlot('FrameInfo'),
        hostBuffer.emplace(info),
      );
      pass.draw(4, instanceCount: entry.count);
    }

    // Draws the opaques' colors and depth. With [blend], it blends their
    // colors with that equation instead, such as _keepColor, which keeps the
    // target's colors.
    void drawOpaques(
      ra.Entry entry,
      int segmentsWord,
      int instancesWord, [
      gpu.ColorBlendEquation? blend,
    ]) {
      pass.setColorBlendEnable(blend != null);
      if (blend != null) {
        pass.setColorBlendEquation(blend);
      }
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.greater);
      draw(
        opaquesPipeline,
        opaquesVertex,
        entry,
        segmentsWord,
        instancesWord,
        () => pass.bindTexture(
          opaquesFragment.getUniformSlot('colors'),
          colors,
          sampler: _colorSampler,
        ),
      );
    }

    void beginPass(_PassKind kind) {
      if (passKind == kind && kind != _PassKind.edges) {
        return;
      }
      commandBuffer?.submit();
      commandBuffer = context.createCommandBuffer();
      passKind = kind;
      if (kind == _PassKind.edges) {
        pass = commandBuffer!.createRenderPass(
          gpu.RenderTarget.singleColor(
            gpu.ColorAttachment(
              texture: accumulation,
              clearValue: vm.Vector4.zero(),
            ),
          ),
        );
        return;
      }
      pass = commandBuffer!.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(texture: target, loadAction: gpu.LoadAction.load),
          depthStencilAttachment: gpu.DepthStencilAttachment(
            texture: depth,
            depthClearValue: 0,
            depthStoreAction: gpu.StoreAction.dontCare,
          ),
        ),
      );
      if (!cleared) {
        cleared = true;
        pass.clearBindings();
        pass.bindPipeline(clearPipeline);
        pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
        pass.setColorBlendEnable(false);
        pass.setDepthWriteEnable(false);
        pass.setDepthCompareOperation(gpu.CompareFunction.always);
        pass.bindVertexBuffer(corners);
        final info = Float32List.fromList(clearColor);
        pass.bindUniform(
          clearVertex.getUniformSlot('ClearInfo'),
          hostBuffer.emplace(ByteData.sublistView(info)),
        );
        pass.draw(4);
      }
      for (final (entry, segmentsWord, instancesWord) in opaques) {
        drawOpaques(entry, segmentsWord, instancesWord, _keepColor);
      }
    }

    beginPass(_PassKind.drawable);
    var segmentsWord = 0, instancesWord = 0;
    for (final entry in frame.entries) {
      switch (entry.type) {
        case ra.EntryType.segmentsBase:
          segmentsWord = entry.begin ~/ 4;
        case ra.EntryType.instancesBase:
          // Its end gives the accumulation rows its group's edges use. For
          // now, edges passes render all the rows.
          instancesWord = entry.begin ~/ 4;
        case ra.EntryType.disableClip || ra.EntryType.enableClip:
          break;
        case ra.EntryType.opaques:
          beginPass(_PassKind.drawable);
          drawOpaques(entry, segmentsWord, instancesWord);
          opaques.add((entry, segmentsWord, instancesWord));
        case ra.EntryType.quadEdges ||
            ra.EntryType.fastEdges ||
            ra.EntryType.fastMolecules ||
            ra.EntryType.quadMolecules:
          // Each group's edges begin with its quad edges. They begin a new
          // edges pass once the instances have read the last one.
          if (entry.type == ra.EntryType.quadEdges &&
              (passKind != _PassKind.edges || edgesRead)) {
            beginPass(_PassKind.edges);
            edgesRead = false;
          }
          if (entry.count == 0) {
            break;
          }
          final (pipeline, vertex) = switch (entry.type) {
            ra.EntryType.quadEdges => (quadEdgesPipeline, edgesVertex),
            ra.EntryType.fastEdges => (fastEdgesPipeline, edgesVertex),
            ra.EntryType.fastMolecules => (
              fastMoleculesPipeline,
              fastMoleculesVertex,
            ),
            _ => (quadMoleculesPipeline, quadMoleculesVertex),
          };
          pass.setColorBlendEnable(true);
          pass.setColorBlendEquation(_additive);
          draw(pipeline, vertex, entry, segmentsWord, instancesWord);
        case ra.EntryType.instances:
          edgesRead = true;
          if (entry.count == 0) {
            break;
          }
          beginPass(_PassKind.drawable);
          pass.setColorBlendEnable(true);
          pass.setColorBlendEquation(_sourceOver);
          pass.setDepthWriteEnable(false);
          pass.setDepthCompareOperation(gpu.CompareFunction.greater);
          draw(
            instancesPipeline,
            instancesVertex,
            entry,
            segmentsWord,
            instancesWord,
            () {
              pass.bindTexture(
                instancesFragment.getUniformSlot('accumulation'),
                accumulation,
              );
              pass.bindTexture(
                instancesFragment.getUniformSlot('colors'),
                colors,
                sampler: _colorSampler,
              );
            },
          );
        case ra.EntryType.clipMask || ra.EntryType.blendInstances:
          throw UnsupportedError(
            'GpuRenderer renders no ${entry.type.name} entries, which SVGs '
            'shouldn\'t have',
          );
      }
    }
    commandBuffer!.submit();
    encodeMicros = watch.elapsedMicroseconds;
    return target;
  }

  /// The number of pipeline states [render] draws with.
  ///
  /// They are: clear, opaques without and with blending, the four kinds of
  /// edges and molecules, and instances. Each compiles when it first draws.
  /// On OpenGL ES, Flutter GPU blocks the UI thread while it compiles, for
  /// 25-130 ms each on the Android emulator.
  static const warmUpSteps = 8;

  /// Draws with pipeline state [step] of [warmUpSteps], into scratch
  /// textures, which compiles it if needed.
  ///
  /// This lets the self-test compile one state per frame. Each step must set
  /// the same states that [render] sets for that draw.
  void warmUp(int step) {
    final slot = _warmSlot ??= RenderTargets(),
        shared = _warmShared ??= SharedTargets();
    _ensureTargets(slot, shared, 4, 4);
    final data = slot.data ??= context.createTexture(
      gpu.StorageMode.devicePrivate,
      1 << dataWidthLog2,
      1,
      format: gpu.PixelFormat.r32g32b32a32Float,
      enableRenderTargetUsage: false,
    )..overwrite(ByteData(dataRowBytes));
    final colors = slot.colors ??= context.createTexture(
      gpu.StorageMode.devicePrivate,
      ra.layout.colorTextureWidth,
      1,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      enableRenderTargetUsage: false,
    )..overwrite(ByteData(ra.layout.colorTextureWidth * 4));
    final edges = step >= 3 && step <= 6;
    final commandBuffer = context.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      edges
          ? gpu.RenderTarget.singleColor(
              gpu.ColorAttachment(
                texture: shared.accumulation!,
                clearValue: vm.Vector4.zero(),
              ),
            )
          : gpu.RenderTarget.singleColor(
              gpu.ColorAttachment(
                texture: slot.target!,
                loadAction: gpu.LoadAction.load,
              ),
              depthStencilAttachment: gpu.DepthStencilAttachment(
                texture: shared.depth!,
                depthClearValue: 0,
                depthStoreAction: gpu.StoreAction.dontCare,
              ),
            ),
    );
    pass.clearBindings();
    pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
    pass.bindVertexBuffer(corners);
    if (step == 0) {
      pass.bindPipeline(clearPipeline);
      pass.setColorBlendEnable(false);
      pass.setDepthWriteEnable(false);
      pass.setDepthCompareOperation(gpu.CompareFunction.always);
      pass.bindUniform(
        clearVertex.getUniformSlot('ClearInfo'),
        hostBuffer.emplace(ByteData(16)),
      );
      pass.draw(4);
      commandBuffer.submit();
      return;
    }
    final (pipeline, vertex) = switch (step) {
      1 || 2 => (opaquesPipeline, opaquesVertex),
      3 => (quadEdgesPipeline, edgesVertex),
      4 => (fastEdgesPipeline, edgesVertex),
      5 => (fastMoleculesPipeline, fastMoleculesVertex),
      6 => (quadMoleculesPipeline, quadMoleculesVertex),
      _ => (instancesPipeline, instancesVertex),
    };
    if (step == 1 || step == 2) {
      pass.setColorBlendEnable(step == 2);
      if (step == 2) {
        pass.setColorBlendEquation(_keepColor);
      }
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.greater);
    } else if (edges) {
      pass.setColorBlendEnable(true);
      pass.setColorBlendEquation(_additive);
    } else {
      pass.setColorBlendEnable(true);
      pass.setColorBlendEquation(_sourceOver);
      pass.setDepthWriteEnable(false);
      pass.setDepthCompareOperation(gpu.CompareFunction.greater);
    }
    pass.bindPipeline(pipeline);
    pass.bindTexture(vertex.getUniformSlot('data'), data);
    if (step == 1 || step == 2) {
      pass.bindTexture(
        opaquesFragment.getUniformSlot('colors'),
        colors,
        sampler: _colorSampler,
      );
    }
    if (step == 7) {
      pass.bindTexture(
        instancesFragment.getUniformSlot('accumulation'),
        shared.accumulation!,
      );
      pass.bindTexture(
        instancesFragment.getUniformSlot('colors'),
        colors,
        sampler: _colorSampler,
      );
    }
    // A draw of 0 instances doesn't compile its pipeline, so this draws 1,
    // from zeroed data.
    pass.bindUniform(
      vertex.getUniformSlot('FrameInfo'),
      hostBuffer.emplace(ByteData(64)),
    );
    pass.draw(4, instanceCount: 1);
    commandBuffer.submit();
  }

  RenderTargets? _warmSlot;
  SharedTargets? _warmShared;

  static final _colorSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
  );

  /// Adds up coverage, for the edges' accumulation.
  static final _additive = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  /// Keeps the target's colors, for draws of depth only.
  static final _keepColor = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.zero,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.zero,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  /// Source over, with premultiplied colors.
  static final _sourceOver = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );

  /// Sizes [slot]'s target and [shared]'s depth and accumulation to [width] x
  /// [height], and returns the target.
  ///
  /// The GPU renderer hands out the target's image before it renders.
  gpu.Texture target(
    RenderTargets slot,
    SharedTargets shared,
    int width,
    int height,
  ) {
    _ensureTargets(slot, shared, width, height);
    return slot.target!;
  }

  void _ensureTargets(
    RenderTargets slot,
    SharedTargets shared,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid target size $width×$height');
    }
    if (slot.target?.width != width || slot.target?.height != height) {
      slot.target = context.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: colorFormat,
      );
      // Writes the new texture once, which puts it in a defined layout before
      // its first render pass. Impeller's Vulkan backend reuses that pass for
      // later ones, so they would all begin in an undefined layout otherwise.
      // The bytes come from the texture's own size, as a format's pixels may
      // not be 4 bytes, as with wide gamut.
      slot.target!.overwrite(
        ByteData(slot.target!.getBaseMipLevelSizeInBytes()),
      );
    }
    if (shared.depth?.width == width && shared.depth?.height == height) {
      return;
    }
    shared.depth = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: depthFormat,
      enableShaderReadUsage: false,
    );
    shared.accumulation = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: accumulationFormat,
    );
  }

  /// Uploads [frame] for [slot], and returns its data and colors textures.
  ///
  /// The frame's bytes go in one copy into [slot]'s staging buffer. A blit
  /// then copies them into the data texture, as whole rows. It also copies
  /// the paths' colors and the gradient strips, which are among those bytes,
  /// into the colors texture, kColorTextureWidth texels a row, as
  /// RasterizerLayer does.
  ///
  /// The data texture and its staging buffer grow to 4/3 of the rows a frame
  /// needs. They shrink as the core's buffer does: when they're over 1 MB and
  /// over 5 times what the frame needs. Only the frame's rows are blitted. The
  /// rows past them hold an earlier frame's data, which the shaders never
  /// read, as they read rows by index.
  ///
  /// The colors texture has exactly the frame's rows, as the shaders compute
  /// their coordinates from its height.
  (gpu.Texture, gpu.Texture) _upload(RenderTargets slot, ra.Frame frame) {
    final rows = (frame.size + dataRowBytes - 1) ~/ dataRowBytes;
    final capacity = slot.data?.height ?? 0;
    if (capacity < rows ||
        (capacity * dataRowBytes > 1000000 && capacity ~/ rows > 5)) {
      slot.data = context.createTexture(
        gpu.StorageMode.devicePrivate,
        1 << dataWidthLog2,
        rows * 4 ~/ 3,
        format: gpu.PixelFormat.r32g32b32a32Float,
        enableRenderTargetUsage: false,
      );
      slot.staging = null;
    }
    // A buffer whose last blit hasn't run yet is replaced, as writing into it
    // would change what that blit copies.
    final reused = slot.staging;
    final staging = reused != null && !identical(reused, slot._blitting)
        ? reused
        : slot.staging = context.createDeviceBuffer(
            gpu.StorageMode.hostVisible,
            slot.data!.height * dataRowBytes,
          );
    if (!staging.overwrite(ByteData.sublistView(frame.bytes))) {
      throw StateError('Failed to upload a frame of ${frame.size} bytes');
    }

    final w = ra.layout.colorTextureWidth, rowBytes = w * ra.layout.color;
    final h = (frame.pathsCount + w) ~/ w, th = frame.texCount;
    if (slot.colors?.height != h + th) {
      slot.colors = context.createTexture(
        gpu.StorageMode.devicePrivate,
        w,
        h + th,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
      );
    }
    final data = slot.data!, colors = slot.colors!;
    gpu.BufferView view(int offset, int length) =>
        gpu.BufferView(staging, offsetInBytes: offset, lengthInBytes: length);
    final blit = context.createCommandBuffer()
      ..copyBufferToTexture(
        view(0, rows * dataRowBytes),
        gpu.TextureRegion(data, height: rows),
      )
      ..copyBufferToTexture(
        view(frame.colors, h * rowBytes),
        gpu.TextureRegion(colors, height: h),
      );
    if (th > 0) {
      blit.copyBufferToTexture(
        view(frame.texStrips, th * rowBytes),
        gpu.TextureRegion(colors, y: h, height: th),
      );
    }
    slot._blitting = staging;
    blit.submit(
      completionCallback: (_) {
        if (identical(slot._blitting, staging)) {
          slot._blitting = null;
        }
      },
    );
    return (data, colors);
  }
}

/// The kinds of render pass: into the target, or into the accumulation.
enum _PassKind() {
  drawable,
  edges,
}

/// The textures of a frame in flight.
///
/// They are its target, the data and colors textures it reads, and the
/// staging buffer they're uploaded through.
class RenderTargets() {
  gpu.Texture? target, data, colors;
  gpu.DeviceBuffer? staging;

  /// The staging buffer whose last blit hasn't run yet, if any.
  gpu.DeviceBuffer? _blitting;
}

/// The textures that frames in flight share: depth and accumulation.
///
/// Only a frame's own command buffers use them.
class SharedTargets() {
  gpu.Texture? depth, accumulation;
}
