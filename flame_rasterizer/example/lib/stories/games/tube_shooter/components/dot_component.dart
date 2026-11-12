import 'dart:ui';

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// A dot of [color], such as a star or an enemy waiting to come.
///
/// Its position is where it's drawn, and its scale is its width in world
/// units. A filled path scales with its transform, so dots of every size share
/// one imported path per colour.
abstract class DotComponent(final Color color)
    extends PositionComponent
    with HasGameRef<TubeShooterExample> {
  /// The component that draws it.
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.dotComponent(color));
    place();
  }

  @override
  void update(double dt) {
    super.update(dt);
    move(dt);
    place();
  }

  /// Moves it over [dt] seconds.
  void move(double dt) {}

  /// Sets its position and scale for where it is now.
  void place();

  /// Makes it [pixels] device pixels wide.
  void sizeTo(double pixels) => scale.splat(pixels * gameRef.view.devicePixel);
}
