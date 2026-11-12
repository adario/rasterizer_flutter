// Checks SvgHitbox, in flutter_tester. From this package's folder:
//   flutter test test/hitbox_test.dart
//
// The hitbox takes the shape of an SVG's paths, from the SVG's outline, which
// is parsed whatever the backend of the SVG's import. It's stretched to its
// component's size, as the component draws the SVG. It collides along the
// paths, not along their rectangle.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:math' show pi;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/geometry.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String svg) => Uint8List.fromList(utf8.encode(svg));

// A filled square from 2, 2 to 8, 8 in a 10 × 10 viewBox.
final _square = _bytes(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" '
  'viewBox="0 0 10 10"><rect x="2" y="2" width="6" height="6" '
  'fill="#ff0000"/></svg>',
);

// A filled triangle over the top left half of its 10 × 10 viewBox.
final _triangle = _bytes(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" '
  'viewBox="0 0 10 10"><path d="M0 0 L10 0 L0 10 Z" fill="#ff0000"/></svg>',
);

// A filled circle and a filled bar side by side in a 10 × 10 viewBox.
final _circleAndBar = _bytes(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" '
  'viewBox="0 0 10 10"><circle cx="3" cy="5" r="2.5" fill="#ff0000"/> '
  '<rect x="6" y="2" width="3" height="6" fill="#ff0000"/></svg>',
);

class _Game() extends FlameGame with HasCollisionDetection;

class _Shape(RasterizerSvg svg, {required super.position})
    extends RasterizerSvgComponent
    with CollisionCallbacks {
  this : super(svg: svg, size: Vector2.all(10)) {
    add(SvgHitbox(svg.outline, size: size));
  }

  final collisions = <PositionComponent>[];

  @override
  void onCollisionStart(List<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    collisions.add(other);
  }
}

/// A game loaded and mounted, as GameWidget does, without a widget.
Future<_Game> _mounted(List<Component> children) async {
  final game = _Game()..onGameResize(Vector2.all(100));
  // ignore: invalid_use_of_internal_member
  await game.load();
  // ignore: invalid_use_of_internal_member
  game.mount();
  game.update(0);
  game.world.addAll(children);
  await game.ready();
  return game;
}

/// The bounds of [hitbox]'s polygons, in the game's coordinates.
Rect _bounds(PathHitbox hitbox) {
  final vertices = hitbox.globalPolygons().expand((p) => p);
  final xs = vertices.map((v) => v.x);
  final ys = vertices.map((v) => v.y);
  return Rect.fromLTRB(
    xs.reduce((a, b) => a < b ? a : b),
    ys.reduce((a, b) => a < b ? a : b),
    xs.reduce((a, b) => a > b ? a : b),
    ys.reduce((a, b) => a > b ? a : b),
  );
}

void main() {
  for (final backend in RasterizerBackend.values) {
    test(
      "a ${backend.name} SVG's outline is its paths, in its coordinates",
      () {
        final svg = RasterizerSvg.debugFromBytes(_square, backend);
        expect(svg.outline.path.getBounds(), const Rect.fromLTRB(2, 2, 8, 8));
        expect(svg.outline.rect, svg.rect);
        svg.dispose();
      },
    );
  }

  test(
    "it's stretched to its component's size, again as that changes",
    () async {
      final svg = RasterizerSvg.fromBytes(_square);
      final component = RasterizerSvgComponent(
        svg: svg,
        position: Vector2(10, 20),
        size: Vector2(40, 20),
      );
      final hitbox = SvgHitbox(svg.outline, size: component.size);
      component.add(hitbox);
      await _mounted([component]);
      // 2 to 8 of 10 across 40 × 20, from 10, 20.
      expect(_bounds(hitbox), const Rect.fromLTRB(18, 24, 42, 36));
      component.size = Vector2.all(20);
      expect(_bounds(hitbox), const Rect.fromLTRB(14, 24, 26, 36));
      svg.dispose();
    },
  );

  test(
    "its aabb is its polygons' bounds, as it moves and turns by right angles, "
    'and holds them at other angles',
    () async {
      final svg = RasterizerSvg.fromBytes(_triangle);
      final component = RasterizerSvgComponent(
        svg: svg,
        position: Vector2(30, 40),
        size: Vector2(20, 10),
        anchor: Anchor.center,
      );
      final hitbox = SvgHitbox(svg.outline, size: component.size);
      component.add(hitbox);
      await _mounted([component]);
      Rect aabb() {
        final Aabb2(:min, :max) = hitbox.aabb;
        return Rect.fromLTRB(min.x, min.y, max.x, max.y);
      }

      // The box must be the polygons' bounds moved out by a few float32
      // steps, as points on a box's edges count as outside it.
      void expectBounds([String? reason]) {
        final box = aabb();
        final bounds = _bounds(hitbox);
        // A few float32 steps at the bounds' largest coordinate.
        final far = [
          bounds.left,
          bounds.top,
          bounds.right,
          bounds.bottom,
        ].fold(0.0, (m, v) => math.max(m, v.abs()));
        expect(
          box,
          rectMoreOrLessEquals(bounds, epsilon: 1e-5 * (far + 1)),
          reason: reason,
        );
        expect(box.left, lessThan(bounds.left), reason: reason);
        expect(box.top, lessThan(bounds.top), reason: reason);
        expect(box.right, greaterThan(bounds.right), reason: reason);
        expect(box.bottom, greaterThan(bounds.bottom), reason: reason);
      }

      for (final angle in [0.0, pi / 2, pi, -pi / 2]) {
        component.angle = angle;
        expectBounds('$angle');
      }
      component.position = Vector2(70, 15);
      expectBounds();
      // Far out, where a double's 1e-15 would be lost in a float32.
      component.position = Vector2(30000, -20000);
      expectBounds();
      component.position = Vector2(70, 15);
      // The triangle's bounds' 4th corner, turned, sticks out.
      component.angle = 0.5;
      final bounds = _bounds(hitbox);
      expect(aabb().expandToInclude(bounds), rectMoreOrLessEquals(aabb()));
      expect(aabb().height, greaterThan(bounds.height + 1));
      svg.dispose();
    },
  );

  test(
    "its aabb is its bounds' corners mapped by absolutePositionOf, under any "
    'chain of transforms',
    () async {
      final svg = RasterizerSvg.fromBytes(_triangle);
      final hitbox = SvgHitbox(svg.outline, size: Vector2(20, 10));
      final inner = RasterizerSvgComponent(
        svg: svg,
        size: Vector2(20, 10),
        anchor: Anchor.center,
        children: [hitbox],
      );
      final outer = PositionComponent(
        size: Vector2(30, 40),
        anchor: Anchor.bottomRight,
        // A component with no transform between them.
        children: [
          Component(children: [inner]),
        ],
      );
      await _mounted([outer]);
      final bounds = Rect.fromPoints(
        Offset.zero,
        Offset(hitbox.size.x, hitbox.size.y),
      );
      final random = math.Random(1);
      double next(double from, double to) =>
          from + (to - from) * random.nextDouble();
      for (var i = 0; i < 200; i++) {
        inner
          ..position.setValues(next(-50, 50), next(-50, 50))
          ..angle = next(-pi, pi)
          ..scale.setValues(next(-2, 2), next(-2, 2));
        outer
          ..position.setValues(next(-300, 300), next(-300, 300))
          ..angle = next(-pi, pi)
          ..scale.setValues(next(-3, 3), next(-3, 3));
        final corners = [
          for (final corner in [
            bounds.topLeft,
            bounds.topRight,
            bounds.bottomRight,
            bounds.bottomLeft,
          ])
            hitbox.absolutePositionOf(Vector2(corner.dx, corner.dy)),
        ];
        final xs = corners.map((v) => v.x);
        final ys = corners.map((v) => v.y);
        final Aabb2(:min, :max) = hitbox.aabb;
        // Within a few float32 steps, as Vector2 rounds each step's result
        // to a float32.
        const tolerance = 1e-3;
        expect(min.x, closeTo(xs.reduce(math.min), tolerance), reason: '$i');
        expect(min.y, closeTo(ys.reduce(math.min), tolerance), reason: '$i');
        expect(max.x, closeTo(xs.reduce(math.max), tolerance), reason: '$i');
        expect(max.y, closeTo(ys.reduce(math.max), tolerance), reason: '$i');
      }
      svg.dispose();
    },
  );

  test('two collide where their paths meet, not their rectangles', () async {
    final svg = RasterizerSvg.fromBytes(_triangle);
    final a = _Shape(svg, position: Vector2.zero());
    // Its rectangle overlaps a's, but its triangle's corner, at 6, 6, is past
    // a's diagonal.
    final b = _Shape(svg, position: Vector2.all(6));
    final game = await _mounted([a, b]);
    game.update(0);
    expect(a.collisions, isEmpty);
    expect(b.collisions, isEmpty);
    // Its corner, now at 4, 4, is inside a's triangle.
    b.position = Vector2.all(4);
    game.update(0);
    expect(a.collisions, [b]);
    expect(b.collisions, [a]);
    svg.dispose();
  });

  test('it collides with a circle across its edges, not one only in its '
      'rectangle', () async {
    final svg = RasterizerSvg.fromBytes(_square);
    final shape = _Shape(svg, position: Vector2.zero());
    CircleComponent circle(Vector2 center, double radius) => CircleComponent(
      position: center,
      radius: radius,
      anchor: Anchor.center,
      children: [CircleHitbox()],
    );
    // One circle crosses the square's left edge, at x = 2. The other lies in
    // the rectangle's top left corner, outside the square.
    final across = circle(Vector2(1, 5), 1.5);
    final corner = circle(Vector2(1, 1), 0.8);
    final game = await _mounted([shape, across, corner]);
    game.update(0);
    expect(shape.collisions, [across]);
    svg.dispose();
  });

  test('it acts as a PathHitbox of its outline sampled the same, however its '
      'parent is moved', () async {
    final svg = RasterizerSvg.fromBytes(_circleAndBar);
    final component = RasterizerSvgComponent(
      svg: svg,
      position: Vector2(50, 50),
      size: Vector2(40, 20),
      anchor: Anchor.center,
    );
    final hitbox = SvgHitbox(svg.outline, size: component.size);
    final pathHitbox = PathHitbox(
      path: svg.outline.path,
      sampling: hitbox.sampling,
      tolerance: hitbox.tolerance,
    );
    component.addAll([hitbox, pathHitbox]);
    await _mounted([component]);
    pathHitbox
      ..position.setFrom(hitbox.position)
      ..scale.setFrom(hitbox.scale);
    expect(hitbox.polygons, hasLength(2));
    expect(hitbox.polygons, pathHitbox.polygons);
    expect(hitbox.size, pathHitbox.size);
    expect(hitbox.path.getBounds(), pathHitbox.path.getBounds());
    expect(
      // ignore: invalid_use_of_protected_member
      hitbox.polygonsPath.getBounds(),
      // ignore: invalid_use_of_protected_member
      pathHitbox.polygonsPath.getBounds(),
    );
    List<(Vector2, Vector2)> edges(PathHitbox hitbox) => [
      for (final edge in hitbox.possibleIntersectionVertices(null))
        (edge.from.clone(), edge.to.clone()),
    ];
    for (final (angle, scale) in [
      (0.0, Vector2(1, 1)),
      (0.7, Vector2(1, 1)),
      (0.0, Vector2(-1, 1)),
      (2.0, Vector2(1.5, -2)),
    ]) {
      component
        ..angle = angle
        ..scale = scale;
      final reason = '$angle, $scale';
      expect(
        hitbox.globalPolygons(),
        pathHitbox.globalPolygons(),
        reason: reason,
      );
      expect(edges(hitbox), edges(pathHitbox), reason: reason);
      var inside = 0;
      // Off round numbers, so off the polygons' edges.
      for (var x = 0.37; x < 100; x += 1.5) {
        for (var y = 0.37; y < 100; y += 1.5) {
          final point = Vector2(x, y);
          final contains = pathHitbox.containsPoint(point);
          expect(hitbox.containsPoint(point), contains, reason: reason);
          inside += contains ? 1 : 0;
        }
      }
      expect(inside, greaterThan(0), reason: reason);
      for (var x = -1.13; x < 10; x += 0.5) {
        for (var y = -1.13; y < 10; y += 0.5) {
          final point = Vector2(x, y);
          expect(
            hitbox.containsLocalPoint(point),
            pathHitbox.containsLocalPoint(point),
            reason: reason,
          );
        }
      }
      var hits = 0;
      for (var k = 0.0; k <= 100; k += 5) {
        for (final ray in [
          Ray2(origin: Vector2(0, k), direction: Vector2(1, 0)),
          Ray2(origin: Vector2(k, 0), direction: Vector2(0, 1)),
        ]) {
          final hit = pathHitbox.rayIntersection(ray);
          final svgHit = hitbox.rayIntersection(ray);
          expect(svgHit?.intersectionPoint, hit?.intersectionPoint);
          expect(svgHit?.normal, hit?.normal);
          hits += hit == null ? 0 : 1;
        }
      }
      expect(hits, greaterThan(0), reason: reason);
    }
    svg.dispose();
  });

  test('hitboxes of an outline share its path, and its polygons for the last 8 '
      'sizes they were made for', () {
    final svg = RasterizerSvg.fromBytes(_circleAndBar);
    SvgHitbox hitbox(double side) =>
        SvgHitbox(svg.outline, size: Vector2.all(side));
    final first = hitbox(10);
    expect(hitbox(10).polygons, same(first.polygons));
    expect(hitbox(10).path, same(first.path));
    final larger = hitbox(20);
    expect(larger.polygons, isNot(same(first.polygons)));
    expect(larger.path, same(first.path));
    // Using 10's polygons again leaves 20's the oldest of 9 sizes, so they're
    // made again.
    hitbox(10);
    for (var side = 30.0; side <= 90; side += 10) {
      hitbox(side);
    }
    expect(hitbox(10).polygons, same(first.polygons));
    final again = hitbox(20);
    expect(again.polygons, isNot(same(larger.polygons)));
    expect(again.polygons, larger.polygons);
    svg.dispose();
  });
}
