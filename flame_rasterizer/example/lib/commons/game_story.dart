import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows the game that [create] makes, over a status bar, zoomed to [zoom]
/// and running at [speed].
///
/// A new [zoom] or [speed] changes the same game, as do the knobs that
/// [update] passes to it. Give this widget a key made of whatever needs a new
/// game, such as the renderer. The game has the keyboard focus at the start,
/// and a pointer down on it takes the focus back from the knobs.
class const GameStory<G extends StoryGame>({
  /// Creates the game, which shows its status in the notifier it gets.
  required final G Function(ValueNotifier<String> status) create,

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
  State<GameStory<G>> createState() => _GameStoryState<G>();
}

class _GameStoryState<G extends StoryGame>() extends State<GameStory<G>> {
  final _status = ValueNotifier('');
  final _focusNode = FocusNode();
  late final G _game = widget.create(_status)
    ..camera.viewfinder.zoom = widget.zoom
    ..speed = widget.speed;

  @override
  void didUpdateWidget(GameStory<G> oldWidget) {
    super.didUpdateWidget(oldWidget);
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
            child: GameWidget<G>(game: _game, focusNode: _focusNode),
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
