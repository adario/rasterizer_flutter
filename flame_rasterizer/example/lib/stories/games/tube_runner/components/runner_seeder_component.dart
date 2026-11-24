import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/endless_tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';

/// A seeder, which climbs its lane toward the ship and lays its [spike]
/// behind it, as Tube Shooter's `SeederComponent` does, with the same shape
/// and colour.
///
/// The spike stays where it's laid, so it comes at the ship as the tube does,
/// and the seeder faster. The game moves it with [climb], and places it with
/// [placeAt] where the tube says it shows.
class RunnerSeederComponent(final Spike spike)
    extends PositionComponent
    with HasGameRef<TubeRunnerExample>, HasVisibility {
  this : super(priority: 1);

  /// How fast it climbs its lane, along the axis, in tube units a second.
  static const climbSpeed = 1.0;

  /// The component that draws its shape.
  late final PathComponent drawing;

  @override
  Future<void> onLoad() async {
    add(drawing = gameRef.shapeComponent(Shapes.seeder, TubeColors.seeder));
  }

  @override
  void update(double dt) {
    super.update(dt);
    gameRef.keepStroke(drawing);
  }

  /// Climbs its lane over [dt] seconds, laying the spike to where it gets.
  void climb(double dt) {
    spike.near -= climbSpeed * dt;
  }

  /// Shows it at [place], or hides it if null.
  void placeAt(SeederPlace? place) {
    isVisible = place != null;
    if (place == null) {
      return;
    }
    position.setValues(place.position.dx, place.position.dy);
    angle = place.angle;
    scale.splat(place.scale);
  }
}
