import 'package:http/http.dart' as http;
import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  final fileSystem = await IndexedDbFileSystem.open(dbName: 'test');
  final response = await http.get(Uri.parse('sqlite3.wasm'));
  final sqlite3 = await WasmSqlite3.load(
      response.bodyBytes, SqliteEnvironment(fileSystem: fileSystem));
  final database = sqlite3.open('test');
  print('${database.userVersion} (should be 0)');
  database.userVersion = 1;
  print('${database.userVersion} (should be 1)');

  database.execute('CREATE TABLE IF NOT EXISTS users ( '
      'id INTEGER NOT NULL, '
      'name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, '
      'password TEXT NOT NULL, '
      'user_id INTEGER NOT NULL, '
      'currentCompanyId INTEGER NULL REFERENCES companies (id), '
      'PRIMARY KEY (id));');

  final prepared = database.prepare('INSERT INTO users '
      '(id, name, email, password, user_id) VALUES (?, ?, ?, ?, ?)');

  for (var i = 0; i < 200; i++) {
    prepared.execute(
      [
        BigInt.from(i),
        'name',
        'email${BigInt.from(i)}',
        'password',
        BigInt.from(i),
      ],
    );
  }

  database.select('SELECT * FROM users').forEach((element) {
    print(element.values);
  });

  database.dispose();
  //await fileSystem.close();
  await Future<void>.delayed(const Duration(milliseconds: 10000));
  fileSystem.printState();

  final fileSystem2 = await IndexedDbFileSystem.open(dbName: 'test');
  final sqlite32 = await WasmSqlite3.load(
      response.bodyBytes, SqliteEnvironment(fileSystem: fileSystem2));
  final database2 = sqlite32.open('test');
  print('${database2.userVersion} (should be 2)');

  database2.select('SELECT * FROM users').forEach((element) {
    print(element.values);
  });
}
