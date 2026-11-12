/// The core's affine transforms and bounds, written in Dart for core.dart.
///
/// They match the C++ core's `Ra::Transform` and `Ra::Bounds`, without FFI.
library;

/// An affine transform, as the core's `Ra::Transform`.
///
/// It maps (x, y) to (a * x + c * y + tx, b * x + d * y + ty).
class const Transform(
  final double a,
  final double b,
  final double c,
  final double d,
  final double tx,
  final double ty,
) {
  const Transform.identity() : this(1, 0, 0, 1, 0, 0);
  const Transform.scale(double s) : this(s, 0, 0, s, 0, 0);
  const Transform.translation(double tx, double ty) : this(1, 0, 0, 1, tx, ty);

  /// The transform that applies this one, then [t].
  ///
  /// It matches the core's `Ra::Transform::concat`.
  Transform concat(Transform t) => Transform(
    a * t.a + b * t.c,
    a * t.b + b * t.d,
    c * t.a + d * t.c,
    c * t.b + d * t.d,
    tx * t.a + ty * t.c + t.tx,
    tx * t.b + ty * t.d + t.ty,
  );

  @override
  String toString() => 'Transform($a, $b, $c, $d, $tx, $ty)';
}

/// Axis-aligned bounds, as the core's `Ra::Bounds`.
class const Bounds(
  final double lx,
  final double ly,
  final double ux,
  final double uy,
) {
  double get width => ux - lx;
  double get height => uy - ly;
  bool get isNull => lx == _fltMax && ly == _fltMax;
  bool get isRect => ux > lx && uy > ly;

  /// The transform that fits [inner] into these bounds.
  ///
  /// It centers [inner] and keeps its aspect ratio, as the core's
  /// `Ra::Bounds::fitTransform` does.
  Transform fit(Bounds inner) {
    if (isNull || !isRect || inner.isNull || !inner.isRect) {
      return const Transform.identity();
    }
    final s = width / inner.width < height / inner.height
        ? width / inner.width
        : height / inner.height;
    return Transform(
      s,
      0,
      0,
      s,
      lx + 0.5 * (width - s * inner.width) - s * inner.lx,
      ly + 0.5 * (height - s * inner.height) - s * inner.ly,
    );
  }

  static const _fltMax = 3.4028234663852886e38;

  @override
  String toString() => 'Bounds($lx, $ly, $ux, $uy)';
}
