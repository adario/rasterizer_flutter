import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/shooter_mode.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';

/// Draws the tube's lines, with the ship's [lane] over them in the ship's
/// colour.
///
/// While the ship arrives from a run, this draws neither, because the run
/// draws them.
///
/// flame_rasterizer treats a path as immutable, so whenever the view changes,
/// this rebuilds both paths, each as a new component in the game's tube group.
/// The view changes on every frame of the zoom and the drop, and when the
/// window or the Zoom knob changes. The lane's path also changes when the ship
/// moves to another lane.
///
/// Its priority makes it update after the components that move, so that it
/// draws the view they moved in.
class TubeComponent()
    extends Component
    with HasGameRef<TubeHost>, InShooterMode {
  this : super(priority: 10);

  /// The lane to highlight over the tube, if any: the ship's lane during play.
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
    final hidden = shooter.state == TubeState.arrive;
    final changed = view.version != _version || hidden != _hidden;
    if (changed) {
      _version = view.version;
      _hidden = hidden;
      _tube = shooter.replacePath(
        _tube,
        hidden ? null : view.tubePath(),
        shooter.level.color,
      );
    }
    final lane = hidden ? null : this.lane;
    if (changed || lane != _shownLane) {
      _shownLane = lane;
      _lane = shooter.replacePath(
        _lane,
        lane == null ? null : view.lanePath(lane),
        TubeColors.ship,
        priority: 1,
      );
    }
  }
}
