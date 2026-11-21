import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

/// The table's parts for one arena size. It stops drawing once [next] has
/// mounted all of its parts, and then goes, so that resizing doesn't flicker.
class TableComponent(final List<Component> _parts) extends Component {
  this : super(children: _parts);

  TableComponent? next;

  bool get _ready => isMounted && children.length == _parts.length;

  @override
  void update(double dt) {
    if (next?._ready ?? false) {
      removeFromParent();
    }
  }

  @override
  void renderTree(Canvas canvas) {
    if (!(next?._ready ?? false)) {
      super.renderTree(canvas);
    }
  }
}
