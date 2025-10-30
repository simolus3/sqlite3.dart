@TestOn('browser')
library;

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/client.dart';
import 'package:test/test.dart';

void main() {
  test('finds preferrable implementations', () {
    final all = DatabaseImplementation.values.toList();

    all.shuffle();
    all.sort(DatabaseClient.preferrableMode);

    expect(all, [
      DatabaseImplementation.opfsShared,
      DatabaseImplementation.opfsWithExternalLocks,
      DatabaseImplementation.opfsAtomics,
      DatabaseImplementation.indexedDbShared,
      DatabaseImplementation.indexedDbUnsafeWorker,
      DatabaseImplementation.indexedDbUnsafeLocal,
      DatabaseImplementation.inMemoryShared,
      DatabaseImplementation.inMemoryLocal,
    ]);
  });
}
