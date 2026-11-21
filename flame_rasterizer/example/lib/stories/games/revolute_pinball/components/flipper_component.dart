import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' hide World;
import 'package:flame_rasterizer_example/commons/example_colors.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/outlined.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';

/// A flipper [_length] meters from its pivot's center to its tip's, on the
/// left of its [_pivot] if [_side] is 1, or on the right if -1. It lies in a
/// guide's recess at rest, its flat top along the guide. Holding it kicks it
/// up, and a motor holds it at the top. Released, it falls back.
class FlipperComponent(
  final Vector2 _pivot,
  final double _length,
  final int _side,
) extends BodyComponent with GlowingBody, Outlined {
  this : super(paint: Paint()..color = ExampleColors.dynamicColor(0));

  /// The radii of its round ends.
  static const radius = 0.6;
  static const tipRadius = 0.3;

  /// The room between it and its guide's recess.
  static const gap = 0.1;

  static const _segments = 16;

  /// For a left flipper with its pivot at the origin and its top along the
  /// x axis: its tip's center, and the angle of its bottom edge's normal.
  static Vector2 tipCenter(double length) =>
      Vector2(length, tipRadius - radius);
  static double bottomAngle(double length) =>
      2 * math.atan2(tipRadius - radius, length) + math.pi / 2;

  /// The arc around [center] from angle [from] to [to].
  static List<Vector2> arc(
    Vector2 center,
    double radius,
    double from,
    double to,
  ) => List.generate(_segments + 1, (i) {
    final a = from + (to - from) * i / _segments;
    return center + Vector2(math.cos(a), math.sin(a)) * radius;
  });

  @override
  late final outline = () {
    final bottom = bottomAngle(_length);
    final left = [
      ...arc(Vector2.zero(), radius, bottom, 3 * math.pi / 2),
      ...arc(tipCenter(_length), tipRadius, -math.pi / 2, bottom),
    ];
    return _side < 0
        ? left
        : [for (final v in left.reversed) Vector2(-v.x, v.y)];
  }();

  /// The kick's angular speed, and the motor's, in radians a second.
  static const _kickSpeed = 15.0;

  /// Its angle above the horizontal when fully kicked.
  static const _upAngle = 40 * math.pi / 180;

  /// How much faster than the other bodies it falls.
  static const _gravityScale = 16.0;

  /// Less than the other bodies', so that they slow it as it hits them.
  static const _density = 0.3;

  final _holders = <Object>{};
  late final RevoluteJoint _joint;

  /// The bodies touching it.
  final touching = <Body>{};

  /// Whether it's swinging up.
  bool get kicking => isLoaded && _side * body.angularVelocity > 1;

  /// Updates [touching] with [events].
  void track(ContactEvents events) {
    if (!isLoaded) {
      return;
    }
    Body? other(Shape a, Shape b) => !a.isValid || !b.isValid
        ? null
        : (a.body == body ? b.body : (b.body == body ? a.body : null));
    for (final event in events.begin) {
      if (other(event.shapeA, event.shapeB) case final other?) {
        touching.add(other);
      }
    }
    for (final event in events.end) {
      if (other(event.shapeA, event.shapeB) case final other?) {
        touching.remove(other);
      }
    }
    touching.removeWhere((other) => !other.isValid);
  }

  /// Whether it kicked.
  bool hold(Object holder) {
    final kick = _holders.isEmpty && isLoaded;
    if (kick) {
      body.angularVelocity += _side * _kickSpeed;
      _joint.motorEnabled = true;
    }
    _holders.add(holder);
    return kick;
  }

  void release(Object holder) {
    if (_holders.remove(holder) && _holders.isEmpty && isLoaded) {
      _joint.motorEnabled = false;
      body.isAwake = true;
    }
  }

  @override
  Body createBody() {
    const angle = RevolutePinballExample.restAngle;
    final body = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _pivot,
        rotation: Rot.fromAngle(-_side * angle),
        gravityScale: _gravityScale,
        isBullet: true,
      ),
    );
    addPieces(
      body,
      ShapeDef(
        // Below the balls' restitution, so that only SVG bodies bounce more.
        material: SurfaceMaterial(friction: 0.1, restitution: 0.6),
        density: _density,
        enableContactEvents: true,
      ),
    );
    _joint = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: world.createBody(BodyDef()),
        bodyB: body,
        localAnchorA: _pivot.clone(),
        enableLimit: true,
        lowerAngle: math.min(-_side * angle, _side * _upAngle),
        upperAngle: math.max(-_side * angle, _side * _upAngle),
        motorSpeed: _side * _kickSpeed,
        maxMotorTorque: 2 * body.mass * 10 * _gravityScale * _length,
      ),
    );
    return body;
  }
}
