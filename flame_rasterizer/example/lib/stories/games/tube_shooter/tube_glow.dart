import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/extensions.dart';
import 'package:flame/post_process.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// The Glow knob's glow with the renderers other than the mesh renderer,
/// which draws its own: a halo round the lines, in their colours, with a
/// white core down the middle of the wider ones.
///
/// As [game]'s camera's post process, it rasterizes the world each frame at
/// half the device's pixel ratio, which the halo's blur hides, and draws
/// `shaders/glow.frag` over the world, which the renderer draws as usual.
/// The halo reaches [radius] logical pixels round the rim, and less towards
/// the tube's middle, as the lines thin with depth. The stars, in the
/// camera's backdrop, don't glow.
class TubeGlow(final TubeHost game) extends ShaderPostProcess {
  this
    : super(
        'shaders/glow.frag',
        sampleSubtree: true,
        placement: ShaderPlacement.over,
        // Its image is at half the resolution, so the renderer draws the
        // world again.
        reuseRasterizedSubtree: false,
        pixelRatio:
            PlatformDispatcher.instance.views.first.devicePixelRatio / 2,
      );

  /// How far the halo reaches round the rim, in logical pixels.
  static const radius = 8.0;

  /// How strong the halo is: how fast it saturates as lines come near.
  static const gain = 3.0;

  /// How white the core of a wide line is, from 0 to 1.
  static const core = 0.5;

  late final UniformVec2Slot _center;
  late final UniformFloatSlot _rim;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // The shader keeps these.
    shader.getUniformFloat('uRadius').set(radius);
    shader.getUniformFloat('uGain').set(gain);
    shader.getUniformFloat('uCore').set(core);
    _center = shader.getUniformVec2('uCenter');
    _rim = shader.getUniformFloat('uRim');
  }

  @override
  void updateUniforms(Vector2 size) {
    // Where the tube's axis is, in the viewport.
    final viewfinder = game.camera.viewfinder;
    _center.setVector(viewfinder.transform.localToGlobal(Vector2.zero()));
    // How far its rim reaches from the axis, in the viewport.
    final view = game.view;
    var outline = 0.0;
    for (final point in view.tube.points) {
      outline = math.max(outline, point.distance);
    }
    _rim.set(math.max(1, outline * view.rimScale * viewfinder.zoom));
  }
}
