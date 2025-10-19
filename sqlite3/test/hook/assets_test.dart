@Tags(['ffi'])
library;

import 'package:sqlite3/src/hook/assets.dart';
import 'package:test/test.dart';

void main() {
  test('prebuilt libraries have no conflicting hash code', () {
    // We join the hash code against the outputDirectoryShared of hooks, so
    // there should be no collisions.
    final hashes = <String>{};
    for (final target in PrebuiltSqliteLibrary.all) {
      expect(hashes.add(target.dirname), isTrue);
    }
  });
}
