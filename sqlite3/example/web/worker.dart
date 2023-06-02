import 'dart:html';

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:sqlite3/wasm.dart';

@JS()
external bool get crossOriginIsolated;

void main() {
  print('worker main');
  final self = DedicatedWorkerGlobalScope.instance;

  if (!WasmVfs.supportsAtomicsAndSharedMemory) {
    throw UnsupportedError(
        'Missing support for Atomics or SharedArrayBuffer! Isolated: $crossOriginIsolated');
  }

  self.onMessage.listen((event) async {
    // We're not calling .data because we don't want the result to be Dartified,
    // we want to keep the anonymous JS object.
    final data = getProperty<Object>(event, 'data');

    if (data == 'start') {
      final options = WasmVfs.createOptions();
      final worker = Worker(''); // Clone this worker
      worker.postMessage(options);

      // Now, wait for the worker to report that it has been initialized.
      await worker.onMessage.first;

      final sqlite3 =
          await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.debug.wasm'));
      sqlite3.registerVirtualFileSystem(
          await SimpleOpfsFileSystem.loadFromStorage('worker-test'),
          makeDefault: true);

      sqlite3.open('/database')
        ..execute('pragma user_version = 1')
        ..execute('CREATE TABLE foo (bar INTEGER NOT NULL);')
        ..execute('INSERT INTO foo (bar) VALUES (?)', [3])
        ..dispose();

      final db = sqlite3.open('/database');
      print(db.select('SELECT * FROM foo'));
    } else {
      final message = data as WorkerOptions;

      final worker = await VfsWorker.create(message);

      self.postMessage(true);
      await worker.start();
    }
  });
}
