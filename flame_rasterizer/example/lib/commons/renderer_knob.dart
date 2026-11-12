import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:widgetbook/widgetbook.dart';

/// The Renderer knob's label, which also names its field in the URL.
const _label = 'Renderer';

/// The knob's GPU entries, in the order that their self-tests run.
const _gpus = [SvgRenderer.rasterizer, SvgRenderer.rasterizerAtlas];

/// The Renderer knob: a dropdown of the [SvgRenderer]s.
///
/// A GPU entry is inactive where its renderer isn't [SvgRenderer.supported]:
/// on the web, without Impeller, and on OpenGL ES until its self-test passes
/// (see [refreshRendererKnob]). GPU (mesh) is the first choice, or Canvas
/// where GPU (mesh) is inactive. Widgetbook's own dropdown can't make an
/// entry inactive, so this knob has a dropdown of its own.
SvgRenderer rendererKnob(BuildContext context) {
  final renderer = context.knobs.onKnobAdded(
    _RendererKnob(
      initialValue: SvgRenderer.rasterizer.supported
          ? SvgRenderer.rasterizer
          : SvgRenderer.rasterizerCanvas,
    ),
  );
  // A link can pick a GPU entry where it's inactive: Canvas draws then.
  return renderer == null || !renderer.supported
      ? SvgRenderer.rasterizerCanvas
      : renderer;
}

/// The Zoom knob: the camera's zoom, from 0.25 to 5, on a continuous slider.
double zoomKnob(BuildContext context) => context.knobs.onKnobAdded(
  _SliderKnob(label: 'Zoom', initialValue: 1, min: 0.25, max: 5),
)!;

/// The Speed knob: the game's speed, from 0, which stands still, to 2, on a
/// continuous slider.
double speedKnob(BuildContext context) => context.knobs.onKnobAdded(
  _SliderKnob(label: 'Speed', initialValue: 1, min: 0, max: 2),
)!;

/// An integer slider knob from [min] to [max], in [divisions] steps, like
/// Widgetbook's. Like [zoomKnob], it shows its value in tabular figures.
int intSliderKnob(
  BuildContext context, {
  required String label,
  required int initialValue,
  required int min,
  required int max,
  int? divisions,
}) => context.knobs.onKnobAdded(
  _IntSliderKnob(
    label: label,
    initialValue: initialValue,
    min: min,
    max: max,
    divisions: divisions,
  ),
)!;

/// The Cache mode and Cache size knobs, which set flame_svg's cache.
///
/// They show only while [shown], which the examples set with Flame SVG.
/// Otherwise this returns flame_svg's defaults. Widgetbook registers the
/// knobs again on each build, so hidden knobs keep their values.
SvgCache cacheKnobs(BuildContext context, {required bool shown}) {
  if (!shown) {
    return defaultSvgCache;
  }
  return (
    mode: context.knobs.object.segmented(
      label: 'Cache mode',
      options: SvgCacheMode.values,
      initialOption: defaultSvgCache.mode,
      labelBuilder: (value) => value.name,
    ),
    size: context.knobs.object.dropdown(
      label: 'Cache size',
      options: SvgCacheSize.values,
      initialOption: defaultSvgCache.size,
      labelBuilder: (value) => '${value.name} (${value.label})',
    ),
  );
}

/// Makes a GPU renderer's entry active once its self-test passes, as on
/// OpenGL ES.
///
/// It waits for each renderer's self-test in turn, the mesh renderer's
/// first. When one passes, it rebuilds the knobs panel. The Renderer knob
/// keeps the renderer that the game has, from a link or else Canvas, the
/// first choice until then, so that the game goes on.
Future<void> refreshRendererKnob(BuildContext context) async {
  for (final renderer in _gpus) {
    if (renderer.supported) {
      continue;
    }
    await RasterizerGpu.of(renderer.gpu).initialize();
    if (!context.mounted) {
      return;
    }
    if (!renderer.supported) {
      continue;
    }
    final state = WidgetbookState.of(context);
    final knobs = FieldCodec.decodeQueryGroup(state.queryParams['knobs']);
    state.updateQueryField(
      group: 'knobs',
      field: _label,
      value: knobs[_label] ?? SvgRenderer.rasterizerCanvas.label,
    );
  }
}

/// The Renderer knob, whose dropdown can make entries inactive.
class _RendererKnob({required super.initialValue}) extends Knob<SvgRenderer?> {
  this : super(label: _label);

  @override
  List<Field> get fields => [
    _RendererField(name: label, initialValue: initialValue),
  ];

  @override
  SvgRenderer? valueFromQueryGroup(Map<String, String> group) =>
      valueOf(label, group);
}

class _RendererField({required super.name, required super.initialValue})
    extends ObjectDropdownField<SvgRenderer> {
  this
    : super(values: SvgRenderer.values, labelBuilder: (value) => value.label);

  /// Builds Widgetbook's dropdown, with the GPU entries inactive where their
  /// renderers aren't supported.
  @override
  Widget toWidget(BuildContext context, String group, SvgRenderer? value) {
    return DropdownMenu<SvgRenderer>(
      expandedInsets: EdgeInsets.zero,
      trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
      selectedTrailingIcon: const Icon(Icons.keyboard_arrow_up_rounded),
      initialSelection: value,
      onSelected: (value) {
        if (value != null) {
          updateField(context, group, value);
        }
      },
      dropdownMenuEntries: [
        for (final renderer in values)
          DropdownMenuEntry(
            value: renderer,
            label: labelBuilder(renderer),
            enabled: renderer.supported,
          ),
      ],
    );
  }
}

/// A continuous slider knob from [min] to [max], with values kept to two
/// decimals.
///
/// Widgetbook's slider keeps one decimal by default, so its thumb jumps
/// between tenths, whatever its divisions. This one shows its value in
/// tabular figures.
class _SliderKnob({
  required super.label,
  required super.initialValue,
  required final double min,
  required final double max,
}) extends Knob<double?> {
  @override
  List<Field> get fields => [
    _SliderField(name: label, initialValue: initialValue, min: min, max: max),
  ];

  @override
  double? valueFromQueryGroup(Map<String, String> group) =>
      valueOf(label, group);
}

class _SliderField({
  required super.name,
  required super.initialValue,
  required super.min,
  required super.max,
}) extends DoubleSliderField {
  this : super(precision: 2);

  @override
  Widget toWidget(BuildContext context, String group, double? value) =>
      _withTabularFigures((context) => super.toWidget(context, group, value));
}

class _IntSliderKnob({
  required super.label,
  required super.initialValue,
  required final int min,
  required final int max,
  final int? divisions,
}) extends Knob<int?> {
  @override
  List<Field> get fields => [
    _IntSliderField(
      name: label,
      initialValue: initialValue,
      min: min,
      max: max,
      divisions: divisions,
    ),
  ];

  @override
  int? valueFromQueryGroup(Map<String, String> group) => valueOf(label, group);
}

class _IntSliderField({
  required super.name,
  required super.initialValue,
  required super.min,
  required super.max,
  super.divisions,
}) extends IntSliderField {
  @override
  Widget toWidget(BuildContext context, String group, int? value) =>
      _withTabularFigures((context) => super.toWidget(context, group, value));
}

/// Builds a slider with [builder], showing its value in tabular figures.
///
/// Widgetbook sizes the value for the wider of the slider's min and max.
/// With proportional figures, such as those of macOS' system font, a value
/// can be wider, and gets cut: "3." for 3.6, or an integer without its last
/// digit.
Widget _withTabularFigures(WidgetBuilder builder) => DefaultTextStyle.merge(
  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
  child: Builder(builder: builder),
);
