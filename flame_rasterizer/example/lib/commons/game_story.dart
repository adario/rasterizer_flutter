import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/foundation.dart';

/// Shows the game that [create] makes above a status bar, zoomed to [zoom]
/// and running at [speed].
///
/// A new [renderer] or [cache] creates a new game that continues from a
/// [snapshot] of the old one, so that it looks the same. A new [zoom] or
/// [speed] changes the running game, and so do the knobs that [update]
/// passes to it. For any other change that needs a new game, which starts
/// afresh, give this widget a key made of those values.
///
/// The game has the keyboard focus at the start, and pressing a pointer on
/// it takes the focus back from the knobs. A spinner shows until the game
/// has loaded. The game is paused while a [TickerMode] above it is off, as
/// the standalone games' settings dialog does.
class const GameStory<G extends StoryGame, S extends Object>({
  /// The renderer that the game draws with.
  required final SvgRenderer renderer,

  /// Creates the game, which shows its status in the given notifier and
  /// continues from the given snapshot, if any.
  required final G Function(ValueNotifier<String> status, S? from) create,

  /// flame_svg's cache settings, for Flame SVG.
  final SvgCache cache = defaultSvgCache,

  /// Takes a snapshot of the game, so that a new game with another renderer
  /// or cache can continue from it. Without it, the new game starts afresh.
  final S Function(G game)? snapshot,

  /// Passes the story's other knobs to the running game, each time the story
  /// rebuilds.
  final void Function(G game)? update,

  /// The camera's zoom.
  final double zoom = 1,

  /// The world's speed, from 0 (standing still) to 2.
  final double speed = 1,

  /// How many lines tall the status bar is: 0 for none.
  final int statusLines = 2,
  super.key,
}) extends StatefulWidget {
  @override
  State<GameStory<G, S>> createState() => _GameStoryState<G, S>();
}

class _GameStoryState<G extends StoryGame, S extends Object>()
    extends State<GameStory<G, S>> {
  final _status = ValueNotifier('');
  final _focusNode = FocusNode();

  /// The snapshot that [_game] continued from, if any.
  S? _from;
  late G _game = _create();

  G _create() => widget.create(_status, _from)
    ..camera.viewfinder.zoom = widget.zoom
    ..speed = widget.speed
    ..isPaused = !TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paused = !TickerMode.valuesOf(context).enabled;
    if (_game.isPaused != paused) {
      _game.isPaused = paused;
    }
  }

  @override
  void didUpdateWidget(GameStory<G, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.renderer != oldWidget.renderer ||
        widget.cache != oldWidget.cache) {
      // Take the snapshot here, because the old game is removed only after
      // the new one is built. A game that hasn't loaded yet hasn't continued
      // from its snapshot either, so the new game gets that same snapshot.
      if (_game.isLoaded) {
        _from = widget.snapshot?.call(_game);
      }
      _status.value = '';
      _game = _create();
      return;
    }
    _game
      ..camera.viewfinder.zoom = widget.zoom
      ..speed = widget.speed;
    widget.update?.call(_game);
  }

  @override
  void dispose() {
    _status.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Flame doesn't clip the game, so components drawn outside it would
        // paint over the widgets around it.
        Expanded(
          child: ClipRect(
            child: Listener(
              onPointerDown: (_) => _focusNode.requestFocus(),
              child: GameWidget<G>(
                key: ObjectKey(_game),
                game: _game,
                focusNode: _focusNode,
                // Shows until the game has loaded, which for
                // flame_rasterizer's games includes loading their renderer
                // (ExampleRasterizer.onLoad).
                loadingBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
        if (widget.statusLines > 0) _StatusBar(_status, widget.statusLines),
      ],
    );
  }
}

/// The status bar, which shows the status in at most [lines] lines.
///
/// The bar is always [lines] lines tall, from the first frame and whatever
/// the status, so that the game keeps its size.
class const _StatusBar(
  final ValueListenable<String> status,
  final int lines,
) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: lines == 1 ? 2 : 6,
        ),
        child: Stack(
          children: [
            // Empty lines set the bar's height. The status draws over them,
            // so it can't change the height.
            Text('\n' * (lines - 1), style: style),
            Positioned.fill(
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (context, text, _) => Text(
                  text,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
