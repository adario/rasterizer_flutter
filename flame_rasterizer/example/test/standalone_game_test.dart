import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/commons/standalone_game.dart';
import 'package:flame_rasterizer_example/commons/svg_renderers.dart';
import 'package:flutter_test/flutter_test.dart';

/// A game's settings, for the tests.
typedef _Settings = ({bool sound});

/// A standalone game whose story shows its renderer and settings, and whose
/// dialog has a Sound switch. [builder] builds the story instead, if given.
Widget _game({
  bool svgs = true,
  List<SvgRenderer>? renderers,
  List<bool>? ticking,
  Widget Function()? builder,
}) {
  return StandaloneGame<_Settings>(
    title: 'Game',
    svgs: svgs,
    settings: (sound: true),
    builder: (renderer, settings, _) {
      renderers?.add(renderer);
      return builder?.call() ??
          Builder(
            builder: (context) {
              ticking?.add(TickerMode.valuesOf(context).enabled);
              return Text('story ${renderer.name} ${settings.sound}');
            },
          );
    },
    settingsBuilder: (renderer, settings, onChanged) => [
      SettingSwitch(
        label: 'Sound',
        value: settings.sound,
        onChanged: (sound) => onChanged((sound: sound)),
      ),
    ],
  );
}

void main() {
  /// Opens the settings dialog.
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
  }

  /// Picks the renderer that shows [text] in the open dialog.
  Future<void> pick(WidgetTester tester, String text) async {
    await tester.tap(find.byType(DropdownButton<SvgRenderer>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  /// Closes the open dialog with its Done button.
  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog picks the renderer that the story gets once it '
      'closes', (tester) async {
    final renderers = <SvgRenderer>[];
    await tester.pumpWidget(_game(renderers: renderers));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'Game');
    expect(find.byType(AppBar), findsNothing);
    expect(renderers.last, SvgRenderer.firstChoice);
    await open(tester);
    expect(find.text('Settings'), findsOneWidget);
    await pick(tester, 'Flame SVG');
    expect(renderers.last, SvgRenderer.firstChoice);
    await done(tester);
    expect(find.text('Settings'), findsNothing);
    expect(renderers.last, SvgRenderer.flameSvg);
    expect(find.text('story flameSvg true'), findsOneWidget);
  });

  testWidgets('without SVGs, the dialog shows Flame for Flame SVG', (
    tester,
  ) async {
    await tester.pumpWidget(_game(svgs: false));
    await open(tester);
    await pick(tester, 'Flame');
    expect(find.text('Flame SVG'), findsNothing);
    await done(tester);
    expect(find.text('story flameSvg true'), findsOneWidget);
  });

  testWidgets('the story is paused while the dialog shows, and gets its '
      'settings once it closes, however it closes', (tester) async {
    final ticking = <bool>[];
    await tester.pumpWidget(_game(ticking: ticking));
    expect(ticking.last, isTrue);
    await open(tester);
    expect(ticking.last, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('true'), findsOneWidget);
    // Outside the dialog, on the barrier.
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    expect(ticking.last, isTrue);
    expect(find.textContaining('false'), findsOneWidget);
    // Without a change, it goes on as it was.
    await open(tester);
    expect(ticking.last, isFalse);
    await done(tester);
    expect(ticking.last, isTrue);
    expect(find.textContaining('false'), findsOneWidget);
  });

  testWidgets('the story keeps the focus once the dialog closes', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _game(
        builder: () => Focus(
          focusNode: focusNode,
          autofocus: true,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await open(tester);
    await pick(tester, 'Flame SVG');
    await done(tester);
    expect(focusNode.hasFocus, isTrue);
  });
}
