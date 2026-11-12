import 'dart:math' as math;

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_shooter/shapes.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';

/// Draws the spikes, at most one per lane, each reaching from the far end
/// toward the rim.
///
/// All the spikes make one path. Whenever a spike grows or shortens, or the
/// view changes, this makes the path again, with a new component in the game's
/// tube group.
class SpikesComponent() extends Component with HasGameRef<TubeShooterExample> {
  this : super(priority: 10);

  /// The length of each lane's spike, 0 for none.
  final lengths = List<double>.filled(Tubes.mostLanes, 0);

  PathComponent? _spikes;
  int _version = -1;
  bool _changed = false;

  /// The depth of [lane]'s spike's tip, or null if it has none.
  double? tipOf(int lane) =>
      lengths[lane] > 0 ? Tube.depth - lengths[lane] : null;

  /// Grows [lane]'s spike to [length], if it's shorter.
  void grow(int lane, double length) {
    if (length > lengths[lane]) {
      lengths[lane] = math.min(length, Tube.depth);
      _changed = true;
    }
  }

  /// Shortens [lane]'s spike by [by].
  void shorten(int lane, double by) {
    lengths[lane] = math.max(0, lengths[lane] - by);
    _changed = true;
  }

  void clear() {
    lengths.fillRange(0, lengths.length, 0);
    _changed = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final view = gameRef.view;
    if (!_changed && view.version == _version) {
      return;
    }
    _changed = false;
    _version = view.version;
    _spikes = gameRef.replacePath(
      _spikes,
      lengths.any((length) => length > 0) ? view.spikesPath(lengths) : null,
      TubeColors.spikes,
      priority: 2,
    );
  }
}
