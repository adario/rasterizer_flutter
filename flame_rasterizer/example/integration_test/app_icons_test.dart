// Captures the standalone games' app icons on macOS, for
// tool/make_icons.py, which runs it:
//   flutter test integration_test/app_icons_test.dart -d macos
//
// Each game runs with its standalone app's settings at the start, in a
// square of 512 by 512, until the first frame that shows READY. Then its
// world stops, the texts over it go, READY and the HUD, and the square is
// saved at 1024 by 1024 as <game>.png, in the folder that the test prints.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show TextComponent;
import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/commons/vector_text_component.dart';
import 'package:flame_rasterizer_example/main_revolute_pinball.dart';
import 'package:flame_rasterizer_example/main_tube_runner.dart';
import 'package:flame_rasterizer_example/main_tube_shooter.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
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
