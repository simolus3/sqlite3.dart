import 'package:sqlite3_web/sqlite3_web.dart';

void main() async {
  final sqlite = await WebSqlite.open(
    worker: Uri.parse('worker.dart.js'),
    wasmModule: Uri.parse('sqlite3.wasm'),
  );

  final database = await sqlite.connect(
      'test', StorageMode.inMemory, AccessMode.throughDedicatedWorker);
  print('has database');
  print(await database.select('select 1'));
}
