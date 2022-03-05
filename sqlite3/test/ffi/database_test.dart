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
}
