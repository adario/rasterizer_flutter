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
/// up with a spring, which holds it at the top. Released, it falls back,
/// and bounces.
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

  /// The collision group of the flippers and the guides, which don't
  /// collide, so that a kick, which stretches its joint, doesn't rub the
  /// flipper against its recess.
  static const group = -1;

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

  /// The spring that kicks it up and holds it there: its frequency, in
  /// hertz, and its damping ratio, around the pivot, so that it's up in
  /// about 80 ms, and rebounds about 4°.
  static const _kickHertz = 6.0;
  static const _kickDamping = 0.55;

  /// Its angle above the horizontal when fully kicked, and the room above
  /// it for the rebound.
  static const _upAngle = 40 * math.pi / 180;
  static const _reboundAngle = 5 * math.pi / 180;

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
      _joint.springEnabled = true;
      body.isAwake = true;
    }
    _holders.add(holder);
    return kick;
  }

  void release(Object holder) {
    if (_holders.remove(holder) && _holders.isEmpty && isLoaded) {
      _joint.springEnabled = false;
      body.isAwake = true;
    }
  }

  /// Releases it from all its holders.
  void releaseAll() => _holders.toList().forEach(release);

  /// The share of its fall's speed that it bounces back up with as it lands
  /// at rest, from a fall faster than [_minBounce] radians a second.
  static const _bounce = 0.3;
  static const _minBounce = 3.0;

  /// How fast it was falling in the last step, in radians a second.
  double _falling = 0;

  @override
  void update(double dt) {
    super.update(dt);
    final falling = -_side * body.angularVelocity;
    final atRest =
        (_joint.angle + _side * RevolutePinballExample.restAngle).abs() < 0.01;
    if (_holders.isEmpty && atRest && _falling > _minBounce && falling < 1) {
      // Around the pivot, so that the joint doesn't take most of it away.
      final speed = _side * _bounce * _falling;
      final arm = body.worldCenterOfMass - _pivot;
      body
        ..angularVelocity = speed
        ..linearVelocity = Vector2(-arm.y, arm.x) * speed;
      _falling = 0;
    } else {
      _falling = falling;
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
        filter: Filter(groupIndex: group),
        enableContactEvents: true,
      ),
    );
    // Box2D's spring works on the inertia around the center of mass, so it's
    // set stiffer, as for the inertia around the pivot.
    final inertia = body.rotationalInertia;
    final stiffer = math.sqrt(
      (inertia + body.mass * body.localCenterOfMass.length2) / inertia,
    );
    const up = _upAngle + _reboundAngle;
    _joint = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: world.createBody(BodyDef()),
        bodyB: body,
        localAnchorA: _pivot.clone(),
        enableLimit: true,
        lowerAngle: math.min(-_side * angle, _side * up),
        upperAngle: math.max(-_side * angle, _side * up),
        targetAngle: _side * _upAngle,
        hertz: _kickHertz * stiffer,
        dampingRatio: _kickDamping * stiffer,
      ),
    );
    return body;
  }
}
