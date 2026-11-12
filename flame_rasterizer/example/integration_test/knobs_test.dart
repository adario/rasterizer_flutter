// Checks the example's knobs on a phone, where Widgetbook shows them in a
// sheet:
//   flutter test integration_test/knobs_test.dart -d <emulator-5554|iPhone>
//
// Every SVG must be reachable in the Svg menu, the last one too, above the
// system's bars. The Renderer knob's GPU entries must be active only where
// their renderers are supported. Tube Shooter's Glow knob must show with
// GPU (mesh).
import 'package:flame_rasterizer/flame_rasterizer.dart';
import 'package:flame_rasterizer_example/commons/material.dart';
import 'package:flame_rasterizer_example/main.dart';
import 'package:flame_rasterizer_example/stories/svg/svg_renderers_example.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  // Fully live, so that frames draw while the tests await: on OpenGL ES, the
  // self-tests wait for frames. As in the example's main, OpenGL ES is
  // allowed, so the self-tests run there.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  RasterizerGpu.allowOpenGles = true;

  testWidgets('the Svg menu reaches its last SVG', (tester) async {
    // Not pumpAndSettle, which never settles while the game animates.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=svg/svg-renderers'),
    );
    await settle();
    // On a phone, the knobs are in a sheet.
    if (find.text('Renderer').evaluate().isEmpty) {
      await tester.tap(find.text('Knobs'));
      await settle();
    }
    await tester.tap(find.byType(DropdownMenu<String>));
    await settle();
    final last = svgNames.last;
    await tester.scrollUntilVisible(
      find.text(last).last,
      100,
      scrollable: find.byType(Scrollable).last,
      duration: const Duration(milliseconds: 100),
    );
    await settle();
    expect(
      find.text(last).hitTestable(),
      findsWidgets,
      reason: '$last is out of reach',
    );
    await tester.tap(find.text(last).hitTestable().last);
    await settle();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, last);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the Renderer knob's GPU entries are active where their "
      'renderers are supported', (tester) async {
    // On OpenGL ES, a GPU entry is active once its renderer's self-test passes.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Whether GPU (mesh) is supported as the Renderer knob is first built,
    // when it picks its entry. On OpenGL ES, the self-test can pass during
    // the settle.
    final atFirst = SvgRenderer.rasterizer.supported;
    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=svg/svg-renderers'),
    );
    await settle();
    await tester.runAsync(() async {
      for (final renderer in [
        SvgRenderer.rasterizer,
        SvgRenderer.rasterizerAtlas,
      ]) {
        await RasterizerGpu.of(renderer.gpu).initialize();
      }
    });
    await settle();
    if (find.text('Renderer').evaluate().isEmpty) {
      await tester.tap(find.text('Knobs'));
      await settle();
    }
    final menu = tester.widget<DropdownMenu<SvgRenderer>>(
      find.byType(DropdownMenu<SvgRenderer>),
    );
    // ignore: avoid_print
    print(
      '  RASTERIZER_EXAMPLE knobs: mesh '
      '${RasterizerGpu.of(RasterizerBackend.mesh).support.name}, GPU '
      '${RasterizerGpu.support.name} '
      '(${atFirst ? 'at first' : 'after the self-tests'}), '
      'selected ${menu.initialSelection?.label}',
    );
    expect(
      [for (final entry in menu.dropdownMenuEntries) entry.label],
      ['GPU (mesh)', 'GPU (atlas)', 'Canvas', 'Flame SVG'],
    );
    for (final entry in menu.dropdownMenuEntries) {
      expect(entry.enabled, entry.value.supported, reason: entry.label);
    }
    // GPU (mesh) is the first choice where it's supported from the start.
    // Otherwise it's Canvas, which the game keeps once GPU (mesh) becomes
    // active.
    expect(
      menu.initialSelection,
      atFirst ? SvgRenderer.rasterizer : SvgRenderer.rasterizerCanvas,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Tube Shooter's Glow knob shows with GPU (mesh)", (tester) async {
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // So that GPU (mesh) is the first choice on OpenGL ES too.
    await tester.runAsync(
      () => RasterizerGpu.of(RasterizerBackend.mesh).initialize(),
    );
    await tester.pumpWidget(
      const FlameRasterizerExamples(initialRoute: '/?path=games/tube-shooter'),
    );
    await settle();
    // On a phone, the knobs are in a sheet, which builds the knobs below its
    // fold only as it scrolls.
    if (find.text('Renderer').evaluate().isEmpty) {
      await tester.tap(find.text('Knobs'));
      await settle();
    }
    if (find.text('Glow').evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text('Glow'),
        100,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
    }
    expect(find.text('Glow'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
