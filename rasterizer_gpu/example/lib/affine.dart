import 'dart:ui';

/// An affine transform, in the form that rasterizer_gpu's runs take:
/// x' = a * x + c * y + tx, y' = b * x + d * y + ty.
class const Affine(
  final double a,
  final double b,
  final double c,
  final double d,
  final double tx,
  final double ty,
) {
  const Affine.identity() : this(1, 0, 0, 1, 0, 0);
  const Affine.scale(double s) : this(s, 0, 0, s, 0, 0);
  const Affine.translation(double tx, double ty) : this(1, 0, 0, 1, tx, ty);

  /// Returns the transform that fits [inner] into [outer], centred, keeping
  /// its aspect ratio. Returns the identity if either is empty.
  static Affine fit(Rect outer, Rect inner) {
    if (outer.width <= 0 ||
        outer.height <= 0 ||
        inner.width <= 0 ||
        inner.height <= 0) {
      return const Affine.identity();
    }
    final s = outer.width / inner.width < outer.height / inner.height
        ? outer.width / inner.width
        : outer.height / inner.height;
    return Affine(
      s,
      0,
      0,
      s,
      outer.left + 0.5 * (outer.width - s * inner.width) - s * inner.left,
      outer.top + 0.5 * (outer.height - s * inner.height) - s * inner.top,
    );
  }

  /// Returns the transform that applies this one, then [t].
  Affine concat(Affine t) => Affine(
    a * t.a + b * t.c,
    a * t.b + b * t.d,
    c * t.a + d * t.c,
    c * t.b + d * t.d,
    tx * t.a + ty * t.c + t.tx,
    tx * t.b + ty * t.d + t.ty,
  );

  @override
  String toString() => 'Affine($a, $b, $c, $d, $tx, $ty)';
}
