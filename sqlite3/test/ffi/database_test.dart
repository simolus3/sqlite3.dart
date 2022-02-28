import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database database;

  setUp(() => database = sqlite3.openInMemory());
  tearDown(() => database.dispose());

  test('user version', () {
    expect(database.userVersion, 0);
    database.userVersion = 1;
    expect(database.userVersion, 1);
  });

  test("database can't be used after dispose", () {
    database.dispose();

    expect(() => database.execute('SELECT 1;'), throwsStateError);
  });

  test('disposing multiple times works', () {
    database.dispose();
    database.dispose(); // shouldn't throw or crash
  });

  test('getUpdatedRows', () {
    database
      ..execute('CREATE TABLE foo (bar INT);')
      ..execute('INSERT INTO foo VALUES (3), (4);');

    expect(database.getUpdatedRows(), 2);
  });

  test('last insert id', () {
    database.execute('CREATE TABLE tbl(a INTEGER PRIMARY KEY AUTOINCREMENT)');

    for (var i = 0; i < 5; i++) {
      database.execute('INSERT INTO tbl DEFAULT VALUES');
      expect(database.lastInsertRowId, i + 1);
    }
  });

  test('can bind and retrieve 64 bit ints', () {
    const value = 1 << 63;

    final stmt = database.prepare('SELECT ?');
    final result = stmt.select(<int>[value]);
    expect(result, [
      {'?': value}
    ]);
  });

  group('execute', () {
    test('can run multiple statements at once', () {
      database.execute('CREATE TABLE foo (a); CREATE TABLE bar (b);');

      final result = database
          .select('SELECT name FROM sqlite_master')
          .map((row) => row['name'] as String);
      expect(result, containsAll(<String>['foo', 'bar']));
    });

    test('can use parameters', () {
      database.execute('CREATE TABLE foo (a);');
      database.execute('INSERT INTO foo VALUES (?)', [123]);

      final result = database.select('SELECT * FROM foo');
      expect(result, hasLength(1));
      expect(result.single['a'], 123);
    });

    test('does not allow multiple statements with parameters', () {
      database.execute('CREATE TABLE foo (a);');

      expect(
          () => database.execute(
              'INSERT INTO foo VALUES (?); INSERT INTO foo VALUES (?);', [123]),
          throwsArgumentError);
    });

    final hasColumnMeta =
        open.openSqlite().providesSymbol('sqlite3_column_table_name');

    test('inner join with toTableColumnMap and computed column', () {
      database.execute('''
      CREATE TABLE foo (
        a INT
      );
      CREATE TABLE bar (
        b TEXT,
        a_ref INT,
        FOREIGN KEY (a_ref) REFERENCES foo (a)
      );
      ''');
      database.execute('INSERT INTO foo(a) VALUES (1), (2), (3);');
      database.execute(
          "INSERT INTO bar(b, a_ref) VALUES ('1', NULL), ('2', 2), ('3', 3);");

      final result = database.select(
        'SELECT *, foo.a > 2 is_greater_than_2 FROM foo'
        ' INNER JOIN bar bar_alias ON bar_alias.a_ref = foo.a;',
      );

      expect(result, [
        {'a': 2, 'b': '2', 'a_ref': 2, 'is_greater_than_2': 0},
        {'a': 3, 'b': '3', 'a_ref': 3, 'is_greater_than_2': 1},
      ]);

      expect(result.map((row) => row.toTableColumnMap()), [
        {
          null: {'is_greater_than_2': 0},
          'foo': {'a': 2},
          'bar': {'b': '2', 'a_ref': 2},
        },
        {
          null: {'is_greater_than_2': 1},
          'foo': {'a': 3},
          'bar': {'b': '3', 'a_ref': 3},
        },
      ]);
    },
        skip: hasColumnMeta
            ? null
            : 'sqlite3 was compiled without column metadata');
  });

  group('throws', () {
    test('when executing an invalid statement', () {
      database.execute('CREATE TABLE foo (bar INTEGER CHECK (bar > 10));');

      expect(
        () => database.execute('INSERT INTO foo VALUES (3);'),
        throwsA(const TypeMatcher<SqliteException>().having(
            (e) => e.message, 'message', contains('CHECK constraint failed'))),
      );
    });

    test('when preparing an invalid statement', () {
      expect(
        () => database.prepare('INSERT INTO foo VALUES (3);'),
        throwsA(const TypeMatcher<SqliteException>()
            .having((e) => e.message, 'message', contains('no such table'))),
      );
    });
  });

  test('violating constraint throws exception with extended error code', () {
    database.execute('CREATE TABLE tbl(a INTEGER NOT NULL)');

    final statement = database.prepare('INSERT INTO tbl DEFAULT VALUES');

    expect(
      statement.execute,
      throwsA(
        isA<SqliteException>().having(
            (e) => e.explanation, 'explanation', endsWith(' (code 1299)')),
      ),
    );
  });

  test('open shared in-memory instances', () {
    final db1 = sqlite3.open('file:test?mode=memory&cache=shared', uri: true);
    final db2 = sqlite3.open('file:test?mode=memory&cache=shared', uri: true);

    db1
      ..execute('CREATE TABLE tbl (a INTEGER NOT NULL);')
      ..execute('INSERT INTO tbl VALUES (1), (2), (3);');

    final result = db2.select('SELECT * FROM tbl');
    expect(result, hasLength(3));
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

  group(
    'user-defined functions',
    () {
      test('can read arguments of user defined functions', () {
        late List<Object?> readArguments;

        database.createFunction(
          functionName: 'test_fun',
          argumentCount: const AllowedArgumentCount(6),
          function: (args) {
            // copy since the args become invalid as soon as this function
            // finishes.
            readArguments = List.of(args);
            return null;
          },
        );

        database.execute(
            r'''SELECT test_fun(1, 2.5, 'hello world', X'ff00ff', X'', NULL)''');

        expect(readArguments, <dynamic>[
          1,
          2.5,
          'hello world',
          Uint8List.fromList([255, 0, 255]),
          Uint8List(0),
          null,
        ]);
      });

      test('throws when using a long function name', () {
        expect(
          () => database.createFunction(
              functionName: 'foo' * 100, function: (args) => null),
          throwsArgumentError,
        );
      });

      group('scalar return', () {
        test('null', () {
          database.createFunction(
            functionName: 'test_null',
            function: (args) => null,
            argumentCount: const AllowedArgumentCount(0),
          );
          final stmt = database.prepare('SELECT test_null() AS result');

          expect(stmt.select(), [
            {'result': null}
          ]);
        });

        test('integers', () {
          database.createFunction(
            functionName: 'test_int',
            function: (args) => 420,
            argumentCount: const AllowedArgumentCount(0),
          );
          final stmt = database.prepare('SELECT test_int() AS result');

          expect(stmt.select(), [
            {'result': 420}
          ]);
        });

        test('doubles', () {
          database.createFunction(
            functionName: 'test_double',
            function: (args) => 133.7,
            argumentCount: const AllowedArgumentCount(0),
          );
          final stmt = database.prepare('SELECT test_double() AS result');

          expect(stmt.select(), [
            {'result': 133.7}
          ]);
        });

        test('bytes', () {
          database.createFunction(
            functionName: 'test_blob',
            function: (args) => [1, 2, 3],
            argumentCount: const AllowedArgumentCount(0),
          );
          final stmt = database.prepare('SELECT test_blob() AS result');

          expect(stmt.select(), [
            {
              'result': [1, 2, 3]
            }
          ]);
        });

        test('text', () {
          database.createFunction(
            functionName: 'test_text',
            function: (args) => 'hello from Dart',
            argumentCount: const AllowedArgumentCount(0),
          );
          final stmt = database.prepare('SELECT test_text() AS result');

          expect(stmt.select(), [
            {'result': 'hello from Dart'}
          ]);
        });
      });

      test('aggregate functions', () {
        database
          ..execute('CREATE TABLE test (a INT, b TEXT);')
          ..execute('INSERT INTO test VALUES '
              "(1, 'hello world'), "
              "(2, 'foo'), "
              "(1, 'another'), "
              "(2, 'bar');");

        database.createAggregateFunction(
          functionName: 'sum_lengths',
          function: const _SummedStringLength(),
          argumentCount: const AllowedArgumentCount(1),
        );

        expect(
          database.select('SELECT a, sum_lengths(b) AS l FROM test GROUP BY a '
              'ORDER BY 2;'),
          [
            {'a': 2, 'l': 6 /* foo + bar */},
            {'a': 1, 'l': 18 /* hello world + another */},
          ],
        );
      });
    },
    onPlatform: const <String, dynamic>{
      'mac-os': Skip('TODO: User-defined functions cause a sigkill on MacOS')
    },
  );

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

  test('prepare does not throw for multiple statements by default', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    final stmt = db.prepare('SELECT 1; SELECT 2');
    expect(stmt.sql, 'SELECT 1;');
  });

  test('prepare throws with checkNoTail', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.dispose);

    expect(() => db.prepare('SELECT 1; SELECT 2', checkNoTail: true),
        throwsArgumentError);
  });

  group('prepareMultiple', () {
    late Database db;

    setUp(() => db = sqlite3.openInMemory());
    tearDown(() => db.dispose());

    test('can prepare multiple statements', () {
      final statements = db.prepareMultiple('SELECT 1; SELECT 2;');
      expect(statements, [_statement('SELECT 1;'), _statement(' SELECT 2;')]);
    });

    test('fails for trailing syntax error', () {
      expect(() => db.prepareMultiple('SELECT 1; error here '),
          throwsA(isA<SqliteException>()));
    });

    test('fails for syntax error in the middle', () {
      expect(() => db.prepareMultiple('SELECT 1; error here; SELECT 2;'),
          throwsA(isA<SqliteException>()));
    });

    group('edge-cases', () {
      test('empty string', () {
        expect(() => db.prepare(''), throwsArgumentError);
        expect(db.prepareMultiple(''), isEmpty);
      });

      test('whitespace only', () {
        expect(() => db.prepare('  '), throwsArgumentError);
        expect(() => db.prepare('/* oh hi */'), throwsArgumentError);

        expect(db.prepareMultiple('  '), isEmpty);
        expect(db.prepareMultiple('/* oh hi */'), isEmpty);
      });

      test('leading whitespace', () {
        final stmt =
            db.prepare('  /*wait for it*/ SELECT 1;', checkNoTail: true);
        expect(stmt.sql, '  /*wait for it*/ SELECT 1;');
      });

      test('trailing comment', () {
        final stmt = db.prepare('SELECT 1; /* done! */', checkNoTail: true);
        expect(stmt.sql, 'SELECT 1;');
      });

      test('whitespace between statements', () {
        final stmts = db.prepareMultiple('SELECT 1; /* and */ SELECT 2;');
        expect(stmts, hasLength(2));

        expect(stmts[0].sql, 'SELECT 1;');
        expect(stmts[1].sql, ' /* and */ SELECT 2;');
      });
    });
  });
}

Matcher _update(SqliteUpdate update) {
  return isA<SqliteUpdate>()
      .having((e) => e.kind, 'kind', update.kind)
      .having((e) => e.tableName, 'tableName', update.tableName)
      .having((e) => e.rowId, 'rowId', update.rowId);
}

Matcher _statement(String sql) {
  return isA<PreparedStatement>().having((e) => e.sql, 'sql', sql);
}

/// Aggregate function that counts the length of all string parameters it
/// receives.
class _SummedStringLength implements AggregateFunction<int> {
  const _SummedStringLength();

  @override
  AggregateContext<int> createContext() {
    return AggregateContext(0);
  }

  @override
  void step(List<Object?> arguments, AggregateContext<int> context) {
    if (arguments.length != 1) return;

    final arg = arguments.single;
    if (arg is String) {
      context.value += arg.length;
    }
  }

  @override
  Object finalize(AggregateContext<int> context) => context.value;
}
