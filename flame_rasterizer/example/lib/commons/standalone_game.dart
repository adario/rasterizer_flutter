import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';

/// An app that runs a game's story on its own, outside the Widgetbook.
///
/// A small renderer menu over the story's top right corner starts at
/// [SvgRenderer.firstChoice]. [builder] builds the story for the renderer,
/// such as a `GameStory` over a status bar, which goes on from a snapshot of
/// the old game when the renderer changes. The story gets no knobs.
class const StandaloneGame({
  /// The app's title, for the platform: the task switcher, or the browser
  /// tab.
  required final String title,

  /// Builds the story for a renderer.
  required final Widget Function(SvgRenderer renderer) builder,

  /// Whether the game draws SVGs: without them, the menu shows Flame for
  /// Flame SVG, as Flame's own components draw then.
  final bool svgs = true,
  super.key,
}) extends StatefulWidget {
  @override
  State<StandaloneGame> createState() => _StandaloneGameState();
}

class _StandaloneGameState() extends State<StandaloneGame> {
  var _renderer = SvgRenderer.firstChoice;

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
              Positioned.fill(child: widget.builder(_renderer)),
              Positioned(
                top: 4,
                right: 4,
                // Out of the focus, so that the game keeps the keys once the
                // menu closes.
                child: ExcludeFocus(
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButton<SvgRenderer>(
                        value: _renderer,
                        isDense: true,
                        underline: const SizedBox(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        iconEnabledColor: Colors.white,
                        dropdownColor: Colors.grey.shade900,
                        onChanged: (renderer) {
                          if (renderer != null) {
                            setState(() => _renderer = renderer);
                          }
                        },
                        items: [
                          for (final renderer in SvgRenderer.values)
                            DropdownMenuItem(
                              value: renderer,
                              enabled: renderer.supported,
                              child: Text(
                                renderer.entryText(svgs: widget.svgs),
                              ),
                            ),
                        ],
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
