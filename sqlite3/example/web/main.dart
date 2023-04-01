import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  final fs = await IndexedDbFileSystem.open(dbName: 'test');
  print('loaded fs');

  final sqlite = await WasmSqlite3.loadFromUrl(
    Uri.parse('sqlite3.wasm'),
    environment: SqliteEnvironment(fileSystem: fs),
  );

  print('Version of sqlite used is ${sqlite.version}');

  print('opening a persistent database');
  var db = sqlite.open('test.db');

  if (db.userVersion == 0) {
    db
      ..execute('CREATE TABLE foo (x TEXT);')
      ..execute("INSERT INTO foo VALUES ('foo'), ('bar');")
      ..userVersion = 1;
  }

  print(db.select('SELECT * FROM foo'));
  await fs.flush();

  print('re-opening database');
  db = sqlite.open('test.db');
  print(db.select('SELECT * FROM foo'));
}
