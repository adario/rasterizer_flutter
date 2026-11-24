import 'dart:ui' show StrokeCap, StrokeJoin;

import 'package:flame/components.dart';

import 'package:flame_rasterizer_example/stories/games/tube_runner/components/tube_placed.dart';
import 'package:flame_rasterizer_example/stories/games/tube_runner/tube_runner_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';

/// An enemy of [kind], which comes at the far end of [spawnLane] and climbs
/// the tube toward the ship, with the shape and colour of Tube Shooter's, and
/// [strokeWidths] as wide a stroke.
///
/// The game moves it with [climb], and places it with [placeAt] where the
/// tube says it shows. It goes once it passes the ship.
///
/// For [flashTime] after it comes, it glows in its colour, fading out as
/// [flash] says: with [TubeRunnerExample.glowShape] if the renderer draws
/// glows, or else under a wider, see-through copy of its shape, as wide as
/// that glow.
abstract class RunnerEnemyComponent(
  final EnemyKind kind,
  final int spawnLane,
) extends PositionComponent
    with HasGameRef<TubeRunnerExample>, HasVisibility, TubePlaced {
  this : super(priority: 1);

  /// How fast every kind climbs its lane, along the axis, in tube units a
  /// second.
  static const climbSpeed = 1.0;

  /// How many times as wide as the ship's its stroke is.
  static const strokeWidths = 2.0;

  /// How long it flashes after it comes, in seconds of the game.
  static const flashTime = 1.5;

  /// Where it is along the axis, in tube units.
  double get at;

  /// Where it was along the axis before it last climbed.
  late double previousAt = at;

  /// The lane it counts as in, for hits.
  int get currentLane;

  /// How long it has climbed, in seconds of the game.
  double _age = 0;

  /// How strong its flash is: 1 as it comes, fading to 0 over [flashTime].
  double get flash => _age < flashTime ? 1 - _age / flashTime : 0;

  /// The component that draws its shape.
  late final PathComponent drawing;

  /// The component that draws the copy of its shape under it, while it
  /// flashes, if the renderer doesn't draw the glow.
  PathComponent? _halo;

  /// How many times as wide as the ship's the halo's stroke is.
  static const _haloStroke =
      strokeWidths * 2 * TubeRunnerExample.shapeGlowWidths;

  @override
  Future<void> onLoad() async {
    if (!gameRef.rendererGlows) {
      add(
        _halo =
            gameRef.shapeComponent(kind.shape, kind.color, widths: _haloStroke)
              ..paint.strokeJoin = StrokeJoin.round
              ..paint.strokeCap = StrokeCap.round
              ..opacity = 0,
      );
    }
    add(
      drawing = gameRef.shapeComponent(
        kind.shape,
        kind.color,
        widths: strokeWidths,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    gameRef
      ..keepStroke(drawing, widths: strokeWidths)
      ..glowShape(drawing, flash, kind.color);
    final halo = _halo;
    if (halo == null) {
      return;
    }
    if (flash == 0) {
      halo.removeFromParent();
      _halo = null;
      return;
    }
    gameRef.keepStroke(halo, widths: _haloStroke);
    halo.opacity = TubeRunnerExample.haloAlpha * flash;
  }

  /// Climbs over [dt] seconds, as [move] says.
  void climb(double dt) {
    _age += dt;
    previousAt = at;
    move(dt);
  }

  /// Moves it over [dt] seconds, as its kind does.
  void move(double dt);
}
