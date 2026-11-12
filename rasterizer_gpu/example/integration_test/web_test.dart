import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

/// Defines a [test], or on the web a [testWidgets] that runs [body] with
/// [WidgetTester.runAsync].
///
/// On the web, flutter drive reports only widget tests' failures, so a
/// failing [test] would pass.
void webTest(String description, FutureOr<void> Function() body) => kIsWeb
    ? testWidgets(description, (tester) async {
        await tester.runAsync(() async => body());
      })
    : test(description, body);
