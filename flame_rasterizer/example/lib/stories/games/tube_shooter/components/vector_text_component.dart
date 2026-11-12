import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/font.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// A text in `TubeFont`, with capitals [capHeight] logical pixels high, in
/// [color].
///
/// It draws each glyph with a path component of the game's renderer. All the
/// components of a glyph share its path, so setting a new text only imports
/// the glyphs that no other text shows.
///
/// With a [line], the text sits at the bottom right of its parent, [line]
/// lines above the last one; without, at its middle. It keeps its place when
/// the parent is resized. Its priority puts it under the FPS counter, so that
/// it draws in the same run as the world.
class VectorTextComponent({
  required final double capHeight,
  String text = '',
  final int? line,
  final Color color = TubeColors.text,
}) extends PositionComponent with HasGameRef<TubeShooterExample> {
  this
    : super(
        anchor: line == null ? Anchor.center : Anchor.bottomRight,
        scale: Vector2.all(capHeight / TubeFont.capHeight),
        priority: -1,
      );

  /// From a line's baseline to the next's, in cap heights.
  static const lineSpacing = 1.6;

  /// The size every glyph is imported for: the largest text's cap height, at a
  /// device pixel ratio of 3.
  ///
  /// One size lets texts of every size share each glyph's import. Glyphs are
  /// straight lines, which flatten the same at any size, so the large size
  /// loses nothing.
  static const glyphMaxSize = 3 * TubeShooterExample.bannerCap;

  String get text => _text;
  String _text = text;

  set text(String value) {
    if (value == _text) {
      return;
    }
    _text = value;
    if (isLoaded) {
      _layOut();
    }
  }

  @override
  Future<void> onLoad() async => _layOut();

  @override
  void onParentResize(Vector2 maxSize) {
    super.onParentResize(maxSize);
    final line = this.line;
    if (line == null) {
      position = maxSize / 2;
    } else {
      position.setValues(
        maxSize.x - StoryGame.hudMargin,
        maxSize.y - StoryGame.hudMargin - line * lineSpacing * capHeight,
      );
    }
  }

  /// Replaces its glyphs' components with new ones for [text].
  void _layOut() {
    removeAll(children);
    size.setValues(TubeFont.widthOf(_text), TubeFont.capHeight);
    for (final (i, char) in _text.split('').indexed) {
      final glyph = TubeFont.glyph(char);
      if (glyph == null) {
        continue;
      }
      final bounds = glyph.getBounds();
      add(
        gameRef.pathComponent(
          glyph,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = TubeFont.stroke
            ..strokeCap = StrokeCap.square
            ..color = color,
          position: Vector2(i * TubeFont.advance + bounds.left, bounds.top),
          maxSize: glyphMaxSize,
        ),
      );
    }
  }
}
