import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/commons/example_game.dart';

/// A text in StoryGame's style at the bottom right corner of its parent,
/// [line] lines above the bottom one.
///
/// It stays there when the parent is resized.
class BottomRightText({required final int line, super.text})
    extends TextComponent<TextPaint> {
  this
    : super(
        anchor: Anchor.bottomRight,
        textRenderer: StoryGame.hudTextRenderer,
      );

  @override
  void onParentResize(Vector2 maxSize) {
    super.onParentResize(maxSize);
    position.setValues(
      maxSize.x - StoryGame.hudMargin,
      maxSize.y - StoryGame.hudMargin - line * size.y,
    );
  }
}
