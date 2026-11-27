import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';

/// An app that runs a game's story on its own, outside the Widgetbook.
///
/// A settings button over the story's top right corner opens a dialog with
/// the renderer, which starts at [SvgRenderer.firstChoice], and the rows that
/// [settingsBuilder] builds for the game's other settings, its knobs in the
/// Widgetbook. While the dialog shows, the story is under a [TickerMode] that
/// is off, which pauses a `GameStory`'s game. Once the dialog closes,
/// whichever way, the story goes on with the dialog's renderer and settings:
/// a `GameStory` goes on from a snapshot of the old game when the renderer
/// changes.
class const StandaloneGame<S extends Object>({
  /// The app's title, for the platform: the task switcher, or the browser
  /// tab.
  required final String title,

  /// The game's settings at the start.
  required final S settings,

  /// Builds the story for a renderer and settings. The story can change its
  /// settings with the callback it gets, such as the level that it plays.
  required final Widget Function(
    SvgRenderer renderer,
    S settings,
    ValueChanged<S> onChanged,
  )
  builder,

  /// Builds the dialog's rows for the settings, under the renderer's, which
  /// has the renderer picked so far.
  required final List<Widget> Function(
    SvgRenderer renderer,
    S settings,
    ValueChanged<S> onChanged,
  )
  settingsBuilder,

  /// Whether the game draws SVGs: without them, the renderers show Flame for
  /// Flame SVG, as Flame's own components draw then.
  final bool svgs = true,
  super.key,
}) extends StatefulWidget {
  @override
  State<StandaloneGame<S>> createState() => _StandaloneGameState<S>();
}

class _StandaloneGameState<S extends Object>()
    extends State<StandaloneGame<S>> {
  var _renderer = SvgRenderer.firstChoice;
  late var _settings = widget.settings;

  /// Whether the settings dialog shows, which pauses the game.
  var _paused = false;

  /// Shows the settings dialog over the paused game, and goes on with its
  /// renderer and settings once it closes.
  Future<void> _showSettings(BuildContext context) async {
    var renderer = _renderer;
    var settings = _settings;
    setState(() => _paused = true);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingDropdown<SvgRenderer>(
                    label: 'Renderer',
                    value: renderer,
                    options: SvgRenderer.values,
                    labelOf: (value) => value.entryText(svgs: widget.svgs),
                    enabledOf: (value) => value.supported,
                    onChanged: (value) => setState(() => renderer = value),
                  ),
                  ...widget.settingsBuilder(
                    renderer,
                    settings,
                    (value) => setState(() => settings = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _renderer = renderer;
        _settings = settings;
        _paused = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.title,
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: TickerMode(
                  enabled: !_paused,
                  child: widget.builder(
                    _renderer,
                    _settings,
                    (value) => setState(() => _settings = value),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                // Out of the focus, so that the game keeps the keys once the
                // dialog closes.
                child: ExcludeFocus(
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                    child: Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.settings),
                        color: Colors.white,
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Settings',
                        onPressed: () => _showSettings(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings row with a dropdown of [options], which shows each one's
/// [labelOf], and makes inactive those that aren't [enabledOf].
class const SettingDropdown<T extends Object>({
  required final String label,
  required final T value,
  required final List<T> options,
  required final String Function(T option) labelOf,
  required final ValueChanged<T> onChanged,
  final bool Function(T option)? enabledOf,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      label: label,
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              enabled: enabledOf?.call(option) ?? true,
              child: Text(labelOf(option)),
            ),
        ],
      ),
    );
  }
}

/// A settings row with a switch.
class const SettingSwitch({
  required final String label,
  required final bool value,
  required final ValueChanged<bool> onChanged,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      label: label,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// A settings row with a continuous slider from [range]'s min to its max,
/// which shows its value with two decimals, in tabular figures.
class const SettingSlider({
  required final String label,
  required final double value,
  required final ({double min, double max}) range,
  required final ValueChanged<double> onChanged,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(
          label: label,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Slider(
          value: value,
          min: range.min,
          max: range.max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// A settings row: [label] on the left, [child] on the right.
class const _SettingRow({
  required final String label,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          child,
        ],
      ),
    );
  }
}
