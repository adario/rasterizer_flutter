import 'dart:ui';

/// The palette of Flame's Forge2D examples. Svg Shooter's enemies use its
/// colors too.
abstract final class ExampleColors() {
  /// The Forge2D games' background.
  static const background = Color(0xFF0B1020);

  /// The color of the bodies that don't move, such as the walls.
  static const slate = Color(0xFF64748B);

  /// The colors of the bodies that move, which they take in turn.
  static const dynamics = [
    Color(0xFF7C9CFF),
    Color(0xFF38BDF8),
    Color(0xFFFBBF24),
    Color(0xFFFB7185),
    Color(0xFF34D399),
    Color(0xFFA78BFA),
  ];

  /// The color of the body at [index], cycling through [dynamics].
  static Color dynamicColor(int index) => dynamics[index % dynamics.length];
}
