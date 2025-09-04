import 'dart:async';

import 'package:sqlite3/native_assets.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  final sqlite = sqlite3Native;

  Database openDatabase() {
    return sqlite.open(p.join(d.sandbox, 'test.db'))
      ..execute('pragma journal_mode = wal;');
  }

  ConnectionPool createPool() {
    final pool = ConnectionPool(openDatabase(), [
      for (var i = 0; i < 5; i++) openDatabase(),
    ]);
    addTearDown(pool.close);
    return pool;
  }

  test('simple queries', () async {
    final pool = createPool();
    await pool.execute('CREATE TABLE foo (bar TEXT) STRICT;');
    expect(await pool.readQuery('SELECT * FROM foo'), isEmpty);

    await pool.execute('INSERT INTO foo DEFAULT VALUES;');
    expect(await pool.readQuery('SELECT * FROM foo'), hasLength(1));
  });

  test('does not allow concurrent writers', () async {
    final pool = createPool();
    await pool.execute('CREATE TABLE foo (a INTEGER PRIMARY KEY) STRICT;');

    final futures = <Future<void>>[];
    var writers = 0;
    for (var i = 0; i < 10_000; i++) {
      futures.add(
        pool.withWriter((db) async {
          expect(writers += 1, 1);
          await db.execute('INSERT INTO foo DEFAULT VALUES');
          expect(writers -= 1, 0);
        }),
      );
    }

    await Future.wait(futures);
  });

  test('allows concurrent readers', () async {
    final pool = createPool();
    await pool.withAllConnections((readers, writer) async {
      await writer.execute('CREATE TEMPORARY TABLE conn(id);');
      await writer.execute('INSERT INTO conn VALUES (?)', ['writer']);

      for (final (i, reader) in readers.indexed) {
        await reader.execute('CREATE TEMPORARY TABLE conn(id);');
        await reader.execute('INSERT INTO conn VALUES (?)', ['reader-$i']);
      }
    });

    final futures = <Future<void>>[];

    final connectionDistribution = <String, int>{};
    for (var i = 0; i < 10_000; i++) {
      futures.add(
        pool.withReader((db) async {
          final conn = await db.select('SELECT id FROM conn');
          final id = conn.$1.single.columnAt(0) as String;
          connectionDistribution[id] = (connectionDistribution[id] ?? 0) + 1;
        }),
      );
    }

    await Future.wait(futures);

    // Connections should be distributed somewhat evenly.
    expect(connectionDistribution.values.fold(0, (a, b) => a + b), 10_000);
    for (final amount in connectionDistribution.values) {
      expect(amount, lessThan(4000));
    }
  });

  test('cannot use after closing', () async {
    final pool = createPool();
    await pool.close();

    expect(() => pool.withReader((db) {}), throwsStateError);
    expect(() => pool.withWriter((db) {}), throwsStateError);
  });

  test('autocommit', () async {
    final pool = createPool();
    await pool.withWriter((db) async {
      expect(await db.autocommit, isTrue);
      await db.execute('CREATE TABLE foo (id INTEGER NOT NULL PRIMARY KEY);');

      await db.execute('BEGIN');
      expect(await db.autocommit, isFalse);
      expect(
        (await db.execute('INSERT INTO foo DEFAULT VALUES;')).autoCommit,
        isFalse,
      );
      await expectLater(
        () => db.execute('INSERT OR ROLLBACK INTO foo VALUES (1);'),
        throwsA(isA<SqliteException>()),
      );

      expect(await db.autocommit, isTrue);
    });
  });

  group('cannot use database outside of callback', () {
    test('read', () async {
      final pool = createPool();
      final futureReader = Completer<LeasedDatabase>();
      pool.withReader(futureReader.complete);
      final reader = await futureReader.future;

      await pumpEventQueue(times: 1);
      expect(reader.select('SELECT 1'), throwsStateError);
    });

    test('write', () async {
      final pool = createPool();
      final futureWriter = Completer<LeasedDatabase>();
      pool.withWriter(futureWriter.complete);
      final writer = await futureWriter.future;

      await pumpEventQueue(times: 1);
      expect(writer.select('SELECT 1'), throwsStateError);
    });

    test('all', () async {
      final pool = createPool();
      final futureConnections =
          Completer<(List<LeasedDatabase>, LeasedDatabase)>();
      pool.withAllConnections((readers, writer) {
        futureConnections.complete((readers, writer));
      });

      final (readers, writer) = await futureConnections.future;
      await pumpEventQueue(times: 1);

      expect(writer.select('SELECT 1'), throwsStateError);
      for (final reader in readers) {
        expect(reader.select('SELECT 1'), throwsStateError);
      }
    });
  });
}
