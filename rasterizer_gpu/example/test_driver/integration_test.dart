// Drives the integration tests on the web, with flutter drive: see the
// repository's tool/device_tests.py.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(writeResponseOnFailure: true);
