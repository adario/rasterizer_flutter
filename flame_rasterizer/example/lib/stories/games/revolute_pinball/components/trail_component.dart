import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';

/// A trail behind [_body]'s center of mass that lasts [_time] seconds, drawn
/// below everything else.
///
/// It adds one cubic curve per step, matching the body's positions and
/// velocities at both ends. From [_fadeStart] on, it fades out from its oldest
/// curve to its newest.
class TrailComponent(final BodyComponent _body)
    extends Component
    with HasGameRef<RevolutePinballExample> {
  this : super(priority: -1);

  static const _time = 1.0;

  /// When it starts fading, as a share of [_time].
  static const _fadeStart = 0.25;

  /// The width of the fade's edge, as a share of [_time].
  static const _edge = 0.3;

  static const _width = 0.2;

  late final _color = switch (_body) {
    SvgBody(:final color) => color,
    _ => _body.paint.color,
  };

  var _age = 0.0;
  Vector2? _position;
  Vector2? _velocity;
  final _curves = <({PathComponent curve, double age})>[];

  bool get over => _age >= _time;

  @override
  void update(double dt) {
    if (dt == 0) {
      return;
    }
    _age += dt;
    if (over) {
      removeFromParent();
      return;
    }
    if (_body.isLoaded && !_body.isRemoving && !_body.isRemoved) {
      _record(dt);
    }
    final front = (_age / _time - _fadeStart) / (1 - _fadeStart) * (1 + _edge);
    _curves.removeWhere((c) {
      final opacity = ((c.age / _time + _edge - front) / _edge).clamp(0.0, 1.0);
      c.curve.opacity = opacity;
      if (opacity == 0) {
        c.curve.removeFromParent();
      }
      return opacity == 0;
    });
  }

  /// Adds the curve from the last step's position to this one's, [dt]
  /// seconds later.
  void _record(double dt) {
    final p1 = _body.body.worldCenterOfMass;
    final v1 = _body.body.linearVelocity;
    final p0 = _position;
    final v0 = _velocity;
    _position = p1;
    _velocity = v1;
    if (p0 == null || v0 == null) {
      return;
    }
    final c0 = p0 + v0 * (dt / 3);
    final c1 = p1 - v1 * (dt / 3);
    final path = Path()
      ..moveTo(p0.x, p0.y)
      ..cubicTo(c0.x, c0.y, c1.x, c1.y, p1.x, p1.y);
    final bounds = path.getBounds();
    final curve = gameRef.pathComponent(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.round
        ..color = _color,
      position: bounds.topLeft.toVector2(),
      // At a device pixel ratio of up to 3.
      maxSize: 3 * gameRef.metersToPixels * (bounds.longestSide + _width),
    );
    _curves.add((curve: curve, age: _age));
    add(curve);
  }
}
