import 'dart:async';
import 'dart:developer';
import 'dart:html';

import 'package:sqlite3/wasm.dart';

void main() {
  final scope = DedicatedWorkerGlobalScope.instance;

  runZonedGuarded(() {
    scope.onMessage.listen((event) {
      final message = event.data as List;
      Future<void> test;

      final backend = message[0] as String;
      final wasmUri = Uri.parse(message[1] as String);
      debugger();

      switch (backend) {
        case 'memory':
          final fs = FileSystem.inMemory();

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
        case 'opfs':
          test = _runTest(
            open: () => OpfsFileSystem.loadFromStorage('worker-test'),
            close: (fs) async => fs.close(),
            wasmUri: wasmUri,
          );
          break;
        default:
          scope.postMessage([false]);
          return;
      }

      test.then((value) => scope.postMessage([true]));
    });
  }, (error, stack) {
    // Inform the calling test in sqlite3_test.dart about the error
    scope.postMessage([false, error.toString(), stack.toString()]);
  });
}

void _expect(bool condition, String reason) {
  if (!condition) {
    throw reason;
  }
}

Future<void> _runTest<T extends FileSystem>({
  required FutureOr<T> Function() open,
  required Future<void> Function(T fs) close,
  required Uri wasmUri,
}) async {
  final fileSystem = await open();

  final sqlite3 = await WasmSqlite3.loadFromUrl(
    wasmUri,
    environment: SqliteEnvironment(fileSystem: fileSystem),
  );

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
  final sqlite32 = await WasmSqlite3.loadFromUrl(
    wasmUri,
    environment: SqliteEnvironment(fileSystem: fileSystem2),
  );
  final database2 = sqlite32.open('database');

  _expect(database2.userVersion == 1, 'Should be 1 after reload');
  _expect(database2.select('SELECT * FROM users').length == 200,
      'Should find 200 rows');
}
