import 'package:flutter/services.dart';

/// An asset bundle that loads each of the app's assets 10 ms late, in the
/// test's fake time.
///
/// In a test, assets otherwise load at once, before the test could remove
/// the game or send it a key.
class SlowBundle() extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return await rootBundle.load(key);
  }
}
