import 'dart:ui' as ui;

import '../rasterizer_gpu.dart';

/// A run drawn as images, from its parts' rectangles.
///
/// The GPU renderer's parts are rectangles of its atlas pages. A mesh run has
/// one part, its own target.
abstract class ImageRun() extends RasterizerRun {
  @override
  void draw(
    ui.Canvas canvas, {
    double scale = 1,
    ui.Paint? paint,
    ui.FilterQuality filterQuality = ui.FilterQuality.none,
  }) {
    if (parts.isEmpty) {
      return;
    }
    final plain = _paints[filterQuality.index];
    if (paint == null) {
      return _drawParts(canvas, scale, plain);
    }
    // Drawing the images with the paint gives the same pixels as a layer
    // with that paint, without the layer's offscreen pass. A layer is still
    // needed:
    // - unbounded, for an image or mask filter, which reaches outside the
    //   images.
    // - for several parts with a blend mode that changes what's under
    //   transparent pixels, such as the gaps between the parts.
    // The second case takes a layer bounded to the parts and also clipped to
    // those bounds, because Impeller treats a layer's bounds only as a hint.
    // An unclipped srcIn layer clears the whole canvas around the parts,
    // whereas an image drawn with srcIn clears only its own rectangle.
    final filtered = paint.imageFilter != null || paint.maskFilter != null;
    if (filtered) {
      canvas.saveLayer(null, paint);
      _drawParts(canvas, scale, plain);
      canvas.restore();
      return;
    }
    if (parts.length > 1 && _clearsUnder.contains(paint.blendMode)) {
      final bounds = _bounds(scale);
      canvas
        ..save()
        ..clipRect(bounds)
        ..saveLayer(bounds, paint);
      _drawParts(canvas, scale, plain);
      canvas
        ..restore()
        ..restore();
      return;
    }
    _drawParts(
      canvas,
      scale,
      _paint
        ..color = paint.color
        ..blendMode = paint.blendMode
        ..colorFilter = paint.colorFilter
        ..invertColors = paint.invertColors
        ..filterQuality = filterQuality,
    );
  }

  /// Draws each part's image with [paint].
  ///
  /// One image draw per part costs less than one atlas draw per page.
  void _drawParts(ui.Canvas canvas, double scale, ui.Paint paint) {
    for (final part in parts) {
      canvas.drawImageRect(
        part.image,
        part.source,
        _scaled(part.destination, scale),
        paint,
      );
    }
  }

  /// Returns the union of its parts' destinations, in units of [scale] device
  /// pixels.
  ui.Rect _bounds(double scale) {
    var r = parts.first.destination;
    for (final part in parts.skip(1)) {
      r = r.expandToInclude(part.destination);
    }
    return _scaled(r, scale);
  }

  /// Returns [r] converted from device pixels to units of [scale] device
  /// pixels.
  static ui.Rect _scaled(ui.Rect r, double scale) => scale == 1
      ? r
      : ui.Rect.fromLTRB(
          r.left / scale,
          r.top / scale,
          r.right / scale,
          r.bottom / scale,
        );

  /// The blend modes that change what's under a transparent pixel.
  static const _clearsUnder = {
    ui.BlendMode.clear,
    ui.BlendMode.src,
    ui.BlendMode.srcIn,
    ui.BlendMode.dstIn,
    ui.BlendMode.srcOut,
    ui.BlendMode.dstATop,
    ui.BlendMode.modulate,
  };

  /// A plain paint for each filter quality, by index.
  static final _paints = [
    for (final quality in ui.FilterQuality.values)
      ui.Paint()..filterQuality = quality,
  ];

  /// A reused paint, into which each draw copies the fields of the caller's
  /// paint that apply to an image.
  static final _paint = ui.Paint();
}
