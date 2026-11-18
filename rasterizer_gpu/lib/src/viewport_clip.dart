import 'dart:ui' as ui;

/// A rectangle of whole pixels, from (left, top) to (right, bottom).
typedef PixelRect = ({int left, int top, int right, int bottom});

/// Returns the pixels of a [width] by [height] viewport within [margin]
/// pixels of [clip], or all of them if [clip] is null.
///
/// A clip that's inverted, or NaN, has no pixels.
PixelRect viewportClip(ui.Rect? clip, int width, int height, int margin) {
  if (clip == null) {
    return (left: 0, top: 0, right: width, bottom: height);
  }
  if (!(clip.left <= clip.right && clip.top <= clip.bottom)) {
    return (left: 0, top: 0, right: 0, bottom: 0);
  }
  // Clamped first, as huge values don't round to ints.
  final w = width.toDouble(), h = height.toDouble();
  return (
    left: (clip.left.clamp(0.0, w).floor() - margin).clamp(0, width),
    top: (clip.top.clamp(0.0, h).floor() - margin).clamp(0, height),
    right: (clip.right.clamp(0.0, w).ceil() + margin).clamp(0, width),
    bottom: (clip.bottom.clamp(0.0, h).ceil() + margin).clamp(0, height),
  );
}
