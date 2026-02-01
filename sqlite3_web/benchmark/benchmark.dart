import 'dart:js_interop';

import 'package:async/async.dart';
import 'package:http/http.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:jaspr_riverpod/legacy.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/locks.dart';
import 'package:web/web.dart' hide Client;

import 'message.dart';

final class BenchmarkConfiguration {
  final DatabaseImplementation implementation;

  const BenchmarkConfiguration({required this.implementation});

  Future<void> delete(WebSqlite client) async {
    final storage = implementation.storage;
    if (storage != StorageMode.inMemory) {
      await client.deleteDatabase(name: databaseName, storage: storage);
    }
  }

  Future<Database> connect(WebSqlite client) async {
    return await client.connect(databaseName, implementation);
  }

  static const defaultConfig = BenchmarkConfiguration(
    implementation: DatabaseImplementation.inMemoryLocal,
  );

  static const databaseName = 'benchmark';
}

sealed class BenchmarkTarget {
  final BenchmarkConfiguration configuration;

  BenchmarkTarget(this.configuration);

  BenchmarkTarget changeConfig(BenchmarkConfiguration config);
}

/// Benchmarks for a single tab, running predefined SQL scripts on a fresh
/// database.
final class SingleTabBenchmarkTarget extends BenchmarkTarget {
  SingleTabBenchmarkTarget(super.configuration);

  @override
  SingleTabBenchmarkTarget changeConfig(BenchmarkConfiguration config) {
    return SingleTabBenchmarkTarget(config);
  }

  /// Names of benchmark scripts in `benchmark/sql/`.
  static const names = [
    'Test 1: 1000 INSERTs',
    'Test 2: 25000 INSERTs in a transaction',
    'Test 3: 25000 INSERTs into an indexed table',
    'Test 4: 100 SELECTs without an index',
    'Test 5: 100 SELECTs on a string comparison',
    'Test 6: Creating an index',
    'Test 7: 5000 SELECTs with an index',
    'Test 8: 1000 UPDATEs without an index',
    'Test 9: 25000 UPDATEs with an index',
    'Test 10: 25000 text UPDATEs with an index',
    'Test 11: INSERTs from a SELECT',
    'Test 12: DELETE without an index',
    'Test 13: DELETE with an index',
    'Test 14: A big INSERT after a big DELETE',
    'Test 15: A big DELETE followed by many small INSERTs',
    'Test 16: DROP TABLE',
  ];
}

/// Multi-tab / contention benchmarks are not yet supported.
///
/// The idea is to eventually aggregate results from individual tabs through the
/// shared worker.
final class MultiTabBenchmarkTarget extends BenchmarkTarget {
  MultiTabBenchmarkTarget(super.configuration);

  @override
  MultiTabBenchmarkTarget changeConfig(BenchmarkConfiguration config) {
    return MultiTabBenchmarkTarget(config);
  }
}

final class BenchmarkResult {
  final int? tab;
  final String name;

  /// Null if the benchmark is currently running.
  final Duration? runtime;

  BenchmarkResult(this.tab, this.name, this.runtime);

  String get description {
    final buffer = StringBuffer();
    if (tab case final tab?) {
      buffer.write('Tab $tab ');
    }

    buffer
      ..write(name)
      ..write(': ');
    if (runtime case final completedRuntime?) {
      buffer.write('${completedRuntime.inMilliseconds}ms');
    } else {
      buffer.write('running...');
    }

    return buffer.toString();
  }
}

final class BenchmarkState extends Notifier<Result<List<BenchmarkResult>>> {
  final _client = Client();

  @override
  Result<List<BenchmarkResult>> build() {
    return Result.value([]);
  }

  Future<void> runSingleTabBenchmarks(
    SingleTabBenchmarkTarget target,
    WebSqlite sqlite,
  ) async {
    try {
      await _runSingleTabBenchmarks(target, sqlite);
    } catch (e, s) {
      state = Result.error(e, s);
    }
  }

  Future<void> _runSingleTabBenchmarks(
    SingleTabBenchmarkTarget target,
    WebSqlite sqlite,
  ) async {
    final results = <BenchmarkResult>[];
    void publish() {
      state = Result.value(results.toList());
    }

    await target.configuration.delete(sqlite);

    publish();
    for (final (i, name) in SingleTabBenchmarkTarget.names.indexed) {
      results.add(BenchmarkResult(null, name, null));
      publish();

      final (sql, db) = await (
        _fetchBenchmarkSql(i),
        target.configuration.connect(sqlite),
      ).wait;

      results.removeLast();

      final stopwatch = Stopwatch()..start();
      await db.execute(sql);
      stopwatch.stop();

      results.add(BenchmarkResult(null, name, stopwatch.elapsed));
      publish();
    }
  }

  Future<String> _fetchBenchmarkSql(int index) async {
    // Files are named starting with benchmark1.slq
    final response = await _client.get(
      Uri.parse('sql/benchmark${index + 1}.sql'),
    );

    if (response.statusCode != 200) {
      throw StateError('Unexpected response: ${response.body}');
    }

    return response.body;
  }

  static final provider = NotifierProvider(BenchmarkState.new);
}

final class ClientState {
  final int tabId;
  final int numTabs;

  ClientState(this.tabId, this.numTabs);

  int get tabIdPlusOne => tabId + 1;
}

final class ClientStateNotifier extends Notifier<ClientState?> {
  final SharedWorker worker = SharedWorker('worker.dart.js'.toJS);

  ClientStateNotifier();

  @override
  ClientState? build() {
    final lockName =
        'tab-close-notification-${DateTime.now().millisecondsSinceEpoch}';
    WebLocks.instance!.request(lockName).then((held) {
      if (!ref.mounted) {
        return held.release();
      }

      worker.port.postMessage(
        WorkerMessage(
          type: ToWorkerMessageType.connectTab.name,
          payload: ConnectTab(lockName: lockName),
        ),
      );
      ref.onDispose(held.release);
    });

    worker.port.start();
    final subscription = EventStreamProviders.messageEvent
        .forTarget(worker.port)
        .listen((event) {
          final message = event.data as WorkerMessage;
          switch (ToClientMessageType.values.byName(message.type)) {
            case ToClientMessageType.tabId:
              final payload = message.payload as ReceiveTabId;
              state = ClientState(
                payload.index.toDartInt,
                payload.numTabs.toDartInt,
              );
          }
        });
    ref.onDispose(subscription.cancel);

    return null;
  }

  static final provider = NotifierProvider(ClientStateNotifier.new);
}

final sqlite3 = Provider((ref) {
  return WebSqlite.open(
    workers: _EncapsulatedWorkerConnector(),
    wasmModule: Uri.parse('sqlite3.wasm'),
  );
});

final featureDetectionResult = FutureProvider((ref) async {
  final impl = ref.watch(sqlite3);
  return await impl.runFeatureDetection();
});

final selectedTarget = StateProvider<BenchmarkTarget>((ref) {
  return SingleTabBenchmarkTarget(BenchmarkConfiguration.defaultConfig);
});

final class _EncapsulatedWorkerConnector implements WorkerConnector {
  final WorkerConnector _inner = WorkerConnector.defaultWorkers(
    Uri.parse('worker.dart.js'),
  );

  @override
  WorkerHandle? spawnDedicatedWorker() => _inner.spawnDedicatedWorker();

  @override
  WorkerHandle? spawnSharedWorker() {
    return switch (_inner.spawnSharedWorker()) {
      null => null,
      final worker => _EncapsulatedWorker(worker),
    };
  }
}

/// Wraps messages sent to workers in a [WorkerMessage] structure, allowing the
/// shared worker to be used for multiple purposes by indicating that messages
/// we're sending are from the `sqlite3_web` package.
final class _EncapsulatedWorker implements WorkerHandle {
  final WorkerHandle _inner;
  _EncapsulatedWorker(this._inner);

  @override
  EventTarget get targetForErrorEvents => _inner.targetForErrorEvents;

  @override
  void postMessage(JSAny? msg, JSObject transfer) {
    _inner.postMessage(
      WorkerMessage(type: ToWorkerMessageType.sqlite.name, payload: msg),
      transfer,
    );
  }
}
