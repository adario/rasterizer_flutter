import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';

/// An app that runs a game's story on its own, outside the Widgetbook.
///
/// A bar above the story shows [title] and a renderer menu, which starts at
/// [SvgRenderer.firstChoice]. [builder] builds the story for the renderer,
/// such as a `GameStory` over a status bar, which goes on from a snapshot of
/// the old game when the renderer changes. The story gets no knobs.
class const StandaloneGame({
  /// The app's title, which the bar shows.
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
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            // Out of the focus, so that the game keeps the keys once the
            // menu closes.
            ExcludeFocus(
              child: DropdownButton<SvgRenderer>(
                value: _renderer,
                underline: const SizedBox(),
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
                      child: Text(renderer.entryText(svgs: widget.svgs)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(child: widget.builder(_renderer)),
      ),
    );
  }
}
