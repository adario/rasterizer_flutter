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
/// components of a glyph share its path. Setting a new text replaces only the
/// components of the characters that changed, and imports only the glyphs
/// that no other text shows.
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

  /// The text its glyphs show.
  String _laidOut = '';

  /// Its glyphs' components, by their characters' indices in [_laidOut]:
  /// null for a space.
  final _glyphs = <Component?>[];

  /// Replaces the components of the glyphs that changed with new ones for
  /// [text]. A character that stays in its place keeps its component.
  void _layOut() {
    size.setValues(TubeFont.widthOf(_text), TubeFont.capHeight);
    while (_glyphs.length > _text.length) {
      _glyphs.removeLast()?.removeFromParent();
    }
    for (final (i, char) in _text.split('').indexed) {
      if (i < _laidOut.length && _laidOut[i] == char) {
        continue;
      }
      final glyph = TubeFont.glyph(char);
      final component = glyph == null ? null : _glyphComponent(i, glyph);
      if (i < _glyphs.length) {
        _glyphs[i]?.removeFromParent();
        _glyphs[i] = component;
      } else {
        _glyphs.add(component);
      }
      if (component != null) {
        add(component);
      }
    }
    _laidOut = _text;
  }

  /// A component of [glyph] at index [i].
  Component _glyphComponent(int i, Path glyph) {
    final bounds = glyph.getBounds();
    return gameRef.pathComponent(
      glyph,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TubeFont.stroke
        ..strokeCap = StrokeCap.square
        ..color = color,
      position: Vector2(i * TubeFont.advance + bounds.left, bounds.top),
      maxSize: glyphMaxSize,
    );
  }
}
