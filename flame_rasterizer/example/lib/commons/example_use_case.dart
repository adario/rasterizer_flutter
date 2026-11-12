import 'package:flame_rasterizer_example/commons/renderer_knob.dart';
import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

/// A Widgetbook use case with a link to its code and a description, as in
/// Flame's examples.
class ExampleUseCase({
  required super.name,
  required WidgetBuilder builder,

  /// The link to the example's source code.
  required final String codeLink,

  /// The example's description, which the bar's Description button shows.
  required final String info,
}) extends WidgetbookUseCase {
  this : super(builder: _persistent(builder));

  /// Wraps [builder] in a [_PersistentExample] with a key of its own, so that
  /// the example keeps its state when Widgetbook remounts it.
  static WidgetBuilder _persistent(WidgetBuilder builder) {
    final key = GlobalKey();
    return (_) => _PersistentExample(key: key, builder: builder);
  }
}

/// Builds an example again only when its knobs change.
///
/// Widgetbook rebuilds, and even remounts, the active use case whenever any
/// of its state changes, such as the text in its search field. Without this
/// widget, those changes would restart the game.
class const _PersistentExample({
  required final WidgetBuilder builder,
  super.key,
}) extends StatefulWidget {
  @override
  State<_PersistentExample> createState() => _PersistentExampleState();
}

class _PersistentExampleState() extends State<_PersistentExample> {
  Widget? _child;

  /// The knobs' values in the URL's query when [_child] was built.
  String? _knobValues;

  /// The knobs that building [_child] registered.
  Map<String, Knob> _knobs = const {};

  @override
  void initState() {
    super.initState();
    refreshRendererKnob(context);
  }

  @override
  void reassemble() {
    super.reassemble();
    // A hot reload builds the example again, with the new code.
    _child = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = WidgetbookState.of(context);
    final knobValues = state.queryParams['knobs'];
    if (_child == null || knobValues != _knobValues) {
      _child = SizedBox.expand(child: widget.builder(context));
      _knobValues = knobValues;
      _knobs = Map.of(state.knobs);
    } else {
      // Widgetbook clears its knobs before each build of a use case, so
      // register the old ones again.
      state.knobs.addAll(_knobs);
    }
    return _child!;
  }
}
