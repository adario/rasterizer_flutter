import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// Draws the tube's lines, and the ship's [lane] over them in the ship's
/// colour, but for while the ship arrives from a run, when the run draws
/// them.
///
/// flame_rasterizer treats a path as immutable, so whenever the view changes,
/// this makes both paths again, each with a new component in the game's tube
/// group. The view changes on every frame of the zoom and the drop, and when
/// the window or the Zoom knob changes. The lane's path also changes as the
/// ship changes lanes.
///
/// Its priority makes it update after the components that move, so that it
/// draws the view they moved in.
class TubeComponent() extends Component with HasGameRef<TubeShooterExample> {
  this : super(priority: 10);

  /// The lane to show over the tube, if any: the ship's, in play.
  int? lane;

  PathComponent? _tube;
  PathComponent? _lane;
  int _version = -1;
  int? _shownLane;
  bool _hidden = false;

  @override
  void update(double dt) {
    super.update(dt);
    final view = gameRef.view;
    final hidden = gameRef.state == TubeState.arrive;
    final changed = view.version != _version || hidden != _hidden;
    if (changed) {
      _version = view.version;
      _hidden = hidden;
      _tube = gameRef.replacePath(
        _tube,
        hidden ? null : view.tubePath(),
        gameRef.level.color,
      );
    }
    final lane = hidden ? null : this.lane;
    if (changed || lane != _shownLane) {
      _shownLane = lane;
      _lane = gameRef.replacePath(
        _lane,
        lane == null ? null : view.lanePath(lane),
        TubeColors.ship,
        priority: 1,
      );
    }
  }
}
