@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/src/wasm/sqlite3.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/client.dart';
import 'package:sqlite3_web/src/statement_cache.dart';
import 'package:test/test.dart';

import 'protocol_test.dart';

void main() {
  late String sqlite3WasmUri;
  late FakeWorkerEnvironment fakeWorkers;

  setUpAll(() async {
    final channel = spawnHybridUri('/test/asset_server.dart');
    final port = (await channel.stream.first as double).toInt();
    sqlite3WasmUri = 'http://localhost:$port/web/sqlite3.wasm';
  });

  setUp(() {
    fakeWorkers = FakeWorkerEnvironment();
    WebSqlite.workerEntrypoint(
      controller: _TestController(),
      environment: fakeWorkers,
    );
  });

  tearDown(() {
    fakeWorkers.close();
  });

  Future<RemoteDatabase> requestDatabase(
    String name,
    DatabaseImplementation implementation,
  ) async {
    final client = WebSqlite.open(
      workers: _FakeWorkerConnector(fakeWorkers),
      wasmModule: sqlite3WasmUri,
    );
    return (await client.connect(name, implementation)) as RemoteDatabase;
  }

  test('can open database', () async {
    final db = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );

    final results = await db.select('SELECT 1 as r;');
    expect(results.result, [
      {'r': 1},
    ]);
  });

  test('can share database between clients', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    final b = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    await a.execute('CREATE TABLE foo (bar TEXT);');
    await b.execute('INSERT INTO foo DEFAULT VALUES');
    final results = await a.select('SELECT * FROM foo');
    expect(results.result, hasLength(1));
  });

  test('releases resources for closed databases', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    await a.execute('CREATE TABLE foo (bar TEXT);');
    await a.dispose();

    final b = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    // This would fail if the in-memory database were reused.
    await b.execute('CREATE TABLE foo (bar TEXT);');
  });

  test('returns autocommit state', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    var res = await a.execute('BEGIN');
    expect(res.autocommit, isFalse);

    res = await a.execute('COMMIT');
    expect(res.autocommit, isTrue);
  });

  test('returns last insert rowid', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    await a.execute('CREATE TABLE foo (bar TEXT);');

    final insert = await a.execute(
      'INSERT INTO foo (bar) VALUES (?)',
      parameters: ['test'],
    );
    expect(insert.lastInsertRowid, 1);
  });

  test('check in transaction', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    await a.execute('CREATE TABLE foo (bar TEXT);');

    await a.execute('BEGIN');
    await a.execute(
      'INSERT INTO foo (bar) VALUES (?)',
      parameters: ['test'],
      checkInTransaction: true,
    );
    await a.execute('COMMIT');

    await expectLater(
      a.execute('SELECT 1', checkInTransaction: true),
      throwsA(isA<RemoteException>()),
    );
  });

  test('types of bound parameters', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );

    Future<void> expectType(Object? dartValue, String type) async {
      final result = await a.select(
        'SELECT typeof(?)',
        parameters: [dartValue],
      );

      final type = result.result.rows.single.single;
      expect(type, type);
    }

    await expectType(null, 'null');
    await expectType('foo', 'text');
    await expectType(3, 'integer');
    // When compiling to JavaScript, we can't tell 3 and 3.0 apart as distinct
    // types. The worker must support this for dart2wasm clients, though.
    await expectType(3.0, isDart2Wasm ? 'real' : 'integer');
    await expectType(3.1, 'real');
    await expectType(Uint8List(10), 'blob');
  });

  test('returns correct integer types', () async {
    final a = await requestDatabase(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    final result = await a.select('SELECT 3, 3.0');
    final [row] = result.result;
    expect(row.values, [3, 3.0]);

    if (isDart2Wasm) {
      // 3 and 3.0 are equal, but should still be represented as their correct
      // type. We can't test this on dart2js, which only uses a single number
      // type.
      expect(row.columnAt(0).runtimeType, int);
      expect(row.columnAt(1).runtimeType, double);
    }
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
          a.select('SELECT 1').whenComplete(() => hasResults = true),
        );
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

    test('can integrate with custom requests', () async {
      final obtainedA = Completer();
      final releaseA = Completer();

      final lockA = a.requestLock((token) async {
        obtainedA.complete();
        expect(
          (await a.customRequest(null, token: token) as JSString).toDart,
          'response',
        );
        await releaseA.future;
      });

      await obtainedA.future;
      await expectLater(
        b.customRequest(null, abortTrigger: Future.value(null)),
        throwsA(isA<AbortException>()),
      );

      releaseA.complete();
      await lockA;
      expect((await a.customRequest(null) as JSString).toDart, 'response');
    });
  });

  test('can close clients', () async {
    final client = WebSqlite.open(
      workers: _FakeWorkerConnector(fakeWorkers),
      wasmModule: sqlite3WasmUri,
    );
    final database = await client.connect(
      'foo',
      DatabaseImplementation.inMemoryShared,
    );
    await database.select('SELECT 1');
    client.close();

    // Closing the client should also mark the database as closed.
    await database.closed;
    await expectLater(
      () => database.select('SELECT 1'),
      throwsA(isA<ChannelClosedException>()),
    );

    // Additionally, the worker should close its environment.
    await pumpEventQueue();
    expect(fakeWorkers.isClosed, isTrue);
  });

  group('statement cache', () {
    late WasmSqlite3 sqlite3;

    setUpAll(() async {
      sqlite3 = await WasmSqlite3.loadFromUrlString(sqlite3WasmUri);
      sqlite3.registerVirtualFileSystem(
        InMemoryFileSystem(),
        makeDefault: true,
      );
    });

    CommonDatabase openDatabase() {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      return db;
    }

    test('can cache statements', () async {
      final db = openDatabase();
      final cache = PreparedStatementCache(size: 10);
      for (var i = 0; i < 10; i++) {
        cache.addNew(db.prepare('SELECT $i'));
      }

      for (var i = 0; i < 10; i++) {
        expect(cache.use('SELECT $i'), isNotNull);
      }

      cache.addNew(db.prepare('SELECT 10'));
      expect(cache.use('SELECT 0'), isNull);
      expect(cache.use('SELECT 1'), isNotNull);
    });

    test('lookup promotes entry to most recently used', () async {
      final db = openDatabase();
      final cache = PreparedStatementCache(size: 3);
      cache.addNew(db.prepare('SELECT 0'));
      cache.addNew(db.prepare('SELECT 1'));
      cache.addNew(db.prepare('SELECT 2'));

      expect(cache.use('SELECT 0'), isNotNull);

      // Oldest entry is SELECT 1, as SELECT 0 was just used.
      cache.addNew(db.prepare('SELECT 3'));
      expect(cache.use('SELECT 1'), isNull);
      expect(cache.use('SELECT 0'), isNotNull);
    });

    test('does not cache explain statements', () async {
      final client = WebSqlite.open(
        workers: _FakeWorkerConnector(fakeWorkers),
        wasmModule: sqlite3WasmUri,
      );
      final database = await client.connect(
        'foo',
        DatabaseImplementation.inMemoryShared,
        preparedStatementCacheSize: 64,
      );

      await database.execute(
        'create table test(id integer primary key, description text)',
      );
      await database.execute('create index i1 on test(description)');
      final firstPlan = await database.select(
        'explain query plan select * from test where description = ?',
        parameters: ['test'],
      );
      expect(
        firstPlan.result.single['detail'],
        contains('USING COVERING INDEX i1'),
      );

      await database.execute('drop index i1');
      final secondPlan = await database.select(
        'explain query plan select * from test where description = ?',
        parameters: ['test'],
      );
      expect(
        secondPlan.result.single['detail'],
        isNot(contains('USING COVERING INDEX i1')),
      );
    });
  });
}

final class _FakeWorkerConnector implements WorkerConnector {
  final FakeWorkerEnvironment _env;

  _FakeWorkerConnector(this._env);

  @override
  WorkerHandle? spawnDedicatedWorker() {
    return _env;
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    return _env;
  }
}

final class _TestController extends DatabaseController {
  @override
  Future<JSAny?> handleCustomRequest(
    ClientConnection connection,
    CustomClientRequest request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<WorkerDatabase> openDatabase(
    WasmSqlite3 sqlite3,
    String path,
    String vfs,
    JSAny? additionalData,
  ) async {
    return _TestDatabase(sqlite3.open(path, vfs: vfs));
  }
}

final class _TestDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  _TestDatabase(this.database);

  @override
  Future<JSAny?> handleCustomRequest(
    ClientConnection connection,
    CustomClientDatabaseRequest request,
  ) {
    return request.useLock(() {
      return 'response'.toJS;
    });
  }
}
