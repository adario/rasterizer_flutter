import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter/foundation.dart';

/// Shows the game that [create] makes, over a status bar, zoomed to [zoom]
/// and running at [speed].
///
/// A new [renderer] makes a new game, from a snapshot of the old one that
/// [snapshot] takes, so that it looks the same. A new [zoom] or [speed]
/// changes the same game, as do the knobs that [update] passes to it. Give
/// this widget a key made of whatever else needs a new game, which starts
/// afresh. The game has the keyboard focus at the start, and a pointer down
/// on it takes the focus back from the knobs.
class const GameStory<G extends StoryGame, S extends Object>({
  /// The renderer that the game draws with.
  required final SvgRenderer renderer,

  /// Creates the game, which shows its status in the notifier it gets, and
  /// goes on from the snapshot it gets, if any.
  required final G Function(ValueNotifier<String> status, S? from) create,

  /// Takes a snapshot of the game, for a new game with another renderer to go
  /// on from. Without it, the new game starts afresh.
  final S Function(G game)? snapshot,

  /// Passes the story's other knobs to the running game, each time the story
  /// rebuilds.
  final void Function(G game)? update,

  /// The camera's zoom.
  final double zoom = 1,

  /// The world's speed, from 0, which stands still, to 2.
  final double speed = 1,
  super.key,
}) extends StatefulWidget {
  @override
  State<GameStory<G, S>> createState() => _GameStoryState<G, S>();
}

class _GameStoryState<G extends StoryGame, S extends Object>()
    extends State<GameStory<G, S>> {
  final _status = ValueNotifier('');
  final _focusNode = FocusNode();

  /// The snapshot that [_game] went on from, if any.
  S? _from;
  late G _game = _create();

  G _create() => widget.create(_status, _from)
    ..camera.viewfinder.zoom = widget.zoom
    ..speed = widget.speed;

  @override
  void didUpdateWidget(GameStory<G, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.renderer != oldWidget.renderer) {
      // The snapshot is taken here, as the old game is removed only after the
      // new one is built. A game that hasn't loaded yet hasn't gone on from
      // its snapshot either, so it hands that one on.
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
        Expanded(
          child: Listener(
            onPointerDown: (_) => _focusNode.requestFocus(),
            child: GameWidget<G>(
              key: ObjectKey(_game),
              game: _game,
              focusNode: _focusNode,
            ),
          ),
        ),
        _StatusBar(_status),
      ],
    );
  }
}

/// The status bar, which shows the status in at most two lines.
///
/// The bar is always two lines tall, from the first frame and whatever the
/// status, so that the game keeps its size.
class const _StatusBar(final ValueListenable<String> status)
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Stack(
          children: [
            // Two empty lines set the bar's height. The status draws over
            // them, so it can't change the height.
            Text('\n', style: style),
            Positioned.fill(
              child: ValueListenableBuilder<String>(
                valueListenable: status,
                builder: (context, text, _) => Text(
                  text,
                  maxLines: 2,
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
