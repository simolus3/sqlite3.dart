import 'dart:async';
import 'dart:html';
import 'dart:js_util';

import 'package:js/js.dart';
import 'package:sqlite3/wasm.dart';

@JS('Worker')
external Function get _worker;

void main() {
  final scope = DedicatedWorkerGlobalScope.instance;

  runZonedGuarded(() {
    scope.onMessage.listen((event) {
      // We're not calling .data because we don't want the result to be Dartified,
      // we want to keep the anonymous JS object.
      final rawData = getProperty<Object>(event, 'data');

      if (rawData is List) {
        final backend = rawData[0] as String;
        final wasmUri = Uri.parse(rawData[1] as String);

        _startTest(backend, wasmUri);
      } else {
        _startOpfsServer(rawData as WorkerOptions);
      }
    });
  }, (error, stack) {
    // Inform the calling test in sqlite3_test.dart about the error
    scope.postMessage([false, error.toString(), stack.toString()]);
  });
}

Future<void> _startTest(String fsImplementation, Uri wasmUri) async {
  Future<void> test;

  switch (fsImplementation) {
    case 'memory':
      final fs = InMemoryFileSystem();

      test = _runTest(
        open: () => fs,
        close: (fs) async {},
        wasmUri: wasmUri,
      );
      break;
    case 'indexeddb':
      test = _runTest(
        open: () => IndexedDbFileSystem.open(dbName: 'worker-test'),
        close: (fs) => fs.close(),
        wasmUri: wasmUri,
      );
      break;
    case 'opfs-simple':
      test = _runTest(
        open: () => SimpleOpfsFileSystem.loadFromStorage('worker-test'),
        close: (fs) async {
          fs.close();
        },
        wasmUri: wasmUri,
      );
      break;
    case 'opfs':
      test = _runTest(
        open: () async {
          // Start another worker with this entrypoint to launch the OPFS
          // server needed for synchronous access.
          final options = WasmVfs.createOptions();

          final worker = callConstructor<Worker>(
              _worker, [DedicatedWorkerGlobalScope.instance.location]);
          worker.postMessage(options);

          // Wait for the worker to acknowledge it being ready
          await worker.onMessage.first;

          return WasmVfs(workerOptions: options);
        },
        close: (vfs) async {
          vfs.close();
        },
        wasmUri: wasmUri,
      );
      break;
    default:
      DedicatedWorkerGlobalScope.instance.postMessage([false]);
      return;
  }

  await test;
  DedicatedWorkerGlobalScope.instance.postMessage([true]);
}

Future<void> _startOpfsServer(WorkerOptions options) async {
  final worker = await VfsWorker.create(options);

  // Inform the worker running the test that we're on it
  DedicatedWorkerGlobalScope.instance.postMessage(true);
  await worker.start();
}

void _expect(bool condition, String reason) {
  if (!condition) {
    throw reason;
  }
}

Future<void> _runTest<T extends VirtualFileSystem>({
  required FutureOr<T> Function() open,
  required Future<void> Function(T fs) close,
  required Uri wasmUri,
}) async {
  final fileSystem = await open();

  final sqlite3 = await WasmSqlite3.loadFromUrl(wasmUri);
  sqlite3.registerVirtualFileSystem(fileSystem, makeDefault: true);

  final database = sqlite3.open('database');
  _expect(database.userVersion == 0, 'Database version should be 0');
  database.userVersion = 1;
  _expect(database.userVersion == 1, 'Should be 1 after setting it');

  database.execute('CREATE TABLE IF NOT EXISTS users ( '
      'id INTEGER NOT NULL, '
      'name TEXT NOT NULL, '
      'email TEXT NOT NULL UNIQUE, '
      'user_id INTEGER NOT NULL, '
      'PRIMARY KEY (id));');

  final prepared = database.prepare('INSERT INTO users '
      '(id, name, email, user_id) VALUES (?, ?, ?, ?)');

  for (var i = 0; i < 200; i++) {
    prepared.execute(
      [
        BigInt.from(i),
        'name',
        'email${BigInt.from(i)}',
        BigInt.from(i),
      ],
    );
  }

  _expect(database.select('SELECT * FROM users').length == 200,
      'Should find 200 rows');

  database.dispose();

  // file-system should save reasonably quickly
  await close(fileSystem).timeout(const Duration(seconds: 1));

  final fileSystem2 = await open();
  final sqlite32 = await WasmSqlite3.loadFromUrl(wasmUri);
  sqlite32.registerVirtualFileSystem(fileSystem2, makeDefault: true);
  final database2 = sqlite32.open('database');

  _expect(database2.userVersion == 1, 'Should be 1 after reload');
  _expect(database2.select('SELECT * FROM users').length == 200,
      'Should find 200 rows');
  database2.dispose();
}
