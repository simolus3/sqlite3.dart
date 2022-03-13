import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  final fs = await IndexedDbFileSystem.load('/db/');
  print('loaded fs');

  final response = await http.get(Uri.parse('sqlite3.wasm'));
  final sqlite = await WasmSqlite3.load(
      response.bodyBytes, SqliteEnvironment(fileSystem: fs));

  print('Version of sqlite used is ${sqlite.version}');

  print('opening a persistent database');
  var db = sqlite.open('/db/test.db');

  if (db.userVersion == 0) {
    db
      ..execute('CREATE TABLE foo (x TEXT);')
      ..execute("INSERT INTO foo VALUES ('foo'), ('bar');")
      ..userVersion = 1;
  }

  print(db.select('SELECT * FROM foo'));

  print('re-opening dataabse');
  db = sqlite.open('/db/test.db');
  print(db.select('SELECT * FROM foo'));
}
