// Captures the standalone games' app icons on macOS, for
// tool/make_icons.py, which runs it:
//   flutter test integration_test/app_icons_test.dart -d macos
//
// Each game runs with its standalone app's settings at the start, in a
// square of 512 by 512, until the first frame that shows READY. Then its
// world stops, the texts over it go, READY and the HUD, and the square is
// saved at 1024 by 1024 as <game>.png, in the folder that the test prints.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart' show TextComponent, Vector2;
import 'package:flame/game.dart' hide Matrix4;
import 'package:flame_forge2d/flame_forge2d.dart' show BodyComponent;
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/forge2d.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/main_revolute_pinball.dart';
import 'package:flame_rasterizer_example/main_tube_runner.dart';
import 'package:flame_rasterizer_example/main_tube_shooter.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/bucket_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/flipper_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/components/guide_component.dart';
import 'package:flame_rasterizer_example/stories/games/revolute_pinball/revolute_pinball_example.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_host.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The square's side, in logical pixels.
const _side = 512.0;

/// The icon's side, in pixels.
const _iconSide = 1024;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final renderer = SvgRenderer.firstChoice;

  // Each game's story, as its standalone app builds it at the start, but
  // without sounds.
  final games = <String, Widget>{
    'tube_shooter': () {
      const settings = TubeShooterSettings();
      return TubeShooterStory(
        renderer: renderer,
        firstLevel: settings.level,
        glow: settings.glow,
        sound: false,
        statusLines: 0,
      );
    }(),
    'revolute_pinball': () {
      const settings = RevolutePinballSettings();
      return RevolutePinballStory(
        renderer: renderer,
        pieces: settings.pieces,
        drops: settings.drops,
        sound: false,
        cache: renderer == SvgRenderer.flameSvg
            ? settings.cache
            : defaultSvgCache,
        statusLines: 0,
      );
    }(),
    'tube_runner': () {
      final settings = TubeRunnerSettings();
      return TubeRunnerStory(
        renderer: renderer,
        tube: settings.tube,
        sound: false,
        flightSpeed: settings.flightSpeed,
        statusLines: 0,
      );
    }(),
  };

  final folder = Directory.systemTemp.createTempSync('app_icons_');
  for (final MapEntry(key: name, value: story) in games.entries) {
    testWidgets('captures $name', timeout: const Timeout.factor(4), (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox.square(dimension: _side, child: story),
            ),
          ),
        ),
      );
      final gameWidget = find.byWidgetPredicate((w) => w is GameWidget);
      await _pumpUntil(tester, () => gameWidget.evaluate().isNotEmpty);
      final game = tester.widget<GameWidget>(gameWidget).game! as StoryGame;
      _prepare(game);
      bool ready() => game.camera.viewport.children
          .whereType<VectorTextComponent>()
          .any((text) => text.isMounted && text.text == 'READY');
      await _pumpUntil(tester, ready);
      expect(ready(), isTrue, reason: '$name never showed READY');
      // The world stays as it was in READY's first frame.
      game.speed = 0;
      for (final text in [
        ...game.camera.viewport.children.whereType<VectorTextComponent>(),
        ...game.camera.viewport.children.whereType<TextComponent>(),
      ]) {
        text.removeFromParent();
      }
      _stage(game);
      for (var i = 0; i < 10; i++) {
        await _pumpFrame(tester);
      }
      expect(
        game.camera.viewport.children.where(
          (c) => c is VectorTextComponent || c is TextComponent,
        ),
        isEmpty,
      );

      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: _iconSide / _side);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${folder.path}/$name.png')
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      final ratio = tester.view.devicePixelRatio;
      // ignore: avoid_print
      print('ICON ${file.path} (${renderer.name}, device pixel ratio $ratio)');
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// How many times as wide as in play the tube games' lines and shapes are in
/// their icons, which show them small.
const _iconLineWidths = 3.0;

/// How far the pinball's flippers and guides go up in its icon, and its
/// wheel down, in the table's heights.
const _flippersLift = 0.08;
const _wheelDrop = 0.23;

/// How far the pinball's icon zooms in, about the middle of its wheel and
/// flippers.
const _pinballZoom = 2.0;

/// Readies [game] for its icon as soon as it's made, before it loads.
void _prepare(StoryGame game) {
  if (game is TubeHost) {
    game.view.lineWidths = _iconLineWidths;
  }
}

/// Stages [game]'s icon, once its world has stopped at READY: the pinball's
/// flippers and guides go up, so that the icon shows them whole, its wheel
/// down, closer to them, and its buckets go. Then the camera zooms in on the
/// wheel and the flippers.
void _stage(StoryGame game) {
  if (game is! RevolutePinballExample) {
    return;
  }
  final height = game.size.y / game.metersToPixels;
  void move(BodyComponent component, double dy) => component.body.setTransform(
    component.body.position + Vector2(0, dy),
    component.body.rotation,
  );
  // Where the wheel and the flippers are in the world, once moved.
  Rect? content;
  void include(BodyComponent component, Path outline) {
    final body = component.body;
    final transform = Matrix4.identity()
      ..translateByDouble(body.position.x, body.position.y, 0, 1)
      ..rotateZ(body.angle);
    final bounds = outline.transform(transform.storage).getBounds();
    content = content?.expandToInclude(bounds) ?? bounds;
  }

  for (final component in game.world.descendants().toList()) {
    switch (component) {
      case FlipperComponent():
        move(component, -_flippersLift * height);
        include(component, component.glowPath);
      case GuideComponent():
        component.parent!.add(
          GuideComponent(_lifted(component.outline, _flippersLift * height)),
        );
        component.removeFromParent();
      case CircleShuffler():
        move(component, _wheelDrop * height);
        include(component, component.glowPath);
      case BucketComponent():
        component.removeFromParent();
    }
  }
  final center = content!.center;
  // The zoomed square shows them whole.
  final shown = game.size / game.metersToPixels / _pinballZoom;
  expect(content!.width, lessThan(shown.x), reason: 'too wide to zoom in');
  expect(content!.height, lessThan(shown.y), reason: 'too tall to zoom in');
  game.camera.viewfinder
    ..position = Vector2(center.dx, center.dy)
    ..zoom = _pinballZoom;
}

/// Returns a guide's [outline], [lift] meters higher, but still down to the
/// table's bottom, so that its bottom edge stays out of the icon: the recess's
/// end goes up, and a wall goes down from it to where it was.
List<Vector2> _lifted(List<Vector2> outline, double lift) {
  final bottom = outline.map((p) => p.y).reduce(math.max);
  final side = outline.map((p) => p.x.abs()).reduce(math.max);
  bool atBottom(Vector2 p) => (p.y - bottom).abs() < 1e-6;
  bool isCorner(Vector2 p) => atBottom(p) && (p.x.abs() - side).abs() < 1e-6;
  final up = Vector2(0, -lift);
  final n = outline.length;
  return [
    for (var i = 0; i < n; i++)
      ...switch (outline[i]) {
        final p when isCorner(p) => [p],
        // The recess's end, beside the corner: up, then down, from the
        // recess's side.
        final p when atBottom(p) && isCorner(outline[(i + 1) % n]) => [
          p + up,
          p,
        ],
        final p when atBottom(p) => [p, p + up],
        final p => [p + up],
      },
  ];
}

/// Pumps a live frame, about 16 ms after the last.
Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 16)),
  );
  await tester.pump();
}

/// Pumps live frames until [done], for at most 30 seconds.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 30 * 60 && !done(); i++) {
    await _pumpFrame(tester);
  }
}
