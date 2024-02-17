import 'package:sqlite3_web/sqlite3_web.dart';

void main() async {
  final sqlite = await WebSqlite.open(
    worker: Uri.parse('worker.dart.js'),
    wasmModule: Uri.parse('sqlite3.wasm'),
  );

  final database = await sqlite.connect(
      'test', StorageMode.inMemory, AccessMode.throughDedicatedWorker);

  database.updates.listen(print);

  print('has database');

  await database.execute('create table foo (bar)');
  await database.execute('insert into foo VALUES (?)', ['Hello worker!']);
}
