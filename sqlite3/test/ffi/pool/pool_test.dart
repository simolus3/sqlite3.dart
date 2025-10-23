@Tags(['ffi'])
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

void main() {
  Database openDatabase() {
    return sqlite3.open(p.join(d.sandbox, 'test.db'))
      ..execute('pragma journal_mode = wal;');
  }

  ConnectionPool createPool({int readConnections = 5}) {
    final pool = ConnectionPool(openDatabase(), [
      for (var i = 0; i < readConnections; i++) openDatabase(),
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

    final futures = <Future<void>>[];
    var writers = 0;
    for (var i = 0; i < 10_000; i++) {
      futures.add(
        pool.withWriter((db) async {
          expect(writers += 1, 1);
          await pumpEventQueue(times: 5);
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

  group('aborting request', () {
    test('writer grant', () async {
      final pool = createPool();
      // Immediate abort when a writer is available should call the callback.
      await pool.withWriter(expectAsync1((db) {}), abort: Future.value());
    });

    test('writer abort', () async {
      final pool = createPool();
      final firstWriteDone = Completer();

      pool.withWriter(
        expectAsync1((db) async {
          await firstWriteDone.future;
        }),
      );

      final abortedRequest = pool.withWriter(
        expectAsync1((db) {}, count: 0),
        abort: Future.value(),
      );

      var secondLockGranted = false;
      pool.withWriter(expectAsync1((db) => secondLockGranted = true));

      await expectLater(abortedRequest, throwsA(isA<PoolAbortException>()));

      // Aborting the request should not grant the subsequent waiter the mutex.
      await pumpEventQueue();
      expect(secondLockGranted, false);

      firstWriteDone.complete();
      await pumpEventQueue();
      expect(secondLockGranted, true);
    });

    test('reader grant', () async {
      final pool = createPool();
      // Immediate abort when a reader is available should call the callback.
      await pool.withReader(expectAsync1((db) {}), abort: Future.value());
    });

    test('reader abort', () async {
      final pool = createPool(readConnections: 1);

      final firstReadDone = Completer();
      pool.withReader(
        expectAsync1((db) async {
          await firstReadDone.future;
        }),
      );

      final abortedRequest = pool.withReader(
        expectAsync1((db) {}, count: 0),
        abort: Future.value(),
      );

      var secondReadGranted = false;
      pool.withReader(expectAsync1((db) => secondReadGranted = true));

      await expectLater(abortedRequest, throwsA(isA<PoolAbortException>()));

      // Aborting the request should not grant the subsequent waiter the mutex.
      await pumpEventQueue();
      expect(secondReadGranted, false);

      firstReadDone.complete();
      await pumpEventQueue();
      expect(secondReadGranted, true);
    });
  });

  group('server', () {
    test('write', () async {
      final pool = createPool();
      final server = pool.testServer();
      final completeLocalWrite = Completer();
      pool.withWriter((db) async {
        await completeLocalWrite.future;
      });

      var isolateWriteCompleted = false;
      final isolateFuture = server.port
          .isolateRun((pool) {
            return pool.execute('CREATE TABLE foo (bar TEXT);');
          })
          .whenComplete(() => isolateWriteCompleted = true);

      await pumpEventQueue();
      expect(isolateWriteCompleted, isFalse);

      completeLocalWrite.complete();
      await pumpEventQueue();
      await isolateFuture;
    });

    test('closing the isolate returns connection', () async {
      final pool = createPool();
      final server = pool.testServer();
      final grantedToRemote = ReceivePort();

      void takeForever((PoolConnectPort, SendPort) msg) async {
        final (connectPort, sendOnGrant) = msg;
        final pool = connectPort.connect();
        await pool.withWriter((db) async {
          sendOnGrant.send(null);
          await Completer<void>().future;
        });
      }

      final isolate = await Isolate.spawn(takeForever, (
        server.port,
        grantedToRemote.sendPort,
      ));
      await pumpEventQueue();

      var hasLocalWrite = false;
      await grantedToRemote.first;
      final secondWrite = pool.withWriter((db) async => hasLocalWrite = true);

      expect(hasLocalWrite, isFalse);
      await pumpEventQueue();
      expect(hasLocalWrite, isFalse);

      // Killing the isolate without returning the connection should still
      // return the connection.
      isolate.kill();
      await pumpEventQueue();
      await secondWrite;
    });

    test('can abort connections', () async {
      final pool = createPool(readConnections: 1);
      final server = pool.testServer();
      final completeLocal = Completer();
      pool.withReader((db) async {
        await completeLocal.future;
      });

      await expectLater(
        server.port.isolateRun(
          (pool) => pool.withReader((db) {}, abort: Future.value()),
        ),
        throwsA(isA<PoolAbortException>()),
      );

      completeLocal.complete();
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

extension on ConnectionPool {
  PoolServer testServer() {
    final server = PoolServer(this);
    addTearDown(server.close);
    return server;
  }
}

extension on PoolConnectPort {
  Future<T> isolateRun<T>(
    FutureOr<T> Function(ConnectionPool) computation,
  ) async {
    return Isolate.run(() => computation(connect()));
  }
}
