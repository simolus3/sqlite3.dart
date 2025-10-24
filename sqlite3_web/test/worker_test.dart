import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/src/wasm/sqlite3.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/channel.dart';
import 'package:sqlite3_web/src/client.dart';
import 'package:sqlite3_web/src/protocol.dart';
import 'package:sqlite3_web/src/worker.dart';
import 'package:test/test.dart';

void main() {
  late Uri sqlite3WasmUri;
  late Local localEnv;

  setUpAll(() async {
    final channel = spawnHybridUri('/test/asset_server.dart');
    final port = (await channel.stream.first as double).toInt();
    sqlite3WasmUri = Uri.parse('http://localhost:$port/web/sqlite3.wasm');
  });

  setUp(() {
    localEnv = Local();
    WorkerRunner(_TestController(), environment: localEnv).handleRequests();
  });

  tearDown(() {
    localEnv.close();
  });

  Future<WorkerConnection> connectTo(Local local) async {
    final (endpoint, channel) = await createChannel();
    local.addTopLevelMessage(ConnectRequest(requestId: 0, endpoint: endpoint));
    final conn = WorkerConnection(channel, (_) async => null);

    addTearDown(() => conn.close());
    return conn;
  }

  Future<RemoteDatabase> requestDatabase(
      String name, DatabaseImplementation implementation) async {
    final conn = await connectTo(localEnv);
    return await conn.requestDatabase(
      wasmUri: sqlite3WasmUri,
      databaseName: name,
      implementation: implementation,
      onlyOpenVfs: false,
      additionalOptions: null,
    );
  }

  test('can open database', () async {
    final db =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);

    final results = await db.select('SELECT 1 as r;');
    expect(results.result, [
      {'r': 1}
    ]);
  });

  test('can share database between clients', () async {
    final a =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    final b =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    await a.execute('CREATE TABLE foo (bar TEXT);');
    await b.execute('INSERT INTO foo DEFAULT VALUES');
    final results = await a.select('SELECT * FROM foo');
    expect(results.result, hasLength(1));
  });

  test('releases resources for closed databases', () async {
    final a =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    await a.execute('CREATE TABLE foo (bar TEXT);');
    await a.dispose();

    final b =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    // This would fail if the in-memory database were reused.
    await b.execute('CREATE TABLE foo (bar TEXT);');
  });

  test('returns autocommit state', () async {
    final a =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    var res = await a.execute('BEGIN');
    expect(res.autocommit, isFalse);

    res = await a.execute('COMMIT');
    expect(res.autocommit, isTrue);
  });

  test('returns last insert rowid', () async {
    final a =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    await a.execute('CREATE TABLE foo (bar TEXT);');

    final insert = await a
        .execute('INSERT INTO foo (bar) VALUES (?)', parameters: ['test']);
    expect(insert.lastInsertRowid, 1);
  });

  test('check in transaction', () async {
    final a =
        await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    await a.execute('CREATE TABLE foo (bar TEXT);');

    await a.execute('BEGIN');
    await a.execute(
      'INSERT INTO foo (bar) VALUES (?)',
      parameters: ['test'],
      checkInTransaction: true,
    );
    await a.execute('COMMIT');

    await expectLater(a.execute('SELECT 1', checkInTransaction: true),
        throwsA(isA<RemoteException>()));
  });

  group('locks', () {
    late RemoteDatabase a, b;

    setUp(() async {
      a = await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
      b = await requestDatabase('foo', DatabaseImplementation.inMemoryShared);
    });

    test('run sequentially', () async {
      final obtainedA = Completer();
      final releaseA = Completer();
      final obtainedB = Completer();

      a.requestLock((token) async {
        obtainedA.complete();
        await releaseA.future;
      });

      final futureB = b.requestLock((token) async {
        obtainedB.complete();
      });

      await obtainedA.future;
      expect(obtainedB.isCompleted, isFalse);
      await pumpEventQueue();
      expect(obtainedB.isCompleted, isFalse);

      releaseA.complete();
      await obtainedB.future;
      await futureB;
    });

    test('does not run statement while in lock', () async {
      final queryResult = Completer<DatabaseResult<ResultSet>>();
      var hasResults = false;

      await a.requestLock((token) async {
        // The token needs to be passed for statements to work.
        queryResult.complete(
            a.select('SELECT 1').whenComplete(() => hasResults = true));
        expect(hasResults, isFalse);
        await pumpEventQueue();
        expect(hasResults, isFalse);
      });

      final results = await queryResult.future;
      expect(results.result, hasLength(1));
    });

    test('can run statements in lock context', () async {
      await a.requestLock((token) async {
        final response = await a.select('SELECT 1', token: token);
        expect(response.result, hasLength(1));

        await a.execute('SELECT 1', token: token);
      });
    });

    test('closing database releases lock', () async {
      final obtainedA = Completer();
      a.requestLock((token) async {
        obtainedA.complete();
        // Never complete
        await Future.any([]);
      });
      await obtainedA.future;

      final lockB = b.requestLock((_) async {});
      await a.dispose();
      await lockB;
    });

    test('can cancel lock', () async {
      final obtainedA = Completer();
      final releaseA = Completer();
      final cancelB = Completer();

      final lockA = a.requestLock((token) async {
        obtainedA.complete();
        await releaseA.future;
      });

      await obtainedA.future;

      final lockB = b.requestLock((token) async {
        fail('should not grant lock');
      }, abortTrigger: cancelB.future);
      await pumpEventQueue();
      cancelB.complete();
      await expectLater(lockB, throwsA(isA<AbortException>()));

      releaseA.complete();
      await lockA;
    });

    test('does not cancel lock after it has been granted', () async {
      final obtainedA = Completer();
      final releaseA = Completer();
      final cancelA = Completer();

      final lockA = a.requestLock((token) async {
        obtainedA.complete();
        await releaseA.future;
      }, abortTrigger: cancelA.future);

      await obtainedA.future;
      cancelA.complete();
      await pumpEventQueue();
      releaseA.complete();
      await lockA;
    });

    test('can cancel statements', () async {
      final obtainedA = Completer();
      final releaseA = Completer();

      final lockA = a.requestLock((token) async {
        obtainedA.complete();
        await releaseA.future;
      });

      await obtainedA.future;
      await expectLater(
        b.select('SELECT 1', abortTrigger: Future.value(null)),
        throwsA(isA<AbortException>()),
      );
      await expectLater(
        b.execute('SELECT 1', abortTrigger: Future.value(null)),
        throwsA(isA<AbortException>()),
      );

      releaseA.complete();
      await lockA;
    });
  });
}

final class _TestController extends DatabaseController {
  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }

  @override
  Future<WorkerDatabase> openDatabase(WasmSqlite3 sqlite3, String path,
      String vfs, JSAny? additionalData) async {
    return _TestDatabase(sqlite3.open(path, vfs: vfs));
  }
}

final class _TestDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  _TestDatabase(this.database);

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}
