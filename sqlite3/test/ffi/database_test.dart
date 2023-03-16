@Tags(['ffi'])
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/ffi/implementation.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

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
    final path = d.path('read_only.db');

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

  group('backup', () {
    late String path;

    setUp(() {
      path = d.path('test.db');
    });

    test('detects if is in-memory database', () {
      final db1 = sqlite3.open(path) as FfiDatabaseImplementation;
      final db2 = sqlite3.openInMemory() as FfiDatabaseImplementation;

      expect(db1.isInMemory, isFalse);
      expect(db2.isInMemory, isTrue);

      db1.dispose();
      db2.dispose();
    });

    test('copy in-memory', () {
      final db1 = sqlite3.openInMemory();
      db1.execute('CREATE TABLE a(b INTEGER);');
      db1.execute('INSERT INTO a VALUES (1);');

      //Should not be included in copy
      final db2 = sqlite3.copyIntoMemory(db1);

      db1.execute('INSERT INTO a VALUES (2);');

      expect(db2.select('SELECT * FROM a'), hasLength(1));
      expect(db1.select('SELECT * FROM a'), hasLength(2));

      db1.dispose();
      db2.dispose();
    });

    test('restore from disk into memory', () {
      final db1 = sqlite3.open(path);
      db1.execute('CREATE TABLE a(b INTEGER);');
      db1.execute('INSERT INTO a VALUES (1);');

      final db2 = sqlite3.copyIntoMemory(db1);

      //Should not be included in copy
      db1.execute('INSERT INTO a VALUES (2);');

      expect(db2.select('SELECT * FROM a'), hasLength(1));
      expect(db1.select('SELECT * FROM a'), hasLength(2));

      db1.dispose();
      db2.dispose();
    });

    test('backup memory to disk', () async {
      final db1 = sqlite3.openInMemory();
      db1.execute('CREATE TABLE a(b INTEGER);');
      db1.execute('INSERT INTO a VALUES (1);');

      final db2 = sqlite3.open(path);

      final progressStream = db1.backup(db2);
      await expectLater(progressStream, emitsDone);

      //Should not be included in backup
      db1.execute('INSERT INTO a VALUES (2);');

      db1.dispose();
      db2.dispose();

      final db3 = sqlite3.open(path);

      expect(db3.select('SELECT * FROM a'), hasLength(1));

      db3.dispose();
    });

    test('backup disk to disk', () async {
      final pathFrom = d.path('test_from.db');
      Directory(dirname(pathFrom)).createSync(recursive: true);

      if (File(pathFrom).existsSync()) {
        File(pathFrom).deleteSync();
      }

      final db1 = sqlite3.open(pathFrom);

      db1.execute('CREATE TABLE a(b INTEGER);');
      db1.execute('INSERT INTO a VALUES (1);');

      final db2 = sqlite3.open(path);

      final progressStream = db1.backup(db2);
      await expectLater(
          progressStream, emitsInOrder(<Matcher>[emitsThrough(1), emitsDone]));

      //Should not be included in backup
      db1.execute('INSERT INTO a VALUES (2);');

      db1.dispose();
      db2.dispose();

      final db3 = sqlite3.open(path);

      expect(db3.select('SELECT * FROM a'), hasLength(1));

      db3.dispose();

      if (File(pathFrom).existsSync()) {
        File(pathFrom).deleteSync();
      }
    });
  });
}
