import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart';

void main() {
  SqliteConnectionPool testPool({int readConnections = 5}) {
    final pool = createPool(
      directory: sandbox,
      readConnections: readConnections,
    );
    addTearDown(pool.close);
    return pool;
  }

  test('opening pools is synchronized', () async {
    const numIsolates = 10_000;
    final receiveControl = ReceivePort();
    var countOpened = 0;
    final allOpened = Completer();
    final closePorts = <SendPort>[];

    receiveControl.listen((message) {
      final (didOpen, receiveClose) = message as (bool, SendPort);
      if (didOpen) {
        countOpened++;
      }

      closePorts.add(receiveClose);
      if (closePorts.length == numIsolates) {
        allOpened.complete();
      }
    });

    // Spawn 10k isolates attempting to open the same pool.
    for (var i = 0; i < numIsolates; i++) {
      final notify = receiveControl.sendPort;
      _startIsolateForOpenTest(notify);
    }

    await allOpened.future;
    expect(countOpened, 1);
    for (final port in closePorts) {
      port.send(null);
    }
  });

  test('simple queries', () async {
    final pool = testPool();
    await pool.execute('CREATE TABLE foo (bar TEXT) STRICT;');
    expect(await pool.readQuery('SELECT * FROM foo'), isEmpty);

    await pool.execute('INSERT INTO foo DEFAULT VALUES;');
    expect(await pool.readQuery('SELECT * FROM foo'), hasLength(1));
  });

  test('does not allow concurrent writers', () async {
    final pool = testPool();

    final futures = <Future<void>>[];
    var writers = 0;
    for (var i = 0; i < 10_000; i++) {
      futures.add(
        Future(() async {
          final writer = await pool.writer();
          expect(writers += 1, 1);
          await pumpEventQueue(times: 5);
          expect(writers -= 1, 0);
          writer.returnLease();
        }),
      );
    }

    await Future.wait(futures);
  });

  test('allows concurrent readers', () async {
    final pool = testPool();
    {
      final exclusive = await pool.exclusiveAccess();
      await exclusive.writer.execute('CREATE TEMPORARY TABLE conn(id);');
      await exclusive.writer.execute('INSERT INTO conn VALUES (?)', ['writer']);

      for (final (i, reader) in exclusive.readers.indexed) {
        await reader.execute('CREATE TEMPORARY TABLE conn(id);');
        await reader.execute('INSERT INTO conn VALUES (?)', ['reader-$i']);
      }
      exclusive.close();
    }

    final futures = <Future<void>>[];

    final connectionDistribution = <String, int>{};
    for (var i = 0; i < 10_000; i++) {
      futures.add(
        Future(() async {
          final results = await pool.readQuery('SELECT id FROM conn');
          final id = results.single.columnAt(0) as String;
          connectionDistribution[id] = (connectionDistribution[id] ?? 0) + 1;
        }),
      );
    }

    await Future.wait(futures);
    expect(connectionDistribution['writer'], isNull);

    // Connections should be distributed somewhat evenly.
    expect(connectionDistribution.values.fold(0, (a, b) => a + b), 10_000);
    for (final amount in connectionDistribution.values) {
      expect(amount, lessThan(4000));
    }
  });

  test('cannot use after closing', () async {
    final pool = testPool();
    pool.close();

    expect(() => pool.writer(), throwsStateError);
    expect(() => pool.reader(), throwsStateError);
  });

  test('autocommit', () async {
    final pool = testPool();
    final db = await pool.writer();
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

    db.returnLease();
  });

  group('aborting request', () {
    test('writer abort', () async {
      final pool = testPool();
      final firstWriteDone = Completer();

      pool.writer().then((writer) async {
        await firstWriteDone.future;
        writer.returnLease();
      });

      final shouldThrow = pool.writer(abortSignal: Future.value());
      var secondLockGranted = false;
      pool.writer().then((writer) {
        secondLockGranted = true;
        writer.returnLease();
      });

      await expectLater(shouldThrow, throwsA(isA<PoolAbortException>()));

      await pumpEventQueue();
      expect(secondLockGranted, false);

      firstWriteDone.complete();
      await pumpEventQueue();
      expect(secondLockGranted, true);
    });

    test('reader abort', () async {
      final pool = testPool(readConnections: 1);

      final firstReadDone = Completer();
      pool.reader().then((reader) async {
        await firstReadDone.future;
        reader.returnLease();
      });

      final shouldThrow = pool.reader(abortSignal: Future.value());
      var secondReadGranted = false;
      pool.reader().then((reader) {
        secondReadGranted = true;
        reader.returnLease();
      });

      await expectLater(shouldThrow, throwsA(isA<PoolAbortException>()));

      // Aborting the request should not grant the subsequent waiter the mutex.
      await pumpEventQueue();
      expect(secondReadGranted, false);

      firstReadDone.complete();
      await pumpEventQueue();
      expect(secondReadGranted, true);
    });
  });

  group('cannot use database after returning lease', () {
    test('read', () async {
      final pool = testPool();
      final reader = await pool.reader();
      reader.returnLease();

      expect(reader.select('SELECT 1'), throwsStateError);
      expect(
        () => reader.unsafeRawDatabase.select('SELECT 1'),
        throwsStateError,
      );
    });

    test('write', () async {
      final pool = testPool();
      final writer = await pool.writer();
      writer.returnLease();

      await pumpEventQueue(times: 1);
      expect(writer.select('SELECT 1'), throwsStateError);
      expect(
        () => writer.unsafeRawDatabase.select('SELECT 1'),
        throwsStateError,
      );
    });

    test('exclusive', () async {
      final pool = testPool();
      final exclusive = await pool.exclusiveAccess();
      exclusive.close();

      expect(exclusive.writer.select('SELECT 1'), throwsStateError);
      for (final reader in exclusive.readers) {
        expect(reader.select('SELECT 1'), throwsStateError);
      }
    });
  });
}

SqliteConnectionPool createPool({
  required String directory,
  int readConnections = 5,
}) {
  Database openDatabase() {
    return sqlite3.open(p.join(directory, 'test.db'))
      ..execute('pragma journal_mode = wal;');
  }

  return SqliteConnectionPool.open(
    name: directory,
    openConnections: () => PoolConnections(openDatabase(), [
      for (var i = 0; i < readConnections; i++) openDatabase(),
    ]),
  );
}

void _startIsolateForOpenTest(SendPort notify) {
  Isolate.run(() async {
    var didOpenConnections = false;
    final receiveCloseInstruction = ReceivePort();

    final pool = SqliteConnectionPool.open(
      name: 'pool',
      openConnections: () {
        didOpenConnections = true;
        return PoolConnections(sqlite3.openInMemory(), []);
      },
    );

    notify.send((didOpenConnections, receiveCloseInstruction.sendPort));

    await receiveCloseInstruction.first;
    pool.close();
  });
}
