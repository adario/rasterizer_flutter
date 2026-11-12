// Checks the Tube Shooter game on a device:
//   flutter test integration_test/tube_shooter_test.dart -d <macos|emulator-5554>
//
// After a warm-up, it plays a round with the mesh renderer on a closed tube,
// an open one and a concave one, each with the glow on and off. A round is
// its zoom, two seconds of play without zappers, firing while sweeping round
// the rim, and its drop. Each game must load, draw and name its renderer in
// the status bar. With flame_rasterizer, its paths must draw in one run: a
// batch of entries, each a path placed in the frame, that the renderer draws
// together. The tube's paths must be made again every frame of the zoom and
// the drop. The test prints the status at the end of each phase, frame times
// included.
//
// Then it plays a whole game with each GPU renderer. None of its frames may
// fall back to the canvas renderer.
import 'package:flame/components.dart' show PathComponent;
import 'package:flame/game.dart';
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flame_rasterizer_example/stories/games/games.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/components/enemy_component.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/level.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube.dart';
import 'package:flame_rasterizer_example/stories/games/tube_shooter/tube_shooter_example.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/tube_shooter_whole_game.dart';
import 'renderer_status.dart';

const _timeout = Timeout(Duration(minutes: 1));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  // On a phone, in debug mode, the app's first frames are so slow that the
  // first game's zoom, which lasts a fixed time, has too few of them to count
  // its paths.
  testWidgets('warm-up', timeout: _timeout, (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TubeShooterStory(renderer: SvgRenderer.rasterizer, glow: true),
      ),
    );
    final gameWidget = find.byWidgetPredicate((w) => w is GameWidget);
    final game = tester
        .widget<GameWidget<TubeShooterExample>>(gameWidget)
        .game!;
    await pumpFor(tester, 10, done: () => game.state == TubeState.ready);
    expect(game.state, TubeState.ready);
    await tester.pumpWidget(const SizedBox());
  });

  for (final tube in [Tubes.octagon, Tubes.horseshoe, Tubes.star]) {
    final level = levels.indexWhere((level) => level.tube == tube);
    for (final glow in [true, false]) {
      testWidgets(
        '${tube.name}, glow ${glow ? 'on' : 'off'}',
        timeout: _timeout,
        (tester) async {
          await play(
            tester,
            binding,
            SvgRenderer.rasterizer,
            level,
            glow: glow,
          );
        },
      );
    }
  }

  for (final renderer in [
    SvgRenderer.rasterizer,
    SvgRenderer.rasterizerAtlas,
  ]) {
    // On the web, the canvas renderer draws the game, so there's no GPU
    // renderer to check.
    testWidgets(
      'a whole game with ${renderer.label}',
      timeout: _timeout,
      skip: kIsWeb,
      (tester) async {
        await wholeGame(tester, renderer);
      },
    );
  }
}

/// Pumps live frames for [seconds], or until [done], calling [onFrame] after
/// each.
Future<void> pumpFor(
  WidgetTester tester,
  double seconds, {
  bool Function()? done,
  void Function()? onFrame,
}) async {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames && !(done?.call() ?? false); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 16)),
    );
    await tester.pump();
    onFrame?.call();
  }
}

/// Plays a whole game with [renderer]'s GPU renderer, through all its states.
///
/// No frame may fall back to the canvas renderer or to `Canvas.drawPath`.
Future<void> wholeGame(WidgetTester tester, SvgRenderer renderer) async {
  // Initialize the renderer first: on OpenGL ES, the Renderer knob offers it
  // only once its self-test has passed.
  await tester.runAsync(() => RasterizerGpu.of(renderer.gpu).initialize());
  expect(renderer.supported, isTrue);
  await tester.pumpWidget(
    MaterialApp(home: TubeShooterStory(renderer: renderer, glow: true)),
  );
  final gameWidget = find.byWidgetPredicate((w) => w is GameWidget);
  final game = tester.widget<GameWidget<TubeShooterExample>>(gameWidget).game!;
  final watch = FallbackWatch(
    game as RasterizerTubeShooterExample,
    renderer.gpu,
  );
  await playWholeGame(
    tester,
    game,
    tester.getCenter(gameWidget),
    (seconds, {done}) => pumpFor(tester, seconds, done: done),
  );
  watch.stop();
  // ignore: avoid_print
  print(
    '  RASTERIZER_EXAMPLE ${renderer.name} whole game: ${watch.frames} '
    'frames, states ${watch.states.map((state) => state.name).join(' ')}, '
    'problems ${watch.problems}',
  );
  expect(watch.problems, isEmpty);
  expect(watch.states, TubeState.values.toSet());
  await tester.pumpWidget(const SizedBox());
}

/// Plays a round with [renderer], starting at [firstLevel], with [glow] on or
/// off, and checks it.
Future<void> play(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  SvgRenderer renderer,
  int firstLevel, {
  required bool glow,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TubeShooterStory(
        renderer: renderer,
        firstLevel: firstLevel,
        glow: glow,
      ),
    ),
  );
  final gameWidget = find.byWidgetPredicate((w) => w is GameWidget);
  final game = tester.widget<GameWidget<TubeShooterExample>>(gameWidget).game!;

  String status() => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .firstWhere((text) => text.contains(' · '), orElse: () => '');

  final lines = <String, String>{};

  /// Prints the status at the end of [phase], and keeps its line to check
  /// later.
  void report(String phase) {
    final tube = levels[firstLevel].tube.name;
    final on = glow ? 'on' : 'off';
    final line = '${renderer.name} $tube glow $on $phase: ${status()}';
    lines[phase] = line;
    // ignore: avoid_print
    print('  RASTERIZER_EXAMPLE $line · score ${game.score}');
    // On the web, prints go to the browser's console: flutter drive gets the
    // status from the response data instead.
    (binding.reportData ??= {})[line.substring(0, line.indexOf(':'))] =
        status();
  }

  // The frames of the zoom, or of the drop, after its first one, at whatever
  // frame rate.
  var frames = 0;
  // The frames among them whose tube paths were all made again.
  var remade = 0;
  Set<PathComponent>? last;

  /// Counts a frame of [state], and whether its tube paths are all new.
  void watchTube(TubeState state) {
    if (game.state != state) {
      last = null;
      return;
    }
    final paths = game.tubeGroup.children.whereType<PathComponent>().toSet();
    if (last != null) {
      frames++;
      if (paths.intersection(last!).isEmpty) {
        remade++;
      }
    }
    last = paths;
  }

  await pumpFor(
    tester,
    10,
    done: () => game.state == TubeState.ready,
    onFrame: () => watchTube(TubeState.zoom),
  );
  expect(game.state, TubeState.ready);
  expect(frames, greaterThan(0));
  expect(remade, frames);
  await settleRenderer(tester, renderer);
  // A zapper's pulse destroys the ship in the zapper's lane, at any depth,
  // and the sweep can cross that lane. No drop would follow, so remove the
  // zappers.
  for (final spawn in game.spawns.toList()) {
    if (spawn.kind == EnemyKind.zapper) {
      game.spawns.remove(spawn);
      spawn.removeFromParent();
    }
  }
  // Wait for the status to refresh, with the paths made during the zoom.
  await pumpFor(tester, 0.3);
  report('zoom');
  await tester.tapAt(tester.getCenter(gameWidget));
  await pumpFor(tester, 1, done: () => game.state == TubeState.play);
  expect(game.state, TubeState.play);
  // About two seconds of fire, sweeping round the rim.
  final gesture = await tester.startGesture(tester.getCenter(gameWidget));
  for (var i = 0; i < 120; i++) {
    await gesture.moveBy(Offset(i % 60 < 30 ? 8 : -8, 0));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 16)),
    );
    await tester.pump();
  }
  await gesture.up();
  report('play');
  // Remove the round's enemies, so that the drop starts.
  game.clearSpawns();
  for (final enemy in [...game.enemies]) {
    game.discard(enemy);
  }
  await pumpFor(tester, 1, done: () => game.state == TubeState.drop);
  expect(game.state, TubeState.drop);
  frames = remade = 0;
  last = null;
  await pumpFor(
    tester,
    10,
    done: () => game.state != TubeState.drop,
    onFrame: () => watchTube(TubeState.drop),
  );
  expect(game.state, isNot(TubeState.drop));
  expect(frames, greaterThan(0));
  expect(remade, frames);
  report('drop');

  for (final line in lines.values) {
    if (renderer == SvgRenderer.flameSvg) {
      expect(line, contains(": Flame's PathComponent · "));
    } else {
      expect(line, contains(': ${rendererStatus(renderer)}'));
      expect(line, contains(RegExp(r'\b1 run, ')));
    }
  }
  await tester.pumpWidget(const SizedBox());
}
