import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the renderer menu, and picks the entry that shows [text].
  Future<void> pick(WidgetTester tester, String text) async {
    await tester.tap(find.byType(DropdownButton<SvgRenderer>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the menu picks the renderer that the story gets', (
    tester,
  ) async {
    final renderers = <SvgRenderer>[];
    await tester.pumpWidget(
      StandaloneGame(
        title: 'Game',
        builder: (renderer) {
          renderers.add(renderer);
          return Text('story ${renderer.name}');
        },
      ),
    );
    expect(find.text('Game'), findsOneWidget);
    expect(renderers.last, SvgRenderer.firstChoice);
    await pick(tester, 'Flame SVG');
    expect(renderers.last, SvgRenderer.flameSvg);
    expect(find.text('story flameSvg'), findsOneWidget);
  });

  testWidgets('without SVGs, the menu shows Flame for Flame SVG', (
    tester,
  ) async {
    await tester.pumpWidget(
      StandaloneGame(
        title: 'Game',
        svgs: false,
        builder: (renderer) => Text('story ${renderer.name}'),
      ),
    );
    await pick(tester, 'Flame');
    expect(find.text('story flameSvg'), findsOneWidget);
    expect(find.text('Flame SVG'), findsNothing);
  });

  testWidgets('the story keeps the focus once the menu closes', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      StandaloneGame(
        title: 'Game',
        builder: (_) => Focus(
          focusNode: focusNode,
          autofocus: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await pick(tester, 'Flame SVG');
    expect(focusNode.hasFocus, isTrue);
  });
}
