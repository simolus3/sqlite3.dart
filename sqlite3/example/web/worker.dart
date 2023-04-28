import 'dart:html';

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:sqlite3/src/constants.dart';
import 'package:sqlite3/src/vfs.dart';
import 'package:sqlite3/src/wasm/vfs/client.dart';
import 'package:sqlite3/src/wasm/vfs/worker.dart';

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

      final vfs = WasmVfs(workerOptions: options);
      final (file: file, outFlags: flags) =
          vfs.xOpen(Sqlite3Filename('/test'), SqlFlag.SQLITE_OPEN_CREATE);
      print('opened file $file, outflags $flags');

      print('size = ${file.xFileSize()}');
      file.xTruncate(1024);
      print('file after truncate: ${file.xFileSize()}');

      file.xClose();
      print('closed file');
    } else {
      final message = data as WorkerOptions;

      final worker = await VfsWorker.create(message);

      self.postMessage(true);
      await worker.start();
    }
  });
}
