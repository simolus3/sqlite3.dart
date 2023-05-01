import 'dart:html';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:sqlite3/src/constants.dart';
import 'package:sqlite3/src/vfs.dart';
import 'package:sqlite3/src/wasm/vfs/async_opfs/client.dart';
import 'package:sqlite3/src/wasm/vfs/async_opfs/worker.dart';

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
      final opened =
          vfs.xOpen(Sqlite3Filename('/test'), SqlFlag.SQLITE_OPEN_CREATE);
      final file = opened.file;
      print('opened file $file, outflags ${opened.outFlags}');

      final buffer = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      file.xWrite(buffer, 0);

      buffer.fillRange(0, 6, 0);
      file.xRead(buffer, 0);
      print('Buffer after read = $buffer');

      print('size = ${file.xFileSize()}');
      file.xTruncate(1024);
      print('file after truncate: ${file.xFileSize()}');

      file.xClose();
      print('closed file');

      vfs.xDelete('/test', 0);
      print('deleted file');
    } else {
      final message = data as WorkerOptions;

      final worker = await VfsWorker.create(message);

      self.postMessage(true);
      await worker.start();
    }
  });
}
