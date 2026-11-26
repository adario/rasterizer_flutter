import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:widgetbook/widgetbook.dart';

/// The Renderer knob's label, which also names its field in the URL.
const _label = 'Renderer';

/// Returns the Renderer knob: a dropdown of the [SvgRenderer]s.
///
/// A GPU entry is inactive where its renderer isn't [SvgRenderer.supported]:
/// on the web and without Impeller. The first choice is GPU (mesh), else GPU
/// (atlas), else Canvas, whichever is active first. Widgetbook's own dropdown
/// can't make an entry inactive, so this knob has a dropdown of its own.
///
/// The entries show their [SvgRenderer.text], such as Metal (mesh) for an
/// active GPU (mesh). Without [svgs], for a game that draws no SVGs, Flame
/// SVG shows Flame, as Flame's own components draw then. Links keep their
/// [SvgRenderer.label], so that a link picks the same entry on every device
/// and in every use case.
SvgRenderer rendererKnob(BuildContext context, {bool svgs = true}) {
  final renderer = context.knobs.onKnobAdded(
    _RendererKnob(initialValue: SvgRenderer.firstChoice, svgs: svgs),
  );
  // A link can pick a GPU entry where it's inactive: Canvas draws then.
  return renderer == null || !renderer.supported
      ? SvgRenderer.rasterizerCanvas
      : renderer;
}

/// Returns the Zoom knob: the camera's zoom, from 0.25 to 5, on a continuous
/// slider.
double zoomKnob(BuildContext context) => context.knobs.onKnobAdded(
  _SliderKnob(label: 'Zoom', initialValue: 1, min: 0.25, max: 5),
)!;

/// Returns the Speed knob: the game's speed, from 0, which stands still, to 2,
/// on a continuous slider.
double speedKnob(BuildContext context) => context.knobs.onKnobAdded(
  _SliderKnob(label: 'Speed', initialValue: 1, min: 0, max: 2),
)!;

/// Returns the Flight speed knob: how fast Tube Runner's ship flies at first,
/// from 0.5 to 2 tube units a second, on a continuous slider. A prototype's,
/// to pick a speed with.
double flightSpeedKnob(BuildContext context) => context.knobs.onKnobAdded(
  _SliderKnob(label: 'Flight speed', initialValue: 1.5, min: 0.5, max: 2),
)!;

/// Returns an integer slider knob from [min] to [max], in [divisions] steps,
/// like Widgetbook's. Like [zoomKnob], it shows its value in tabular figures.
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

/// Returns the Cache mode and Cache size knobs, which set flame_svg's cache.
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

/// The Renderer knob, whose dropdown can make entries inactive.
class _RendererKnob({
  required super.initialValue,
  required final bool svgs,
}) extends Knob<SvgRenderer?> {
  this : super(label: _label);

  @override
  List<Field> get fields => [
    _RendererField(name: label, initialValue: initialValue, svgs: svgs),
  ];

  @override
  SvgRenderer? valueFromQueryGroup(Map<String, String> group) =>
      valueOf(label, group);
}

class _RendererField({
  required super.name,
  required super.initialValue,

  /// Whether the game draws SVGs: without them, Flame SVG shows Flame.
  required final bool svgs,
}) extends ObjectDropdownField<SvgRenderer> {
  this
    : super(values: SvgRenderer.values, labelBuilder: (value) => value.label);

  /// Builds Widgetbook's dropdown, with the GPU entries inactive where their
  /// renderers aren't supported, and each entry's text. The URL has the
  /// entry's label, from [labelBuilder].
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
            label: renderer.entryText(svgs: svgs),
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
