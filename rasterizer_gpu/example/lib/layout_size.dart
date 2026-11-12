import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Takes the biggest size that its constraints allow, and lays [child] out at
/// that size.
///
/// Whenever the size or [ratio] changes, it calls [onLayout] with both,
/// during layout. So a page can render for its size without changing its
/// state in `build`.
class const LayoutSize({
  super.key,
  required final double ratio,
  required final void Function(Size size, double ratio) onLayout,
  super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutSize(ratio, onLayout);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLayoutSize)
      ..ratio = ratio
      ..onLayout = onLayout;
  }
}

class _RenderLayoutSize(
  var double _ratio,
  var void Function(Size size, double ratio) onLayout,
) extends RenderProxyBox {
  /// The size and ratio that it last passed to [onLayout].
  (Size, double)? _reported;

  double get ratio => _ratio;
  set ratio(double value) {
    if (value != _ratio) {
      _ratio = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints.tight(size));
    if (_reported != (size, _ratio)) {
      _reported = (size, _ratio);
      onLayout(size, _ratio);
    }
  }
}
