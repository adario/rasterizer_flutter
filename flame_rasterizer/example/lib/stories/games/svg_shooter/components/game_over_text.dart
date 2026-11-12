import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/commons/example_game.dart';

/// The Game Over text, in StoryGame's style but larger, at the center of its
/// parent.
///
/// It stays there when the parent is resized.
class GameOverText() extends TextComponent<TextPaint> {
  static final _textRenderer = StoryGame.hudTextRenderer.copyWith(
    (style) => style.copyWith(fontSize: 48),
  );

  this
    : super(
        text: 'Game Over',
        anchor: Anchor.center,
        textRenderer: _textRenderer,
      );

  @override
  void onParentResize(Vector2 maxSize) {
    super.onParentResize(maxSize);
    position = maxSize / 2;
  }
}
