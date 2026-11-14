import 'dart:async';

import 'package:flame/game.dart';
import 'package:flame_rasterizer_example/commons/example_game.dart';
import 'package:flame_rasterizer_example/commons/game_story.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter_test/flutter_test.dart';

/// A game that loads once [loads] completes, and then counts its frames on
/// from [from].
class _CountingGame(
  final int? from,
  final Future<void> loads, {
  @override required final ValueNotifier<String> status,
}) extends FlameGame with StoryGame {
  /// The frames counted, which a snapshot taken while it loads can't read.
  late int count;

  @override
  double speed = 1;

  @override
  String get rendererText => '';

  @override
  Iterable<String> get rendererStats => const [];

  @override
  Future<void> onLoad() async {
    await loads;
    count = from ?? 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    count++;
  }
}

void main() {
  // A new renderer makes a new game, which goes on from a snapshot of the
  // old one. A game that hasn't loaded yet hands on the snapshot it got.
  testWidgets('a new renderer goes on from a snapshot', (tester) async {
    final loads = {for (final r in SvgRenderer.values) r: Completer<void>()};
    final games = <_CountingGame>[];
    Widget story(SvgRenderer renderer) => MaterialApp(
      home: GameStory<_CountingGame, int>(
        renderer: renderer,
        create: (status, from) {
          final game = _CountingGame(
            from,
            loads[renderer]!.future,
            status: status,
          );
          games.add(game);
          return game;
        },
        snapshot: (game) => game.count,
      ),
    );

    loads[SvgRenderer.rasterizer]!.complete();
    await tester.pumpWidget(story(SvgRenderer.rasterizer));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final first = games.single;
    expect(first.from, isNull);
    expect(first.count, greaterThan(0));

    // The next game doesn't load yet. The first counts the switch's frame,
    // before the snapshot, and is then removed.
    await tester.pumpWidget(story(SvgRenderer.rasterizerCanvas));
    expect(games, hasLength(2));
    expect(first.isRemoved, isTrue);
    final count = first.count;
    final loading = games.last;
    expect(loading.from, count);
    await tester.pump(const Duration(milliseconds: 16));
    expect(loading.isLoaded, isFalse);

    // Its snapshot would throw, as it has no count yet.
    await tester.pumpWidget(story(SvgRenderer.flameSvg));
    expect(games, hasLength(3));
    final last = games.last;
    expect(last.from, count);
    loads[SvgRenderer.flameSvg]!.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(last.isLoaded, isTrue);
    expect(last.count, greaterThan(count));
    await tester.pumpWidget(const SizedBox());
  });
}
