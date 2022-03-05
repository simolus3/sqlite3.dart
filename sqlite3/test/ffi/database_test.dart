@Tags(['ffi'])
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Additional tests to `common_database_test.dart` that aren't supported on
/// the web.
void main() {
  late Database database;

  setUp(() => database = sqlite3.openInMemory());
  tearDown(() => database.dispose());

  test('can bind and retrieve 64 bit ints', () {
    const value = 1 << 63;

    final stmt = database.prepare('SELECT ?');
    final result = stmt.select(<int>[value]);
    expect(result, [
      {'?': value}
    ]);
  });

  test('open read-only', () async {
    final path = join('.dart_tool', 'sqlite3', 'test', 'read_only.db');
    // Make sure the path exists
    await Directory(dirname(path)).create(recursive: true);
    // but not the db
    if (File(path).existsSync()) {
      await File(path).delete();
    }

    // Opening a non-existent database should fail
    expect(
      () => sqlite3.open(path, mode: OpenMode.readOnly),
      throwsA(isA<SqliteException>()),
    );

    // Open in read-write mode to create the database
    var db = sqlite3.open(path);
    // Change the user version to test read-write access
    db.userVersion = 1;
    db.dispose();

    // Open in read-only
    db = sqlite3.open(path, mode: OpenMode.readOnly);

    // Change the user version to test read-only mode
    expect(
      () => db.userVersion = 2,
      throwsA(isA<SqliteException>()),
    );

    // Check that it has not changed
    expect(db.userVersion, 1);

    db.dispose();
  });

  group('update stream', () {
    late Database database;

    setUp(() {
      database = sqlite3.openInMemory()
        ..execute('CREATE TABLE tbl (a TEXT, b INT);');
    });

    tearDown(() => database.dispose());

    test('emits event after insert', () {
      expect(database.updates,
          emits(_update(SqliteUpdate(SqliteUpdateKind.insert, 'tbl', 1))));

      database.execute("INSERT INTO tbl VALUES ('', 1);");
    });

    test('emits event after update', () {
      database.execute("INSERT INTO tbl VALUES ('', 1);");

      expect(database.updates,
          emits(_update(SqliteUpdate(SqliteUpdateKind.update, 'tbl', 1))));

      database.execute("UPDATE tbl SET b = b + 1;");
    });

    test('emits event after delete', () {
      database.execute("INSERT INTO tbl VALUES ('', 1);");

      expect(database.updates,
          emits(_update(SqliteUpdate(SqliteUpdateKind.delete, 'tbl', 1))));

      database.execute("DELETE FROM tbl WHERE b = 1;");
    });

    test('removes callback when no listener exists', () async {
      database.execute("INSERT INTO tbl VALUES ('', 1);");

      final subscription =
          database.updates.listen(expectAsync1((data) {}, count: 0));

      // Pause the subscription, cause an update and resume. As no listener
      // exists, no event should have been received and buffered.
      subscription.pause();
      database.execute("DELETE FROM tbl WHERE b = 1;");
      subscription.resume();
      await pumpEventQueue();

      await subscription.cancel();
    });

    test('closes when disposing the database', () {
      expect(database.updates.listen(null).asFuture(null), completes);
      database.dispose();
    });
  });
}

Matcher _update(SqliteUpdate update) {
  return isA<SqliteUpdate>()
      .having((e) => e.kind, 'kind', update.kind)
      .having((e) => e.tableName, 'tableName', update.tableName)
      .having((e) => e.rowId, 'rowId', update.rowId);
}
