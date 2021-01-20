import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('prepared statements can be used multiple times', () {
    final opened = sqlite3.openInMemory();
    opened.execute('CREATE TABLE tbl (a TEXT);');

    final stmt = opened.prepare('INSERT INTO tbl(a) VALUES(?)');
    stmt.execute(<String>['a']);
    stmt.execute(<String>['b']);
    stmt.dispose();

    final select = opened.prepare('SELECT * FROM tbl ORDER BY a');
    final result = select.select();

    expect(result, hasLength(2));
    expect(result.map((row) => row['a'] as String), ['a', 'b']);

    select.dispose();

    opened.dispose();
  });

  test('prepared statements cannot be used after close', () {
    final opened = sqlite3.openInMemory();

    final stmt = opened.prepare('SELECT ?');
    stmt.dispose();

    expect(stmt.select, throwsStateError);
    opened.dispose();
  });

  test('prepared statements cannot be used after db is closed', () {
    final opened = sqlite3.openInMemory();
    final stmt = opened.prepare('SELECT 1');
    opened.dispose();

    expect(stmt.select, throwsStateError);
  });

  Uint8List? _insertBlob(Uint8List? value) {
    final opened = sqlite3.openInMemory();
    opened.execute('CREATE TABLE tbl (x BLOB);');

    final insert = opened.prepare('INSERT INTO tbl VALUES (?)');
    insert.execute(<dynamic>[value]);
    insert.dispose();

    final select = opened.prepare('SELECT * FROM tbl');
    final result = select.select().single;

    opened.dispose();
    return result['x'] as Uint8List?;
  }

  test('can bind empty blob in prepared statements', () {
    expect(_insertBlob(Uint8List(0)), isEmpty);
  });

  test('can bind null blob in prepared statements', () {
    expect(_insertBlob(null), isNull);
  });

  test('can bind and read non-empty blob', () {
    const bytes = [1, 2, 3];
    expect(_insertBlob(Uint8List.fromList(bytes)), bytes);
  });

  test('throws when sql statement has an error', () {
    final db = sqlite3.openInMemory();
    db.execute('CREATE TABLE foo (id INTEGER CHECK (id > 10));');

    final stmt = db.prepare('INSERT INTO foo VALUES (9)');

    expect(
      stmt.execute,
      throwsA(isA<SqliteException>()
          .having((e) => e.message, 'message', contains('constraint failed'))),
    );

    db.dispose();
  });

  test(
    'throws an exception when iterating over result rows',
    () {
      final db = sqlite3.openInMemory()
        ..createFunction(
          functionName: 'raise_if_two',
          function: (args) {
            if (args.first == 2) {
              // ignore: only_throw_errors
              throw 'parameter was two';
            } else {
              return null;
            }
          },
        );

      db.execute(
          'CREATE TABLE tbl (a INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT)');
      // insert with a = 1..3
      for (var i = 0; i < 3; i++) {
        db.execute('INSERT INTO tbl DEFAULT VALUES');
      }

      final statement =
          db.prepare('SELECT raise_if_two(a) FROM tbl ORDER BY a');

      expect(
        statement.select,
        throwsA(isA<SqliteException>()
            .having((e) => e.message, 'message', contains('was two'))),
      );
    },
    onPlatform: const <String, dynamic>{
      'mac-os': Skip('TODO: User-defined functions cause a sigkill on MacOS')
    },
  );

  test('throws an exception when passing an invalid type as argument', () {
    final db = sqlite3.openInMemory();
    final stmt = db.prepare('SELECT ?');

    expect(() => stmt.execute(<bool>[false]), throwsArgumentError);
    db.dispose();
  });

  group('checks that the amount of parameters are correct', () {
    final db = sqlite3.openInMemory();

    test('when no parameters are set', () {
      final stmt = db.prepare('SELECT ?');
      expect(stmt.select, throwsA(isA<ArgumentError>()));
    });

    test('when the wrong amount of parameters are set', () {
      final stmt = db.prepare('SELECT ?, ?');
      expect(() => stmt.select(<int>[1]), throwsA(isA<ArgumentError>()));
    });

    tearDownAll(db.dispose);
  });

  test('select statements return expected value', () {
    final opened = sqlite3.openInMemory();

    final prepared = opened.prepare('SELECT ?');

    final result1 = prepared.select(<int>[1]);
    expect(result1.columnNames, ['?']);
    expect(result1.single.columnAt(0), 1);

    final result2 = prepared.select(<int>[2]);
    expect(result2.columnNames, ['?']);
    expect(result2.single.columnAt(0), 2);

    final result3 = prepared.select(<String>['']);
    expect(result3.columnNames, ['?']);
    expect(result3.single.columnAt(0), '');

    opened.dispose();
  });
}
