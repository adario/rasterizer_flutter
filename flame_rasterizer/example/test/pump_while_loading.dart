import 'package:flutter_test/flutter_test.dart';

/// Pumps frames while [loading] returns true, for up to 10 s, which a busy
/// machine can take.
///
/// Assets and Box2D load outside the test's fake time, so it waits 10 ms of
/// real time before each frame.
Future<void> pumpWhileLoading(
  WidgetTester tester,
  bool Function() loading,
) async {
  final time = Stopwatch()..start();
  while (loading() && time.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}
